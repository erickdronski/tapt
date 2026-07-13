import SwiftUI
import ImageIO
import UIKit

/// Beer thumbnails come from Open Food Facts, whose CDN is slow (seconds per
/// image). Plain AsyncImage re-downloads on every cell reuse and keeps nothing
/// across launches, so grids crawl. This caches each decoded, downsampled image
/// in memory AND on disk keyed by url+size, so every image is fetched from the
/// slow origin exactly once, ever. Second sight (scroll back, relaunch) is
/// instant and offline.
actor TaptImageCache {
    static let shared = TaptImageCache()

    // Memory tier: decoded UIImages, thread-safe, bounded.
    private let memory: NSCache<NSString, UIImage> = {
        let c = NSCache<NSString, UIImage>()
        c.countLimit = 300
        c.totalCostLimit = 64 * 1_024 * 1_024
        return c
    }()
    private let dir: URL
    // Coalesce concurrent requests for the same key so a fast scroll doesn't
    // kick off ten downloads of the same thumbnail.
    private var inflight: [String: Task<UIImage?, Never>] = [:]

    private init() {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        dir = base.appendingPathComponent("beer-thumbs", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    private func key(_ url: String, _ maxPixel: CGFloat) -> String {
        "\(url)|\(Int(maxPixel.rounded()))"
    }
    private func diskURL(_ key: String) -> URL {
        // Deterministic across launches (Swift's String.hashValue is randomized
        // per process, so it can't name a persistent file). FNV-1a 64-bit.
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in key.utf8 { hash = (hash ^ UInt64(byte)) &* 0x100000001b3 }
        return dir.appendingPathComponent(String(hash, radix: 16) + ".jpg")
    }

    func image(for urlString: String, maxPixel: CGFloat) async -> UIImage? {
        let k = key(urlString, maxPixel)
        if let hit = memory.object(forKey: k as NSString) { return hit }
        if let existing = inflight[k] { return await existing.value }

        let file = diskURL(k)
        // Off-actor fetch (nonisolated static): concurrent downloads, the actor
        // only serializes the tiny memory/inflight bookkeeping.
        let task = Task<UIImage?, Never> { await Self.fetch(urlString, maxPixel: maxPixel, file: file) }
        inflight[k] = task
        let result = await task.value
        inflight[k] = nil
        if let result {
            let px = (result.cgImage?.width ?? 1) * (result.cgImage?.height ?? 1) * 4
            memory.setObject(result, forKey: k as NSString, cost: max(1, px))
        }
        return result
    }

    private nonisolated static func fetch(_ urlString: String, maxPixel: CGFloat, file: URL) async -> UIImage? {
        // Disk tier first.
        if let data = try? Data(contentsOf: file), let img = downsample(data, maxPixel: maxPixel) {
            return img
        }
        // Origin, once. Data task honors caching (URLSession.download bypasses it).
        guard let url = URL(string: urlString),
              let (data, resp) = try? await URLSession.shared.data(from: url),
              (resp as? HTTPURLResponse).map({ (200...299).contains($0.statusCode) }) ?? true,
              let img = downsample(data, maxPixel: maxPixel)
        else { return nil }
        try? data.write(to: file, options: .atomic)
        return img
    }

    /// Decode only the pixels the destination needs (a 400px OFF photo into a
    /// 44pt row is 8x too big to decode at full size).
    nonisolated static func downsample(_ data: Data, maxPixel: CGFloat) -> UIImage? {
        guard let src = CGImageSourceCreateWithData(data as CFData,
                                                    [kCGImageSourceShouldCache: false] as CFDictionary)
        else { return nil }
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: max(64, maxPixel)
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else { return nil }
        return UIImage(cgImage: cg)
    }
}

/// A beer thumbnail that loads through the cache. Shows the image once ready,
/// a soft placeholder before, and the glass glyph if there is genuinely no art.
struct CachedBeerImage: View {
    let url: String?
    /// Point size of the destination; the loader decodes to ~2x this.
    var targetPoints: CGFloat = 44
    var contentMode: ContentMode = .fit

    @State private var image: UIImage?
    @State private var settled = false

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable().aspectRatio(contentMode: contentMode)
            } else if settled {
                Image(systemName: "mug.fill")
                    .font(.system(size: targetPoints * 0.37))
                    .foregroundStyle(Brand.gold.opacity(0.7))
            } else {
                Brand.surface
            }
        }
        .task(id: url) { await load() }
    }

    private func load() async {
        image = nil
        settled = false
        guard let url, !url.isEmpty else { settled = true; return }
        let px = max(88, targetPoints * UIScreen.main.scale)
        let result = await TaptImageCache.shared.image(for: url, maxPixel: px)
        guard !Task.isCancelled else { return }
        withAnimation(.easeOut(duration: 0.2)) { image = result }
        settled = true
    }
}
