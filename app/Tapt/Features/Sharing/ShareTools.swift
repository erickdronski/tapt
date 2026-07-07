import SwiftUI
import UIKit

enum ShareTools {
    /// Rasterize a share card to a high-res image (1080x1920 at scale 3).
    @MainActor
    static func renderCard(_ pour: PourCard, scale: CGFloat = 3) -> UIImage? {
        let renderer = ImageRenderer(content: ShareCard(pour: pour))
        renderer.scale = scale
        return renderer.uiImage
    }

    /// Post straight to Instagram Stories via the documented pasteboard + URL scheme.
    /// Requires Info.plist `LSApplicationQueriesSchemes` to include `instagram-stories`
    /// and a Facebook App ID. See docs/08-SOCIAL.md. Returns false if IG is unavailable.
    @MainActor
    @discardableResult
    static func shareToInstagramStories(image: UIImage, facebookAppID: String) -> Bool {
        guard
            !facebookAppID.isEmpty,
            let url = URL(string: "instagram-stories://share?source_application=\(facebookAppID)"),
            UIApplication.shared.canOpenURL(url),
            let data = image.pngData()
        else { return false }

        let items: [String: Any] = ["com.instagram.sharedSticker.backgroundImage": data]
        UIPasteboard.general.setItems([items], options: [.expirationDate: Date().addingTimeInterval(300)])
        UIApplication.shared.open(url)
        return true
    }
}

/// A pour card with share controls: the system share sheet (Messages, IG feed, X, etc.)
/// plus a direct "Stories" button.
struct CardShareView: View {
    let pour: PourCard
    /// Set your Facebook App ID (docs/08-SOCIAL.md) to enable direct Instagram Stories.
    var facebookAppID: String = ""

    @State private var rendered: UIImage?
    @State private var igUnavailable = false

    var body: some View {
        VStack(spacing: 18) {
            ShareCard(pour: pour)
                .clipShape(RoundedRectangle(cornerRadius: 22))
                .overlay(RoundedRectangle(cornerRadius: 22).stroke(Brand.malt.opacity(0.15), lineWidth: 1))
                .shadow(color: Brand.malt.opacity(0.25), radius: 14, y: 8)
                .scaleEffect(0.68)
                .frame(height: 452)

            HStack(spacing: 12) {
                if let image = rendered {
                    ShareLink(item: Image(uiImage: image),
                              preview: SharePreview("My Tapt pour", image: Image(uiImage: image))) {
                        Label("Share", systemImage: "square.and.arrow.up")
                            .font(.system(.headline, design: .rounded))
                            .frame(maxWidth: .infinity).padding(.vertical, 14)
                            .background(Brand.gold, in: RoundedRectangle(cornerRadius: 14))
                            .foregroundStyle(Brand.malt)
                    }
                }
                Button {
                    guard let image = rendered else { return }
                    igUnavailable = !ShareTools.shareToInstagramStories(image: image, facebookAppID: facebookAppID)
                } label: {
                    Label("Stories", systemImage: "camera.circle.fill")
                        .font(.system(.headline, design: .rounded))
                        .frame(maxWidth: .infinity).padding(.vertical, 14)
                        .background(Brand.surface, in: RoundedRectangle(cornerRadius: 14))
                        .foregroundStyle(Brand.text)
                }
            }
            .padding(.horizontal)

            if igUnavailable {
                Text("Instagram Stories is not set up yet (needs a Facebook App ID). Use Share for now.")
                    .font(.caption).foregroundStyle(Brand.muted).multilineTextAlignment(.center).padding(.horizontal)
            }
        }
        .task { rendered = ShareTools.renderCard(pour) }
    }
}
