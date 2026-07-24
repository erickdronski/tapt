import SwiftUI
import UIKit

/// What a beer may show, in order of preference:
///   1. a reviewed Tapt cutout (background removed, sits clean on the surface), else
///   2. its real product photo from a trusted catalog source (Open Food Facts
///      product front, Wikimedia Commons) -- a genuine label beats a generic glass, else
///   3. the style-true glass (handled by the views).
/// Cutouts stay the gold standard and marketing/share art is still cutout-only
/// (approvedURL), so the strict customer-facing boundary is preserved where it
/// matters; in-app browsing just no longer hides the real photos we already hold.
enum BeerProductImagePolicy {
    enum AssetKind: Equatable {
        case reviewedCutout
        case trustedSource
    }

    struct DisplayAsset: Equatable {
        let url: URL
        let kind: AssetKind
    }

    private static let host = "qfwiizvqxrhjlthbjosz.supabase.co"
    private static let pathPrefix = "/storage/v1/object/public/beer-cutouts/"

    // Trusted catalog photo sources. These are product-front databases, not
    // arbitrary scene hosts, so an unreviewed shot here is still a clean label.
    private static let sourceHosts: Set<String> = [
        "images.openfoodfacts.org",
        "upload.wikimedia.org",
        "commons.wikimedia.org"
    ]

    private static func isUUIDPNGPath(_ path: String) -> Bool {
        guard path.hasPrefix(pathPrefix) else { return false }
        let relative = String(path.dropFirst(pathPrefix.count))
        let parts = relative.split(separator: "/", omittingEmptySubsequences: false)
        let filename: Substring
        if parts.count == 1 {
            filename = parts[0]
        } else if parts.count == 2, parts[0] == "v2" || parts[0] == "v3" {
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

    private static func hasSafeImagePath(_ components: URLComponents) -> Bool {
        let encodedPath = components.percentEncodedPath.lowercased()
        guard !encodedPath.contains("%2f"),
              !encodedPath.contains("%5c"),
              !encodedPath.contains("%00"),
              !components.path.contains("\\")
        else { return false }

        return !components.path
            .split(separator: "/", omittingEmptySubsequences: false)
            .contains { $0 == "." || $0 == ".." }
    }

    private static func isImagePath(_ path: String) -> Bool {
        [".jpg", ".jpeg", ".png", ".webp"].contains { path.lowercased().hasSuffix($0) }
    }

    private static func hasAllowedWikimediaQuery(_ components: URLComponents) -> Bool {
        guard components.query != nil else { return true }
        guard let items = components.queryItems,
              items.count == 1,
              items[0].name == "width",
              let value = items[0].value,
              let width = Int(value),
              (1...4096).contains(width)
        else { return false }
        return true
    }

    /// A real product photo from a trusted catalog source (not a Tapt cutout).
    static func approvedSourceURL(_ value: String?) -> URL? {
        guard let value, !value.isEmpty,
              let c = URLComponents(string: value),
              c.scheme == "https",
              let host = c.host, sourceHosts.contains(host),
              c.port == nil,
              c.user == nil, c.password == nil,
              c.fragment == nil,
              hasSafeImagePath(c),
              isImagePath(c.path)
        else { return nil }

        switch host {
        case "images.openfoodfacts.org":
            guard c.path.hasPrefix("/images/products/"), c.query == nil else { return nil }
        case "upload.wikimedia.org":
            guard c.path.hasPrefix("/wikipedia/commons/"), c.query == nil else { return nil }
        case "commons.wikimedia.org":
            guard c.path.hasPrefix("/wiki/Special:FilePath/"),
                  hasAllowedWikimediaQuery(c)
            else { return nil }
        default:
            return nil
        }
        return c.url
    }

    static func displayAsset(_ value: String?) -> DisplayAsset? {
        if let url = approvedURL(value) {
            return DisplayAsset(url: url, kind: .reviewedCutout)
        }
        if let url = approvedSourceURL(value) {
            return DisplayAsset(url: url, kind: .trustedSource)
        }
        return nil
    }

    /// The URL a customer-facing product view should actually load: the reviewed
    /// cutout if we have one, otherwise the real source photo. Views fall back to
    /// the style glass only when this is nil.
    static func displayURL(_ value: String?) -> URL? {
        displayAsset(value)?.url
    }
}

/// Displays reviewed cutouts, contained real-source photos, or the canonical glass.
struct BeerImageView: View {
    let url: String?
    var contentMode: ContentMode = .fit
    var maxPixelSize: CGFloat = 900
    /// Style for the fallback glass so an imageless beer still reads true.
    var style: String? = nil

    @State private var display: UIImage?
    @State private var assetKind: BeerProductImagePolicy.AssetKind?
    @State private var loaded = false

    private var loadIdentity: String {
        "\(url ?? "")|\(Int(maxPixelSize.rounded()))"
    }

    var body: some View {
        Group {
            if let image = display {
                if assetKind == .trustedSource {
                    trustedSourcePresentation(image)
                } else {
                    Image(uiImage: image)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: contentMode)
                }
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

    private func trustedSourcePresentation(_ image: UIImage) -> some View {
        GeometryReader { proxy in
            let edge = min(proxy.size.width, proxy.size.height)
            let outerInset = min(5, max(1, edge * 0.04))
            let imageInset = min(10, max(2, edge * 0.08))
            let radius = min(18, max(6, edge * 0.18))

            ZStack {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 1.0, green: 0.995, blue: 0.975),
                                Color(red: 0.955, green: 0.945, blue: 0.91)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                Image(uiImage: image)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .padding(imageInset)
            }
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(Color.black.opacity(0.09), lineWidth: 0.75)
            }
            .shadow(
                color: Color.black.opacity(0.12),
                radius: min(8, max(2, edge * 0.04)),
                y: min(4, max(1, edge * 0.02))
            )
            .padding(outerInset)
        }
    }

    private func load() async {
        display = nil
        assetKind = nil
        loaded = false
        guard let asset = BeerProductImagePolicy.displayAsset(url) else {
            loaded = true
            return
        }

        let image = await TaptImageCache.shared.image(
            for: asset.url.absoluteString,
            maxPixel: maxPixelSize
        )
        guard !Task.isCancelled else { return }
        withAnimation(.easeOut(duration: 0.2)) {
            assetKind = asset.kind
            display = image
        }
        loaded = true
    }
}
