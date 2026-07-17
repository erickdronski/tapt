import SwiftUI

/// The card you see when you tap a person you follow (or found in search / the
/// Tonight feed). Small on purpose: a passport snapshot, a favorite pour, top
/// styles, earned badges, and a follow button. Everything here is coarse and
/// self-generated -- the server never hands back venues, timestamps, or location.
struct PublicProfileView: View {
    let userId: String
    /// Name we already know (from the row that opened this), so the header isn't blank while loading.
    var initialName: String? = nil
    /// Lets the list that opened this sheet keep its own Follow button in sync.
    var onFollowChange: (Bool) -> Void = { _ in }

    @Environment(\.dismiss) private var dismiss
    @State private var card: ProfileCard?
    @State private var loading = true
    @State private var loadFailed = false
    @State private var working = false
    @State private var showReport = false
    @State private var confirmBlock = false
    @State private var safetyMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    if let card, card.blocked {
                        note("This profile isn't available.", icon: "hand.raised.fill")
                    } else if let card, !card.visible {
                        note("\(firstName) keeps their passport private.", icon: "lock.fill")
                    } else if let card {
                        followRow(card)
                        statStrip(card)
                        if (card.pours ?? 0) == 0 {
                            TaptEmptyState(
                                icon: "drop.fill",
                                title: "Just getting started",
                                message: "\(firstName) hasn't logged a pour yet. Follow along and their beers show up in Tonight.",
                                actionTitle: nil
                            )
                            .padding(.top, 4)
                        } else {
                            if let fav = card.favoriteBeer { favoriteCard(fav) }
                            if let styles = card.topStyles, !styles.isEmpty { topStyles(styles) }
                            badges(card)
                        }
                    } else if loadFailed {
                        note("Couldn't load this profile. Pull to try again.", icon: "wifi.slash")
                    }
                }
                .padding()
            }
            .background(Brand.background)
            .navigationTitle("Passport")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }.foregroundStyle(Brand.gold)
                }
                // Safety controls (App Store UGC guideline 1.2): report or block
                // anyone but yourself.
                if let card, !card.isSelf {
                    ToolbarItem(placement: .topBarLeading) {
                        Menu {
                            Button {
                                showReport = true
                            } label: { Label("Report \(firstName)", systemImage: "flag") }
                            Button(role: .destructive) {
                                confirmBlock = true
                            } label: { Label("Block \(firstName)", systemImage: "hand.raised") }
                        } label: {
                            Image(systemName: "ellipsis.circle").foregroundStyle(Brand.muted)
                        }
                        .disabled(working)
                        .accessibilityLabel("Report or block")
                        .id(card.userId)
                    }
                }
            }
            .confirmationDialog("Report \(firstName)?", isPresented: $showReport, titleVisibility: .visible) {
                Button("Spam or scam") { report("spam") }
                Button("Harassment or bullying") { report("harassment") }
                Button("Inappropriate content") { report("inappropriate") }
                Button("Something else") { report("other") }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Reports go to our moderation team. Thanks for keeping Tapt safe.")
            }
            .confirmationDialog("Block \(firstName)?", isPresented: $confirmBlock, titleVisibility: .visible) {
                Button("Block", role: .destructive) { block() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("You won't see each other's profiles or activity. You can undo this in your device settings by contacting support.")
            }
            .alert("Thanks", isPresented: Binding(get: { safetyMessage != nil }, set: { if !$0 { safetyMessage = nil } })) {
                Button("OK") { safetyMessage = nil }
            } message: { Text(safetyMessage ?? "") }
            .overlay {
                if loading && card == nil {
                    ProgressView().tint(Brand.gold)
                }
            }
        }
        .task { await load() }
    }

    private func report(_ reason: String) {
        working = true
        Task {
            defer { working = false }
            do {
                try await SocialGraphService.reportUser(userId, reason: reason)
                safetyMessage = "Report received. Our team will take a look."
            } catch {
                safetyMessage = "Couldn't send the report. Please try again."
            }
        }
    }

    private func block() {
        working = true
        Task {
            defer { working = false }
            do {
                try await SocialGraphService.blockUser(userId)
                onFollowChange(false)
                dismiss()
            } catch {
                safetyMessage = "Couldn't block right now. Please try again."
            }
        }
    }

    // MARK: header

    private var header: some View {
        HStack(spacing: 14) {
            avatar
            VStack(alignment: .leading, spacing: 3) {
                Text(card?.displayName ?? initialName ?? "Beer fan")
                    .font(.system(.title2, design: .rounded).weight(.heavy))
                    .foregroundStyle(Brand.text)
                    .lineLimit(1)
                if let handle = card?.handle, !handle.isEmpty {
                    Text("@\(handle)").font(.subheadline).foregroundStyle(Brand.muted)
                }
                if let sub = memberLine { Text(sub).font(.caption).foregroundStyle(Brand.muted) }
            }
            Spacer(minLength: 0)
        }
    }

    private var avatar: some View {
        Group {
            if let urlStr = card?.avatarUrl, let url = URL(string: urlStr) {
                AsyncImage(url: url) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFill()
                    } else {
                        initialCircle
                    }
                }
            } else {
                initialCircle
            }
        }
        .frame(width: 64, height: 64)
        .clipShape(Circle())
        .overlay(Circle().stroke(Brand.gold.opacity(0.5), lineWidth: 2))
    }

    private var initialCircle: some View {
        Text(String((card?.displayName ?? initialName ?? "T").first ?? "T").uppercased())
            .font(.system(.title, design: .rounded).weight(.heavy))
            .foregroundStyle(Brand.malt)
            .frame(width: 64, height: 64)
            .background(Brand.gold, in: Circle())
    }

    // MARK: follow

    private func followRow(_ card: ProfileCard) -> some View {
        let top = topEarnedBadges(card)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 14) {
                countPill("\(card.followers)", "Followers")
                countPill("\(card.following)", "Following")
                // On your own passport the strip sits right beside the counts.
                if card.isSelf, !top.isEmpty {
                    HStack(spacing: 6) { ForEach(top) { miniMedal($0) } }
                }
                Spacer(minLength: 8)
                if !card.isSelf { followButton(card) }
            }
            // On someone else's profile the Follow button owns the right edge,
            // so the top-badge strip drops to its own line just below the counts.
            if !card.isSelf, !top.isEmpty {
                HStack(spacing: 6) { ForEach(top) { miniMedal($0) } }
            }
        }
    }

    private func countPill(_ value: String, _ label: String) -> some View {
        VStack(spacing: 1) {
            Text(value).font(.system(.headline, design: .rounded).weight(.heavy)).foregroundStyle(Brand.text)
            Text(label).font(.caption2).foregroundStyle(Brand.muted)
        }
    }

    private func followButton(_ card: ProfileCard) -> some View {
        Button {
            Task { await toggleFollow(card) }
        } label: {
            Text(card.isFollowing ? "Following" : "Follow")
                .font(.system(.subheadline, design: .rounded).weight(.bold))
                .padding(.horizontal, 20).padding(.vertical, 9)
                .background(card.isFollowing ? Brand.surface : Brand.gold, in: Capsule())
                .foregroundStyle(card.isFollowing ? Brand.muted : Brand.malt)
                .overlay(Capsule().stroke(card.isFollowing ? Brand.muted.opacity(0.4) : Brand.gold))
        }
        .buttonStyle(.plain)
        .disabled(working)
    }

    // MARK: stats

    private func statStrip(_ card: ProfileCard) -> some View {
        HStack(spacing: 10) {
            stat("\(card.beersCount ?? card.pours ?? 0)", "Beers", "mug.fill", Brand.gold)
            stat("\(card.stylesCount ?? 0)", "Styles", "square.grid.2x2.fill", Brand.hop)
            stat("\(card.countries ?? 0)", "Countries", "globe", Brand.copper)
            stat("\(card.states ?? 0)", "States", "map.fill", Brand.malt)
        }
    }

    private func stat(_ value: String, _ label: String, _ icon: String, _ tint: Color) -> some View {
        VStack(spacing: 5) {
            Image(systemName: icon).font(.headline).foregroundStyle(tint)
            Text(value).font(.system(.title3, design: .rounded).weight(.heavy)).foregroundStyle(Brand.text)
                .contentTransition(.numericText())
            Text(label).font(.caption2).foregroundStyle(Brand.muted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(Brand.surface, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(tint.opacity(0.18), lineWidth: 1))
    }

    // MARK: favorite beer

    private func favoriteCard(_ fav: ProfileCard.FavoriteBeer) -> some View {
        HStack(spacing: 12) {
            BeerThumb(imageUrl: fav.imageUrl, size: 58)
            VStack(alignment: .leading, spacing: 6) {
                Label("Favorite pour", systemImage: "heart.fill")
                    .font(.caption.weight(.bold)).foregroundStyle(Brand.copper)
                Text(fav.name)
                    .font(.system(.headline, design: .rounded).weight(.bold))
                    .foregroundStyle(Brand.text).lineLimit(2)
                HStack(spacing: 6) {
                    if let brewery = fav.brewery, !brewery.isEmpty {
                        Text(brewery).font(.subheadline).foregroundStyle(Brand.muted)
                    }
                    Spacer()
                    Text(fav.pours == 1 ? "Logged once" : "Logged \(fav.pours) times")
                        .font(.caption.weight(.semibold)).foregroundStyle(Brand.gold)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Brand.surface, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Brand.copper.opacity(0.22), lineWidth: 1))
    }

    // MARK: top styles

    private func topStyles(_ styles: [ProfileCard.StyleCount]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Goes for").font(.caption.weight(.bold)).foregroundStyle(Brand.muted)
            FlowChips(styles.map(\.style))
        }
    }

    // MARK: badges

    private func statsFor(_ card: ProfileCard) -> PassportStats {
        PassportStats(
            pours: card.pours ?? 0,
            beers: card.beersCount,
            styles: card.stylesCount ?? 0,
            states: card.states ?? 0,
            countries: card.countries ?? 0,
            breweries: card.breweries ?? 0,
            styleFamilies: card.styleFamilies ?? 0,
            continents: card.continents ?? 0,
            seasons: card.seasons ?? 0,
            noLow: card.noLow ?? 0,
            hoppy: card.hoppy ?? 0,
            dark: card.dark ?? 0,
            wheat: card.wheat ?? 0,
            sour: card.sour ?? 0,
            belgian: card.belgian ?? 0,
            crisp: card.crisp ?? 0
        )
    }

    /// The five hardest badges this person has actually earned, ranked by tier
    /// then threshold. This is their flex, shown up in the header.
    private func topEarnedBadges(_ card: ProfileCard) -> [Badge] {
        let stats = statsFor(card)
        return PassportData.badges
            .filter { $0.earned(stats) }
            .sorted {
                $0.tier.rawValue != $1.tier.rawValue
                    ? $0.tier.rawValue > $1.tier.rawValue
                    : $0.threshold > $1.threshold
            }
            .prefix(5).map { $0 }
    }

    /// Compact medal (glyph on a tier disc, no label) for the header strip.
    private func miniMedal(_ badge: Badge) -> some View {
        let tint: Color = {
            switch badge.tier {
            case .bronze: return Brand.copper
            case .silver: return Color(hex: 0x8C97A8)
            case .gold:   return Brand.gold
            case .elite:  return Brand.hop
            }
        }()
        return BadgeGlyph(badge: badge, ink: Brand.malt, accent: Brand.malt.opacity(0.28))
            .frame(width: 17, height: 17)
            .frame(width: 30, height: 30)
            .background(
                LinearGradient(colors: [tint, tint.opacity(0.72)],
                               startPoint: .topLeading, endPoint: .bottomTrailing),
                in: Circle())
            .overlay(Circle().stroke(.white.opacity(0.85), lineWidth: 1.5))
            .accessibilityLabel("\(badge.title), earned")
    }

    private func badges(_ card: ProfileCard) -> some View {
        let stats = statsFor(card)
        let earnedCount = PassportData.badges.filter { $0.earned(stats) }.count
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Passport stamps").font(.caption.weight(.bold)).foregroundStyle(Brand.muted)
                Spacer()
                Text("\(earnedCount) of \(PassportData.badges.count)")
                    .font(.caption.weight(.bold)).foregroundStyle(Brand.gold)
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 88), spacing: 12)], spacing: 16) {
                ForEach(PassportData.badges) { badge in
                    BadgeSticker(badge: badge, stats: stats)
                }
            }
        }
    }

    // MARK: shared bits

    private func note(_ text: String, icon: String) -> some View {
        Label(text, systemImage: icon)
            .font(.callout).foregroundStyle(Brand.muted)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(Brand.surface, in: RoundedRectangle(cornerRadius: 14))
    }

    private var firstName: String {
        (card?.displayName ?? initialName ?? "This drinker")
            .split(separator: " ").first.map(String.init) ?? "This drinker"
    }

    private var memberLine: String? {
        guard let card else { return nil }
        var parts: [String] = []
        if let since = memberSince(card.memberSince) { parts.append("Member since \(since)") }
        if let region = card.region, !region.isEmpty { parts.append(region) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private func memberSince(_ iso: String?) -> String? {
        guard let iso else { return nil }
        let iso8601 = ISO8601DateFormatter()
        iso8601.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let date = iso8601.date(from: iso) ?? ISO8601DateFormatter().date(from: iso)
        guard let date else { return nil }
        let out = DateFormatter()
        out.dateFormat = "MMM yyyy"
        return out.string(from: date)
    }

    // MARK: actions

    private func load() async {
        loading = true
        loadFailed = false
        do {
            card = try await SocialGraphService.profile(userId)
        } catch {
            loadFailed = true
        }
        loading = false
    }

    private func toggleFollow(_ current: ProfileCard) async {
        guard !working else { return }
        working = true
        Haptic.tap()
        let wasFollowing = current.isFollowing
        card?.isFollowing.toggle()
        do {
            if wasFollowing {
                try await SocialGraphService.unfollow(userId)
            } else {
                try await SocialGraphService.follow(userId)
            }
            onFollowChange(!wasFollowing)
        } catch {
            card?.isFollowing = wasFollowing
        }
        working = false
    }
}

/// Simple wrapping row of style chips.
private struct FlowChips: View {
    let items: [String]
    init(_ items: [String]) { self.items = items }
    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 88), spacing: 8)], spacing: 8) {
            ForEach(items, id: \.self) { s in
                Text(s)
                    .font(.caption.weight(.semibold)).foregroundStyle(Brand.malt)
                    .lineLimit(1).minimumScaleFactor(0.8)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(Brand.hop.opacity(0.25), in: Capsule())
            }
        }
    }
}

/// Wrapper so a bare user id can drive `.sheet(item:)`.
struct ProfileRef: Identifiable, Equatable {
    let id: String
    var name: String? = nil
}
