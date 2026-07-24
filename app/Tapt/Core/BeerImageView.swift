import SwiftUI
import UIKit

/// What a beer may show, in order of preference:
///   1. a reviewed Tapt cutout (background removed, sits clean on the surface), else
///   2. its real product photo from a trusted catalog source (Open Food Facts
///      product front, Wikimedia Commons) -- a genuine label beats a generic glass, else
///   3. a factual Tapt identity card built from the canonical glass and catalog facts.
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
        if parts.count == 3, parts[0] == "v4", isUUID(parts[1]) {
            let filename = parts[2]
            guard filename.hasSuffix(".png") else { return false }
            let hash = filename.dropLast(4)
            return hash.count == 64 && hash.allSatisfy { "0123456789abcdef".contains($0) }
        }
        let filename: Substring
        if parts.count == 1 {
            filename = parts[0]
        } else if parts.count == 2, parts[0] == "v2" || parts[0] == "v3" {
            filename = parts[1]
        } else {
            return false
        }
        guard filename.hasSuffix(".png") else { return false }
        return isUUID(filename.dropLast(4))
    }

    private static func isUUID(_ stem: Substring) -> Bool {
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
    /// cutout if we have one, otherwise the real source photo. Views use the
    /// factual identity treatment only when this is nil.
    static func displayURL(_ value: String?) -> URL? {
        displayAsset(value)?.url
    }
}

/// Displays reviewed cutouts, contained real-source photos, or a truthful Tapt
/// identity card built from the beer's catalog facts and canonical glass.
struct BeerImageView: View {
    let url: String?
    var contentMode: ContentMode = .fit
    var maxPixelSize: CGFloat = 900
    /// Style for the fallback glass so a beer without a product photo still reads true.
    var style: String? = nil
    var beerName: String? = nil
    var breweryName: String? = nil

    @State private var display: UIImage?
    @State private var assetKind: BeerProductImagePolicy.AssetKind?

    private var loadIdentity: String {
        "\(url ?? "")|\(Int(maxPixelSize.rounded()))"
    }

    var body: some View {
        Group {
            if let image = display {
                Group {
                    if assetKind == .trustedSource {
                        trustedSourcePresentation(image)
                    } else {
                        Image(uiImage: image)
                            .resizable()
                            .interpolation(.high)
                            .aspectRatio(contentMode: contentMode)
                    }
                }
                .transition(.opacity)
            } else {
                BeerIdentityArtwork(
                    beerName: beerName,
                    breweryName: breweryName,
                    style: style
                )
                .transition(.opacity)
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
        guard let asset = BeerProductImagePolicy.displayAsset(url) else {
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
    }
}

/// A polished catalog visual for beers whose exact package photo is not
/// available under usable rights. It uses only known catalog facts and the
/// canonical Tapt glass, so it never pretends to be a brewery label or package.
private struct BeerIdentityArtwork: View {
    let beerName: String?
    let breweryName: String?
    let style: String?

    private var title: String? { clean(beerName) }
    private var brewery: String? { clean(breweryName) }
    private var styleLabel: String { clean(style) ?? "Beer" }

    var body: some View {
        GeometryReader { proxy in
            let edge = min(proxy.size.width, proxy.size.height)
            let compact = edge < 58
            let medium = edge < 118
            let tint = StyleGlassTint.resolve(style)
            let radius = min(24, max(8, edge * 0.16))

            ZStack {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Brand.malt,
                                Color(hex: 0x2E1A0A),
                                tint.mid.opacity(0.58)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                Circle()
                    .fill(tint.top.opacity(0.24))
                    .frame(width: edge * 0.82, height: edge * 0.82)
                    .blur(radius: edge * 0.12)
                    .offset(x: edge * 0.35, y: -edge * 0.38)

                if compact {
                    ZStack(alignment: .bottomTrailing) {
                        BeerGlassView(pour: 0.78, animatesPour: false, style: style)
                            .padding(max(4, edge * 0.13))

                        if let monogram {
                            Text(edge < 42 ? String(monogram.prefix(1)) : monogram)
                                .font(.system(size: max(7, edge * 0.15), weight: .black, design: .rounded))
                                .foregroundStyle(Brand.malt)
                                .padding(.horizontal, max(3, edge * 0.06))
                                .padding(.vertical, max(1, edge * 0.025))
                                .background(Brand.gold, in: Capsule())
                                .overlay(Capsule().stroke(Brand.foam.opacity(0.32), lineWidth: 0.5))
                                .padding(max(3, edge * 0.07))
                        }
                    }
                } else {
                    VStack(spacing: medium ? 3 : 7) {
                        HStack(spacing: 4) {
                            Text("TAPT")
                                .foregroundStyle(Brand.foam)
                            Spacer(minLength: 2)
                            Text("POUR PROFILE")
                                .foregroundStyle(Brand.copper)
                        }
                        .font(.system(size: medium ? 6.5 : 9, weight: .black, design: .rounded))
                        .tracking(medium ? 0.5 : 0.9)

                        BeerGlassView(pour: 0.78, animatesPour: false, style: style)
                            .frame(maxHeight: medium ? edge * 0.52 : edge * 0.56)

                        if let title {
                            Text(title)
                                .font(.system(
                                    size: medium ? 9 : 16,
                                    weight: .black,
                                    design: .rounded
                                ))
                                .foregroundStyle(Brand.foam)
                                .multilineTextAlignment(.center)
                                .lineLimit(2)
                                .minimumScaleFactor(0.68)
                        }

                        Text([brewery, styleLabel].compactMap { $0 }.joined(separator: " / "))
                            .font(.system(
                                size: medium ? 5.5 : 8.5,
                                weight: .bold,
                                design: .rounded
                            ))
                            .foregroundStyle(Brand.foam.opacity(0.7))
                            .textCase(.uppercase)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                    }
                    .padding(medium ? 7 : 12)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(Brand.foam.opacity(0.12), lineWidth: 0.75)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityDescription)
    }

    private var accessibilityDescription: String {
        let identity = [title, brewery, clean(style)].compactMap { $0 }.joined(separator: ", ")
        return identity.isEmpty ? "Beer pour profile" : "Pour profile for \(identity)"
    }

    private var monogram: String? {
        guard let title else { return nil }
        let words = title.split { !$0.isLetter && !$0.isNumber }
        guard let first = words.first else { return nil }
        if words.count == 1 {
            return String(first.prefix(2)).uppercased()
        }
        return String(words.prefix(2).compactMap(\.first)).uppercased()
    }

    private func clean(_ value: String?) -> String? {
        guard let value else { return nil }
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty ? nil : normalized
    }
}
