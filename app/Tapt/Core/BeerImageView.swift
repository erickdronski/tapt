import SwiftUI
import Vision
import CoreImage
import ImageIO
import UIKit

/// Lifts the beer off its background on-device (iOS Vision), so raw Open Food Facts
/// photos (a bottle on a table, a can in a hand) render as a clean floating product.
/// Real photo, background removed -- never fabricated. Cached per URL so it runs once.
enum SubjectLift {
    // NSCache is internally thread-safe, so this shared instance is safe to use nonisolated.
    nonisolated(unsafe) private static let cache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 160
        cache.totalCostLimit = 48 * 1_024 * 1_024
        return cache
    }()

    static func cached(_ key: String) -> UIImage? { cache.object(forKey: key as NSString) }
    static func store(_ key: String, _ img: UIImage) {
        let width = img.cgImage?.width ?? Int(img.size.width * img.scale)
        let height = img.cgImage?.height ?? Int(img.size.height * img.scale)
        cache.setObject(img, forKey: key as NSString, cost: max(1, width * height * 4))
    }

    /// Decodes only the pixels the destination can display. Catalog sources can
    /// be multi-megapixel photos, while most Tapt placements are compact rows.
    static func downsample(_ fileURL: URL, maxPixelSize: CGFloat) -> UIImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(fileURL as CFURL, sourceOptions) else {
            return nil
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: max(64, maxPixelSize)
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        return UIImage(cgImage: image)
    }

    static func hasAlpha(_ image: UIImage) -> Bool {
        guard let alpha = image.cgImage?.alphaInfo else { return false }
        return !(alpha == .none || alpha == .noneSkipFirst || alpha == .noneSkipLast)
    }

    /// Returns the subject cut out onto transparency, or nil if no clear subject.
    static func lift(_ image: UIImage) -> UIImage? {
        guard let cg = image.cgImage else { return nil }
        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(cgImage: cg, options: [:])
        do {
            try handler.perform([request])
            guard let result = request.results?.first, !result.allInstances.isEmpty else { return nil }
            let buffer = try result.generateMaskedImage(ofInstances: result.allInstances,
                                                         from: handler, croppedToInstancesExtent: true)
            let ci = CIImage(cvPixelBuffer: buffer)
            let ctx = CIContext(options: nil)
            guard let out = ctx.createCGImage(ci, from: ci.extent) else { return nil }
            return UIImage(cgImage: out)
        } catch {
            return nil
        }
    }
}

/// Loads a beer photo and shows it with its background removed (falls back to the raw
/// photo, then a glass glyph). Use everywhere a beer image appears.
struct BeerImageView: View {
    let url: String?
    var contentMode: ContentMode = .fit
    var maxPixelSize: CGFloat = 900
    var liftsSubject = true

    @State private var display: UIImage?
    @State private var loaded = false

    private var loadIdentity: String {
        "\(url ?? "")|\(Int(maxPixelSize.rounded()))|\(liftsSubject ? "lift" : "raw")"
    }

    var body: some View {
        Group {
            if let img = display {
                Image(uiImage: img).resizable().aspectRatio(contentMode: contentMode)
            } else if loaded {
                BeerGlassView(pour: 0.76, animatesPour: false)
                    .padding(6)
                    .accessibilityHidden(true)
            } else {
                Color.clear
            }
        }
        .task(id: loadIdentity) { await load() }
    }

    private func load() async {
        display = nil
        loaded = false
        guard let source = url, let remoteURL = URL(string: source) else {
            loaded = true
            return
        }
        let cacheKey = "\(source)|\(Int(maxPixelSize.rounded()))|\(liftsSubject ? "lift" : "raw")"
        if let hit = SubjectLift.cached(cacheKey) {
            display = hit
            loaded = true
            return
        }

        do {
            let (fileURL, response) = try await URLSession.shared.download(from: remoteURL)
            guard !Task.isCancelled else { return }
            if let response = response as? HTTPURLResponse,
               !(200...299).contains(response.statusCode) {
                loaded = true
                return
            }

            guard let raw = await Task.detached(priority: .userInitiated, operation: {
                SubjectLift.downsample(fileURL, maxPixelSize: maxPixelSize)
            }).value else {
                loaded = true
                return
            }
            guard !Task.isCancelled else { return }

            // Show the real source immediately, then swap in the lifted subject.
            display = raw
            loaded = true
            if !liftsSubject || SubjectLift.hasAlpha(raw) {
                SubjectLift.store(cacheKey, raw)
                return
            }

            let cut = await Task.detached(priority: .userInitiated) {
                SubjectLift.lift(raw)
            }.value
            guard !Task.isCancelled else { return }
            let final = cut ?? raw
            SubjectLift.store(cacheKey, final)
            if cut != nil {
                withAnimation(.easeInOut(duration: 0.25)) { display = final }
            }
        } catch {
            guard !Task.isCancelled else { return }
            loaded = true
        }
    }
}
