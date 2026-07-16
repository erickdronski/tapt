import SwiftUI
import UIKit

/// Product art is a reviewed Tapt cutout, never a raw source scene. The source
/// photo remains attributed in the catalog for processing and audit, but hands,
/// tables, packs, and cases cannot cross this customer-facing boundary.
enum BeerProductImagePolicy {
    private static let host = "qfwiizvqxrhjlthbjosz.supabase.co"
    private static let pathPrefix = "/storage/v1/object/public/beer-cutouts/"

    private static func isUUIDPNGPath(_ path: String) -> Bool {
        guard path.hasPrefix(pathPrefix) else { return false }
        let relative = String(path.dropFirst(pathPrefix.count))
        let parts = relative.split(separator: "/", omittingEmptySubsequences: false)
        let filename: Substring
        if parts.count == 1 {
            filename = parts[0]
        } else if parts.count == 2, parts[0] == "v2" {
            filename = parts[1]
        } else {
            return false
        }
        guard filename.hasSuffix(".png") else { return false }
        let stem = filename.dropLast(4)
        let groups = stem.split(separator: "-", omittingEmptySubsequences: false)
        guard groups.map(\.count) == [8, 4, 4, 4, 12] else { return false }
        return groups.joined().allSatisfy { "0123456789abcdef".contains($0) }
    }

    static func approvedURL(_ value: String?) -> URL? {
        guard let value, !value.isEmpty,
              let components = URLComponents(string: value),
              components.scheme == "https",
              components.host == host,
              components.port == nil,
              components.user == nil,
              components.password == nil,
              components.query == nil,
              components.fragment == nil,
              !components.percentEncodedPath.contains("%"),
              isUUIDPNGPath(components.path)
        else { return nil }
        return components.url
    }

    static func isApproved(_ value: String?) -> Bool {
        approvedURL(value) != nil
    }
}

/// Displays reviewed, background-removed product art or the canonical glass.
struct BeerImageView: View {
    let url: String?
    var contentMode: ContentMode = .fit
    var maxPixelSize: CGFloat = 900
    /// Style for the fallback glass so an imageless beer still reads true.
    var style: String? = nil

    @State private var display: UIImage?
    @State private var loaded = false

    private var loadIdentity: String {
        "\(url ?? "")|\(Int(maxPixelSize.rounded()))"
    }

    var body: some View {
        Group {
            if let image = display {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            } else if loaded {
                BeerGlassView(pour: 0.76, animatesPour: false, style: style)
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
        guard let remoteURL = BeerProductImagePolicy.approvedURL(url) else {
            loaded = true
            return
        }

        let image = await TaptImageCache.shared.image(
            for: remoteURL.absoluteString,
            maxPixel: maxPixelSize
        )
        guard !Task.isCancelled else { return }
        withAnimation(.easeOut(duration: 0.2)) { display = image }
        loaded = true
    }
}
