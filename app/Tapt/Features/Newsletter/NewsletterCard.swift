import SwiftUI

/// The Tapt Dispatch, the beer newsletter. A subscribe card for Discover and a
/// compact manager for the You tab. Subscription state lives on the account.
struct NewsletterCard: View {
    @Environment(Session.self) private var session
    @State private var subscribed: Bool?
    @State private var working = false
    @State private var note: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "envelope.open.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(Brand.malt)
                    .frame(width: 52, height: 52)
                    .background(Brand.copper, in: RoundedRectangle(cornerRadius: 14))
                VStack(alignment: .leading, spacing: 2) {
                    Text("The Tapt Dispatch")
                        .font(.system(.title3, design: .rounded).weight(.bold))
                        .foregroundStyle(Brand.text)
                    Text("Beer trends, new spots, and what the world is pouring. Free, of course.")
                        .font(.caption)
                        .foregroundStyle(Brand.muted)
                }
                Spacer(minLength: 0)
            }

            if session.user == nil {
                Button {
                    session.endGuestSession()
                } label: {
                    Label("Sign in to subscribe", systemImage: "person.crop.circle.badge.plus")
                        .font(.system(.subheadline, design: .rounded).weight(.bold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(Brand.gold, in: RoundedRectangle(cornerRadius: 12))
                        .foregroundStyle(Brand.malt)
                }
                .buttonStyle(.plain)
            } else if subscribed == true {
                HStack {
                    Label("You're on the list", systemImage: "checkmark.seal.fill")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(Brand.hop)
                    Spacer()
                    Button("Unsubscribe") { unsubscribe() }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Brand.muted)
                        .disabled(working)
                }
            } else if let accountEmail = session.user?.email, accountEmail.contains("@") {
                // The Dispatch only ever goes to the address on your account. We
                // used to show a free-text field, which implied you could sign up
                // any address you liked, including someone else's.
                HStack(spacing: 8) {
                    Text(accountEmail)
                        .font(.subheadline)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .foregroundStyle(Brand.muted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12)
                        .frame(height: 44)
                        .background(Brand.background, in: RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Brand.malt.opacity(0.12)))
                        .accessibilityLabel("Sends to \(accountEmail)")
                    Button {
                        subscribe(accountEmail)
                    } label: {
                        Text(working ? "..." : "Sign up")
                            .font(.system(.subheadline, design: .rounded).weight(.bold))
                            .padding(.horizontal, 16)
                            .frame(height: 44)
                            .background(Brand.gold, in: RoundedRectangle(cornerRadius: 12))
                            .foregroundStyle(Brand.malt)
                    }
                    .buttonStyle(.plain)
                    .disabled(working)
                }
            } else {
                Text("Add an email to your account to get the Dispatch.")
                    .font(.subheadline)
                    .foregroundStyle(Brand.muted)
            }

            if let note {
                Text(note).font(.caption2).foregroundStyle(Brand.muted)
            }
        }
        .padding(16)
        .background(Brand.surface, in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(Brand.copper.opacity(0.25)))
        .task { await loadStatus() }
    }

    private func loadStatus() async {
        guard session.user != nil else { return }
        if let status = try? await NewsletterService.status() {
            subscribed = status.status == "subscribed"
        } else {
            subscribed = false
        }
    }

    private func subscribe(_ address: String) {
        guard session.user != nil else {
            session.endGuestSession()
            return
        }
        working = true
        note = nil
        Task {
            do {
                try await NewsletterService.subscribe(email: address.trimmingCharacters(in: .whitespaces), source: "app_discover")
                subscribed = true
                note = "Welcome aboard. First issue lands soon. 🍻"
            } catch {
                note = "Could not sign you up yet, double-check the email."
            }
            working = false
        }
    }

    private func unsubscribe() {
        working = true
        Task {
            do {
                try await NewsletterService.unsubscribe()
                subscribed = false
                note = "Unsubscribed. Come back any time."
            } catch {
                note = "Could not update that right now."
            }
            working = false
        }
    }
}
