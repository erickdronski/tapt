import SwiftUI

/// Edit your display name and unique handle. Validation is enforced server-side
/// (set_profile_identity); friendly messages map the RPC error codes.
struct EditIdentityView: View {
    @Environment(Session.self) private var session
    @Environment(\.dismiss) private var dismiss
    let initial: ProfileService.MyProfile?
    var onSaved: (ProfileService.MyProfile) -> Void
    @State private var name = ""
    @State private var handle = ""
    @State private var saving = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
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
                    Button(saving ? "Saving" : "Save") { save() }.disabled(saving)
                }
            }
            .onAppear { name = initial?.displayName ?? ""; handle = initial?.handle ?? "" }
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
                    displayName: name,
                    handle: handle.lowercased(),
                    avatarUrl: initial?.avatarUrl,
                    pendingAvatarUrl: initial?.pendingAvatarUrl,
                    avatarModerationStatus: initial?.avatarModerationStatus ?? "none"
                ))
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
