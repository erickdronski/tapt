import SwiftUI
import Vision
import CoreImage
import UIKit

/// Lifts the beer off its background on-device (iOS Vision), so raw Open Food Facts
/// photos (a bottle on a table, a can in a hand) render as a clean floating product.
/// Real photo, background removed -- never fabricated. Cached per URL so it runs once.
enum SubjectLift {
    // NSCache is internally thread-safe, so this shared instance is safe to use nonisolated.
    nonisolated(unsafe) private static let cache = NSCache<NSString, UIImage>()

    static func cached(_ key: String) -> UIImage? { cache.object(forKey: key as NSString) }
    static func store(_ key: String, _ img: UIImage) { cache.setObject(img, forKey: key as NSString) }

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

    @State private var display: UIImage?
    @State private var loaded = false

    var body: some View {
        Group {
            if let img = display {
                Image(uiImage: img).resizable().aspectRatio(contentMode: contentMode)
            } else if loaded {
                Image(systemName: "mug.fill").font(.system(size: 22)).foregroundStyle(Brand.gold.opacity(0.6))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Color.clear
            }
        }
        .task(id: url) { await load() }
    }

    private func load() async {
        display = nil; loaded = false
        guard let s = url, let u = URL(string: s) else { loaded = true; return }
        if let hit = SubjectLift.cached(s) { display = hit; loaded = true; return }
        guard let (data, _) = try? await URLSession.shared.data(from: u),
              let raw = UIImage(data: data) else { loaded = true; return }
        // show the raw photo immediately, then swap in the cut-out when ready
        display = raw
        loaded = true
        // Already-cut images (transparent PNGs from our storage) are used as-is.
        if hasAlpha(raw) { SubjectLift.store(s, raw); return }
        let cut = await Task.detached(priority: .userInitiated) { SubjectLift.lift(raw) }.value
        if let cut {
            SubjectLift.store(s, cut)
            await MainActor.run { withAnimation(.easeInOut(duration: 0.25)) { display = cut } }
        }
    }

    private func hasAlpha(_ img: UIImage) -> Bool {
        guard let a = img.cgImage?.alphaInfo else { return false }
        return !(a == .none || a == .noneSkipFirst || a == .noneSkipLast)
    }
}
