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

    /// A real product photo from a trusted catalog source (not a Tapt cutout).
    static func approvedSourceURL(_ value: String?) -> URL? {
        guard let value, !value.isEmpty,
              let c = URLComponents(string: value),
              c.scheme == "https",
              let host = c.host, sourceHosts.contains(host),
              c.user == nil, c.password == nil,
              c.fragment == nil
        else { return nil }
        // Wikimedia's Special:FilePath has no extension (and a ?width= query);
        // everything else must be a plain image path with no query string.
        let isWikimedia = host.hasSuffix("wikimedia.org")
        let path = c.path.lowercased()
        let looksLikeImage = [".jpg", ".jpeg", ".png", ".webp"].contains { path.hasSuffix($0) }
        guard isWikimedia || (c.query == nil && looksLikeImage) else { return nil }
        return c.url
    }

    /// The URL a customer-facing product view should actually load: the reviewed
    /// cutout if we have one, otherwise the real source photo. Views fall back to
    /// the style glass only when this is nil.
    static func displayURL(_ value: String?) -> URL? {
        approvedURL(value) ?? approvedSourceURL(value)
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
        guard let remoteURL = BeerProductImagePolicy.displayURL(url) else {
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
