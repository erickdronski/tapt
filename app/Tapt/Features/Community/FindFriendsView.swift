import SwiftUI

/// Find and follow other beer fans by name or handle. Following powers the
/// Tonight friends feed.
struct FindFriendsView: View {
    @State private var query = ""
    @State private var results: [FoundProfile] = []
    @State private var searching = false
    @State private var searchTask: Task<Void, Never>?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(Brand.muted)
                    TextField("Search beer fans by name or handle", text: $query)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.system(.body, design: .rounded))
                }
                .padding(13)
                .background(Brand.surface, in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Brand.malt.opacity(0.1)))
                .padding(.horizontal)

                if searching {
                    ProgressView().tint(Brand.gold).frame(maxWidth: .infinity).padding(.top, 20)
                } else if query.trimmingCharacters(in: .whitespaces).count < 2 {
                    TaptEmptyState(
                        icon: "person.2.fill",
                        title: "Build your beer circle",
                        message: "Search for friends and follow them. Their pours show up in Tonight, and badge unlocks fuel discovery.",
                        actionTitle: nil
                    )
                } else if results.isEmpty {
                    TaptEmptyState(
                        icon: "person.fill.questionmark",
                        title: "No beer fans found",
                        message: "No profiles match that yet. Invite your crew, the more friends on Tapt, the better the night.",
                        actionTitle: nil
                    )
                } else {
                    VStack(spacing: 10) {
                        ForEach(results) { profile in
                            row(profile)
                        }
                    }
                    .padding(.horizontal)
                }
            }
            .padding(.vertical)
        }
        .background(Brand.background)
        .navigationTitle("Find friends")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: query) { _, newValue in
            searchTask?.cancel()
            let term = newValue.trimmingCharacters(in: .whitespaces)
            guard term.count >= 2 else {
                results = []
                return
            }
            searchTask = Task {
                try? await Task.sleep(for: .milliseconds(350))
                guard !Task.isCancelled else { return }
                searching = true
                let found = (try? await SocialGraphService.search(term)) ?? []
                // Don't let a superseded search overwrite newer results.
                guard !Task.isCancelled, term == query.trimmingCharacters(in: .whitespaces) else { return }
                results = found
                searching = false
            }
        }
    }

    private func row(_ profile: FoundProfile) -> some View {
        HStack(spacing: 12) {
            Text(String(profile.displayName.first ?? "T").uppercased())
                .font(.system(.headline, design: .rounded).weight(.heavy))
                .foregroundStyle(Brand.malt)
                .frame(width: 44, height: 44)
                .background(Brand.gold, in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(profile.displayName)
                    .font(.system(.headline, design: .rounded).weight(.bold))
                    .foregroundStyle(Brand.text).lineLimit(1)
                Text(profile.handle.map { "@\($0)" } ?? "\(profile.pours) pours logged")
                    .font(.caption).foregroundStyle(Brand.muted).lineLimit(1)
            }
            Spacer(minLength: 8)
            followButton(profile)
        }
        .padding(12)
        .background(Brand.surface, in: RoundedRectangle(cornerRadius: 15))
        .overlay(RoundedRectangle(cornerRadius: 15).stroke(Brand.malt.opacity(0.08)))
    }

    private func followButton(_ profile: FoundProfile) -> some View {
        Button {
            toggleFollow(profile)
        } label: {
            Text(profile.isFollowing ? "Following" : "Follow")
                .font(.system(.subheadline, design: .rounded).weight(.bold))
                .padding(.horizontal, 16).padding(.vertical, 8)
                .background(profile.isFollowing ? Brand.surface : Brand.gold, in: Capsule())
                .foregroundStyle(profile.isFollowing ? Brand.muted : Brand.malt)
                .overlay(Capsule().stroke(profile.isFollowing ? Brand.muted.opacity(0.4) : Brand.gold))
        }
        .buttonStyle(.plain)
    }

    private func toggleFollow(_ profile: FoundProfile) {
        guard let index = results.firstIndex(where: { $0.id == profile.id }) else { return }
        Haptic.tap()
        let wasFollowing = results[index].isFollowing
        results[index].isFollowing.toggle()
        Task {
            do {
                if wasFollowing {
                    try await SocialGraphService.unfollow(profile.userId)
                } else {
                    try await SocialGraphService.follow(profile.userId)
                }
            } catch {
                await MainActor.run {
                    if let i = results.firstIndex(where: { $0.id == profile.id }) {
                        results[i].isFollowing = wasFollowing
                    }
                }
            }
        }
    }
}
