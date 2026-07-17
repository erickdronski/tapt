import SwiftUI
import PhotosUI

/// One self-contained sheet to edit everything about your identity: profile
/// photo, display name, and handle. Photo upload lives here (an explicit
/// "Change photo" button, not a hidden tap target), and because the whole
/// flow is inside this sheet it never gets dismissed by the profile screen's
/// background reloads. Validation is server-side (set_profile_identity); the
/// photo goes through moderation before it becomes public.
struct EditIdentityView: View {
    @Environment(Session.self) private var session
    @Environment(\.dismiss) private var dismiss
    let initial: ProfileService.MyProfile?
    var onSaved: (ProfileService.MyProfile) -> Void

    @State private var name = ""
    @State private var handle = ""
    @State private var saving = false
    @State private var error: String?

    // Photo state, self-contained in the sheet.
    @State private var pickedItem: PhotosPickerItem?
    @State private var localPreview: UIImage?
    @State private var pendingAvatarUrl: String?
    @State private var moderationStatus: String = "none"
    @State private var uploading = false
    @State private var photoError: String?

    private var currentAvatarUrl: String? { pendingAvatarUrl ?? initial?.avatarUrl }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(spacing: 12) {
                        avatar
                        PhotosPicker(selection: $pickedItem, matching: .images) {
                            Label(uploading ? "Uploading…" : "Change photo",
                                  systemImage: uploading ? "arrow.triangle.2.circlepath" : "camera.fill")
                                .font(.system(.subheadline, design: .rounded).weight(.bold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 11)
                                .background(Brand.gold, in: RoundedRectangle(cornerRadius: 12))
                                .foregroundStyle(Brand.malt)
                        }
                        .buttonStyle(.plain)
                        .disabled(uploading)

                        if let photoError {
                            Text(photoError).font(.caption).foregroundStyle(.red)
                        } else if ["pending", "processing"].contains(moderationStatus) {
                            Label("Photo saved. It goes live once it passes review.",
                                  systemImage: "clock.badge.checkmark")
                                .font(.caption).foregroundStyle(Brand.muted)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .listRowInsets(EdgeInsets(top: 14, leading: 16, bottom: 14, trailing: 16))
                }

                Section("Display name") {
                    TextField("Your name", text: $name).textInputAutocapitalization(.words)
                }
                Section {
                    HStack {
                        Text("@").foregroundStyle(Brand.muted)
                        TextField("handle", text: $handle)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }
                } header: {
                    Text("Handle")
                } footer: {
                    Text("3 to 20 characters: letters, numbers, underscore. This is how friends find you.")
                }
                if let error {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red).font(.footnote)
                    }
                }
            }
            .navigationTitle("Edit profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(saving ? "Saving…" : "Save") { save() }.disabled(saving || uploading)
                }
            }
            .onAppear {
                name = initial?.displayName ?? ""
                handle = initial?.handle ?? ""
                pendingAvatarUrl = initial?.pendingAvatarUrl
                moderationStatus = initial?.avatarModerationStatus ?? "none"
            }
            .onChange(of: pickedItem) { _, item in Task { await uploadPhoto(item) } }
        }
    }

    private var avatar: some View {
        Group {
            if let img = localPreview {
                Image(uiImage: img).resizable().scaledToFill()
            } else if let u = currentAvatarUrl, let url = URL(string: u) {
                AsyncImage(url: url) { $0.resizable().scaledToFill() } placeholder: { initials }
            } else {
                initials
            }
        }
        .frame(width: 96, height: 96)
        .clipShape(Circle())
        .overlay(Circle().stroke(Brand.gold, lineWidth: 2))
    }

    private var initials: some View {
        Circle().fill(Brand.gold).overlay(
            Text(String((name.isEmpty ? "You" : name).prefix(1)).uppercased())
                .font(.system(size: 40, weight: .heavy, design: .rounded))
                .foregroundStyle(Brand.malt))
    }

    /// Downscale to a <=512px JPEG, upload, show it immediately as a local
    /// preview, and reflect the pending moderation state. Nothing is invented:
    /// only a real uploaded image is stored.
    private func uploadPhoto(_ item: PhotosPickerItem?) async {
        guard let item, let id = session.user?.id else { return }
        uploading = true
        photoError = nil
        defer { uploading = false }
        do {
            guard let data = try await item.loadTransferable(type: Data.self),
                  let ui = UIImage(data: data) else {
                photoError = "That photo could not be read. Try another."
                return
            }
            let side: CGFloat = 512
            let scale = min(1, side / max(ui.size.width, ui.size.height))
            let target = CGSize(width: ui.size.width * scale, height: ui.size.height * scale)
            let resized = UIGraphicsImageRenderer(size: target).image { _ in
                ui.draw(in: CGRect(origin: .zero, size: target))
            }
            guard let jpeg = resized.jpegData(compressionQuality: 0.8) else {
                photoError = "That photo could not be prepared. Try another."
                return
            }
            let url = try await ProfileService.uploadAvatar(jpeg, userId: id)
            localPreview = resized
            pendingAvatarUrl = url
            moderationStatus = "pending"
            // Reflect the pending photo on the profile screen right away.
            onSaved(ProfileService.MyProfile(
                displayName: initial?.displayName, handle: initial?.handle,
                avatarUrl: initial?.avatarUrl, pendingAvatarUrl: url,
                avatarModerationStatus: "pending"))
        } catch {
            photoError = "Your photo did not upload. Check your connection and try again."
        }
    }

    private func save() {
        saving = true; error = nil
        Task {
            do {
                try await ProfileService.setIdentity(
                    displayName: name.trimmingCharacters(in: .whitespaces),
                    handle: handle.trimmingCharacters(in: .whitespaces))
                onSaved(ProfileService.MyProfile(
                    displayName: name.trimmingCharacters(in: .whitespaces),
                    handle: handle.trimmingCharacters(in: .whitespaces).lowercased(),
                    avatarUrl: initial?.avatarUrl,
                    pendingAvatarUrl: pendingAvatarUrl ?? initial?.pendingAvatarUrl,
                    avatarModerationStatus: moderationStatus))
                dismiss()
            } catch {
                let d = error.localizedDescription
                if d.contains("handle_taken") { self.error = "That handle is taken. Try another." }
                else if d.contains("handle_format") { self.error = "Handles are 3 to 20 characters: letters, numbers, underscore." }
                else if d.contains("display_name_length") { self.error = "Names are 2 to 40 characters." }
                else if d.contains("not_allowed") { self.error = "Choose a name and handle that follow the community rules." }
                else { self.error = "That did not save. Check your connection and try again." }
            }
            saving = false
        }
    }
}
