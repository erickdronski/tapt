import SwiftUI
import UIKit
import Photos
import Supabase

enum ShareTools {
    /// Rasterize a share card (optionally with the real beer photo) to a high-res image.
    @MainActor
    static func renderCard(_ pour: PourCard, beerImage: UIImage? = nil, scale: CGFloat = 3) -> UIImage? {
        let renderer = ImageRenderer(content: ShareCard(pour: pour, beerImage: beerImage))
        renderer.scale = scale
        return renderer.uiImage
    }

    /// Load a beer photo for the card. ImageRenderer is synchronous, so we fetch the
    /// UIImage up front (from a known URL, or by looking the beer up by id).
    static func loadBeerImage(_ pour: PourCard) async -> UIImage? {
        var urlString = pour.imageUrl
        if urlString == nil, let id = pour.beerId {
            struct Row: Decodable { let label_image_url: String? }
            let row: Row? = try? await Supa.client.from("beer_catalog")
                .select("label_image_url").eq("id", value: id).single().execute().value
            urlString = row?.label_image_url
        }
        guard let s = urlString, let url = URL(string: s),
              let (data, _) = try? await URLSession.shared.data(from: url),
              let img = UIImage(data: data) else { return nil }
        return img
    }

    enum StoriesOutcome { case posted, savedOpenInstagram, savedNoInstagram }

    /// Post to Instagram Stories. With a Facebook App ID we hand the image straight to
    /// the Stories composer; without one we fall back to saving the card to Photos and
    /// opening Instagram so the drinker can post it in two taps.
    @MainActor
    static func postToStories(image: UIImage, facebookAppID: String) async -> StoriesOutcome {
        if !facebookAppID.isEmpty,
           let url = URL(string: "instagram-stories://share?source_application=\(facebookAppID)"),
           UIApplication.shared.canOpenURL(url),
           let data = image.pngData() {
            UIPasteboard.general.setItems(
                [["com.instagram.sharedSticker.backgroundImage": data]],
                options: [.expirationDate: Date().addingTimeInterval(300)])
            _ = await UIApplication.shared.open(url)
            return .posted
        }
        // Fallback: save + open the Instagram app.
        _ = await saveToPhotos(image: image)
        if let ig = URL(string: "instagram://app"), UIApplication.shared.canOpenURL(ig) {
            _ = await UIApplication.shared.open(ig)
            return .savedOpenInstagram
        }
        return .savedNoInstagram
    }

    /// Save the card to the photo library, requesting add-only permission first.
    @discardableResult
    static func saveToPhotos(image: UIImage) async -> Bool {
        let status = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        let granted: Bool
        switch status {
        case .authorized, .limited: granted = true
        case .notDetermined:
            granted = await withCheckedContinuation { cont in
                PHPhotoLibrary.requestAuthorization(for: .addOnly) { s in
                    cont.resume(returning: s == .authorized || s == .limited)
                }
            }
        default: granted = false
        }
        guard granted else { return false }
        return await withCheckedContinuation { cont in
            PHPhotoLibrary.shared().performChanges({
                PHAssetChangeRequest.creationRequestForAsset(from: image)
            }, completionHandler: { ok, _ in cont.resume(returning: ok) })
        }
    }
}

/// A pour card with share controls: the system share sheet, a direct Instagram Stories
/// button, and Save to Photos. Loads the real beer photo before rendering.
struct CardShareView: View {
    let pour: PourCard
    /// Set your Facebook App ID (docs/08-SOCIAL.md) to enable direct Instagram Stories.
    var facebookAppID: String = ""

    @State private var beerImage: UIImage?
    @State private var rendered: UIImage?
    @State private var note: String?
    @State private var savedOK = false
    @State private var working = false

    var body: some View {
        VStack(spacing: 16) {
            ShareCard(pour: pour, beerImage: beerImage)
                .clipShape(RoundedRectangle(cornerRadius: 22))
                .overlay(RoundedRectangle(cornerRadius: 22).stroke(Brand.malt.opacity(0.15), lineWidth: 1))
                .shadow(color: Brand.malt.opacity(0.25), radius: 14, y: 8)
                .scaleEffect(0.8)
                .frame(height: 530)

            HStack(spacing: 10) {
                if let image = rendered {
                    ShareLink(item: Image(uiImage: image),
                              preview: SharePreview("My Tapt pour", image: Image(uiImage: image))) {
                        control("Share", "square.and.arrow.up", Brand.gold, Brand.malt)
                    }
                }
                Button {
                    Task { await postStories() }
                } label: { control("Stories", "camera.circle.fill", Brand.surface, Brand.text) }
                    .disabled(rendered == nil || working)

                Button {
                    Task { await save() }
                } label: {
                    control(savedOK ? "Saved" : "Save", savedOK ? "checkmark" : "square.and.arrow.down",
                            Brand.surface, savedOK ? Brand.hop : Brand.text)
                }
                .disabled(rendered == nil || working)
            }
            .padding(.horizontal)

            if let note {
                Text(note).font(.caption).foregroundStyle(Brand.muted)
                    .multilineTextAlignment(.center).padding(.horizontal)
            }
        }
        .task {
            beerImage = await ShareTools.loadBeerImage(pour)
            rendered = await MainActor.run { ShareTools.renderCard(pour, beerImage: beerImage) }
        }
    }

    private func control(_ title: String, _ icon: String, _ bg: Color, _ fg: Color) -> some View {
        Label(title, systemImage: icon)
            .font(.system(.subheadline, design: .rounded).weight(.bold))
            .frame(maxWidth: .infinity).padding(.vertical, 13)
            .background(bg, in: RoundedRectangle(cornerRadius: 14))
            .foregroundStyle(fg)
    }

    private func postStories() async {
        guard let image = rendered else { return }
        working = true; note = nil
        switch await ShareTools.postToStories(image: image, facebookAppID: facebookAppID) {
        case .posted: break
        case .savedOpenInstagram: note = "Saved to Photos and opened Instagram. Add it to your story."
        case .savedNoInstagram: note = "Saved to Photos. Install Instagram to post it to your story."
        }
        working = false
    }

    private func save() async {
        guard let image = rendered else { return }
        working = true
        savedOK = await ShareTools.saveToPhotos(image: image)
        note = savedOK ? "Saved to your Photos." : "Couldn't save. Allow photo access in Settings."
        working = false
    }
}
