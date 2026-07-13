import SwiftUI

/// Your beers: every beer you have rated or noted, on its own page so the profile
/// stays clean as this list grows. Votes feed the Beer Market; notes stay private.
/// Reuses MyBeerActivity + MyActivityService (defined alongside ProfileView).
struct MyBeersView: View {
    @State private var activity: [MyBeerActivity] = []
    @State private var loading = true
    @State private var error: String?

    var body: some View {
        Group {
            if loading && activity.isEmpty {
                TaptSkeletonList(rows: 6, rowHeight: 60).padding(.top, 8)
            } else if let error, activity.isEmpty {
                TaptEmptyState(
                    icon: "arrow.clockwise",
                    title: "Could not load your beers",
                    message: error,
                    actionTitle: "Try again",
                    action: { Task { await load() } }
                )
            } else if activity.isEmpty {
                TaptEmptyState(
                    icon: "mug.fill",
                    title: "No beers yet",
                    message: "Rate a pour or vote on a beer and it shows up here.",
                    actionTitle: nil
                )
            } else {
                List {
                    Section {
                        ForEach(activity) { a in
                            NavigationLink { BeerDetailView(beerId: a.beerId) } label: {
                                HStack(spacing: 12) {
                                    BeerThumb(imageUrl: a.imageUrl, size: 42)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(a.name).font(.system(.subheadline, design: .rounded).weight(.bold))
                                            .foregroundStyle(Brand.text).lineLimit(1)
                                        if let note = a.note, !note.isEmpty {
                                            Label(note, systemImage: "square.and.pencil")
                                                .font(.caption).foregroundStyle(Brand.muted)
                                                .labelStyle(.titleAndIcon).lineLimit(1)
                                        } else if let v = a.vote {
                                            Label(v > 0 ? "You liked this" : "You passed on this",
                                                  systemImage: v > 0 ? "hand.thumbsup.fill" : "hand.thumbsdown.fill")
                                                .font(.caption.weight(.semibold))
                                                .foregroundStyle(v > 0 ? Brand.hop : Brand.copper)
                                        }
                                    }
                                }
                            }
                        }
                    } header: {
                        Text("\(activity.count) beer\(activity.count == 1 ? "" : "s")")
                    } footer: {
                        Text("Your votes count on the Beer Market. Your notes are private to you.")
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .background(Brand.background)
        .navigationTitle("Your beers")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func load() async {
        loading = true
        defer { loading = false }
        do { activity = try await MyActivityService.fetch(); self.error = nil }
        catch { self.error = "Check your connection and try again." }
    }
}
