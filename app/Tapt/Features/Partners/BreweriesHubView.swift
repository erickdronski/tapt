import SwiftUI
import CoreImage.CIFilterBuiltins

// In-app owner tools for breweries, bars, pubs, and taprooms: the self-service
// claim loop (search -> claim -> approval status) and a claimed-owner dashboard
// (real venue_analytics + a hosted-menu QR generated on-device). This brings the
// two-sided value into the app; full tap-list editing still lives in the web portal.

private enum PartnerLinks {
    static let base = "https://tapt-landing-three.vercel.app"
    static func menuURL(_ venueId: String) -> String { "\(base)/menu?v=\(venueId)" }
    static let portal = "\(base)/portal"
}

// MARK: - Models for the owner tools

struct VenueSearchResult: Identifiable, Decodable, Sendable {
    let venueId: String
    let name: String
    let city: String?
    let region: String?
    let country: String?
    var id: String { venueId }
    enum CodingKeys: String, CodingKey {
        case name, city, region, country
        case venueId = "venue_id"
    }
    var placeLine: String {
        [city, region, country].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ")
    }
}

struct VenueClaim: Identifiable, Decodable, Sendable {
    let claimId: String
    let venueId: String
    let venueName: String
    let status: String
    var id: String { claimId }
    enum CodingKeys: String, CodingKey {
        case status
        case claimId = "claim_id"
        case venueId = "venue_id"
        case venueName = "venue_name"
    }
}

struct VenueAnalytics: Decodable, Sendable {
    let poursTotal: Int
    let pours7d: Int
    let uniqueDrinkers: Int
    let avgRating: Double?
    let topBeers: [TopBeer]

    struct TopBeer: Identifiable, Decodable, Sendable {
        let name: String
        let brewery: String?
        let pours: Int
        var id: String { name + (brewery ?? "") }
    }
    enum CodingKeys: String, CodingKey {
        case poursTotal = "pours_total"
        case pours7d = "pours_7d"
        case uniqueDrinkers = "unique_drinkers"
        case avgRating = "avg_rating"
        case topBeers = "top_beers"
    }
}

extension PartnerService {
    static func searchVenues(_ query: String, limit: Int = 20) async throws -> [VenueSearchResult] {
        struct P: Encodable { let p_query: String; let p_limit: Int }
        return try await Supa.client
            .rpc("search_venues", params: P(p_query: query, p_limit: limit))
            .execute().value
    }

    @discardableResult
    static func claimVenue(venueId: String, email: String, role: String) async throws -> String {
        struct P: Encodable { let p_venue: String; let p_email: String; let p_role: String }
        return try await Supa.client
            .rpc("claim_venue", params: P(p_venue: venueId, p_email: email, p_role: role))
            .execute().value
    }

    static func myClaims() async throws -> [VenueClaim] {
        try await Supa.client.rpc("my_venue_claims").execute().value
    }

    static func analytics(venueId: String) async throws -> VenueAnalytics {
        struct P: Encodable { let p_venue: String }
        return try await Supa.client
            .rpc("venue_analytics", params: P(p_venue: venueId))
            .execute().value
    }
}

// MARK: - QR generation (on-device, no network)

private func qrImage(from string: String) -> UIImage? {
    let context = CIContext()
    let filter = CIFilter.qrCodeGenerator()
    filter.message = Data(string.utf8)
    filter.correctionLevel = "M"
    guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 12, y: 12)),
          let cg = context.createCGImage(output, from: output.extent) else { return nil }
    return UIImage(cgImage: cg)
}

// MARK: - The hub

struct BreweriesHubView: View {
    @Environment(Session.self) private var session
    @State private var claims: [VenueClaim] = []
    @State private var loaded = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                TaptHeroPanel(
                    title: "For breweries & bars",
                    subtitle: "Free menu, QR, map profile, and local analytics. Pay only to reach more drinkers nearby.",
                    metric: "FREE",
                    caption: "Breweries fund the party, drinkers never pay",
                    icon: "storefront.fill",
                    tint: Brand.copper
                )

                if !claims.isEmpty {
                    sectionTitle("Your venues")
                    ForEach(claims) { claim in
                        claimRow(claim)
                    }
                }

                sectionTitle("Get on Tapt")
                NavigationLink { ClaimVenueView(onClaimed: { Task { await load(force: true) } }) } label: {
                    actionCard(
                        icon: "checkmark.seal.fill",
                        tint: Brand.hop,
                        title: "Claim your venue",
                        body: "Find your brewery, bar, pub, or taproom in our map of 8,700+ and claim it. Publish a live tap list, get a printable QR, and see your local drinker activity."
                    )
                }
                .buttonStyle(.plain)

                NavigationLink { PartnerInquiryView() } label: {
                    actionCard(
                        icon: "megaphone.fill",
                        tint: Brand.gold,
                        title: "Get featured",
                        body: "Featured & Spotlight placement puts your taps, releases, and events in front of beer fans near you. Raise your hand and we'll reach out."
                    )
                }
                .buttonStyle(.plain)

                sectionTitle("What you get, free")
                valueGrid

                FeaturedPartnersRail()

                Text("Menus stay honest: tap lists expire after 14 days so a stale list never masquerades as live. Every edit is gated by an approved claim, so nobody can touch a venue they don't own.")
                    .font(.footnote)
                    .foregroundStyle(Brand.muted)
                    .padding(.horizontal)
            }
            .padding(.vertical)
        }
        .background(Brand.background)
        .navigationTitle("Breweries & Bars")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load(force: false) }
    }

    private func load(force: Bool) async {
        if loaded && !force { return }
        loaded = true
        claims = (try? await PartnerService.myClaims()) ?? []
    }

    private func sectionTitle(_ t: String) -> some View {
        Text(t)
            .font(.system(.title3, design: .rounded).weight(.bold))
            .foregroundStyle(Brand.text)
            .padding(.horizontal)
    }

    private func claimRow(_ claim: VenueClaim) -> some View {
        let approved = claim.status == "approved"
        return NavigationLink {
            if approved { VenueDashboardView(venueId: claim.venueId, venueName: claim.venueName) }
            else { ClaimPendingView(venueName: claim.venueName, status: claim.status) }
        } label: {
            HStack(spacing: 14) {
                Image(systemName: approved ? "chart.bar.fill" : "clock.fill")
                    .foregroundStyle(Brand.malt)
                    .frame(width: 46, height: 46)
                    .background(approved ? Brand.hop : Brand.copper, in: RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 3) {
                    Text(claim.venueName)
                        .font(.system(.headline, design: .rounded).weight(.bold))
                        .foregroundStyle(Brand.text).lineLimit(1)
                    Text(approved ? "Live · view analytics & menu QR" : "Claim \(claim.status)")
                        .font(.caption).foregroundStyle(Brand.muted)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").foregroundStyle(Brand.muted)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Brand.surface, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke((approved ? Brand.hop : Brand.copper).opacity(0.25)))
            .padding(.horizontal)
        }
        .buttonStyle(.plain)
    }

    private func actionCard(icon: String, tint: Color, title: String, body: String) -> some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 28)).foregroundStyle(Brand.malt)
                .frame(width: 60, height: 60)
                .background(tint, in: RoundedRectangle(cornerRadius: 16))
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(.title3, design: .rounded).weight(.bold)).foregroundStyle(Brand.text)
                Text(body).font(.subheadline).foregroundStyle(Brand.muted).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Brand.surface, in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(tint.opacity(0.22)))
        .padding(.horizontal)
    }

    private let perks: [(String, String, String)] = [
        ("menucard.fill", "Live hosted menu", "Update taps once, everywhere shows current. No reprinting."),
        ("qrcode", "Printable QR", "Auto-generated for every table and the front door."),
        ("mappin.circle.fill", "Map presence", "A claimed profile drinkers find when deciding where to go."),
        ("chart.line.uptrend.xyaxis", "Local demand", "Your real pours, top beers, and drinker signal, live."),
        ("paintbrush.fill", "Your brand", "Upload your logo and own how you look on Tapt."),
        ("calendar.badge.plus", "Events & releases", "Push happy hours and new pours to nearby fans.")
    ]

    private var valueGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
            ForEach(perks, id: \.1) { perk in
                VStack(alignment: .leading, spacing: 8) {
                    Image(systemName: perk.0)
                        .font(.title3).foregroundStyle(Brand.copper)
                    Text(perk.1).font(.system(.subheadline, design: .rounded).weight(.bold)).foregroundStyle(Brand.text)
                    Text(perk.2).font(.caption).foregroundStyle(Brand.muted).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, minHeight: 118, alignment: .topLeading)
                .padding(14)
                .background(Brand.surface, in: RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(Brand.malt.opacity(0.1)))
            }
        }
        .padding(.horizontal)
    }
}

// MARK: - Claim flow

struct ClaimVenueView: View {
    @Environment(Session.self) private var session
    @Environment(\.dismiss) private var dismiss
    var onClaimed: () -> Void = {}

    @State private var query = ""
    @State private var results: [VenueSearchResult] = []
    @State private var searching = false
    @State private var selected: VenueSearchResult?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Search for your venue by name or city. We've already mapped 8,700+ breweries, bars, and taprooms.")
                    .font(.subheadline).foregroundStyle(Brand.muted)

                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass").foregroundStyle(Brand.muted)
                    TextField("e.g. Iron City Taproom, or Pittsburgh", text: $query)
                        .autocorrectionDisabled()
                        .onSubmit { runSearch() }
                    if searching { ProgressView() }
                }
                .padding(12)
                .background(Brand.surface, in: RoundedRectangle(cornerRadius: 13))
                .overlay(RoundedRectangle(cornerRadius: 13).stroke(Brand.malt.opacity(0.12)))

                Button { runSearch() } label: {
                    Text("Search")
                        .font(.system(.headline, design: .rounded))
                        .frame(maxWidth: .infinity).padding(.vertical, 13)
                        .background(Brand.gold, in: RoundedRectangle(cornerRadius: 13))
                        .foregroundStyle(Brand.malt)
                }
                .buttonStyle(.plain)
                .disabled(query.trimmingCharacters(in: .whitespaces).count < 2)
                .opacity(query.trimmingCharacters(in: .whitespaces).count < 2 ? 0.5 : 1)

                if results.isEmpty && !searching && query.count >= 2 {
                    Text("No matches yet. Try a shorter name or your city. Not listed? Use “Get featured” to tell us and we'll add you.")
                        .font(.footnote).foregroundStyle(Brand.muted).padding(.top, 4)
                }

                ForEach(results) { venue in
                    Button { selected = venue } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "mappin.circle.fill")
                                .foregroundStyle(Brand.copper).font(.title2)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(venue.name).font(.system(.headline, design: .rounded).weight(.semibold))
                                    .foregroundStyle(Brand.text).lineLimit(1)
                                if !venue.placeLine.isEmpty {
                                    Text(venue.placeLine).font(.caption).foregroundStyle(Brand.muted).lineLimit(1)
                                }
                            }
                            Spacer(minLength: 0)
                            Text("Claim").font(.caption.weight(.bold)).foregroundStyle(Brand.malt)
                                .padding(.horizontal, 10).padding(.vertical, 6)
                                .background(Brand.gold, in: Capsule())
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Brand.surface, in: RoundedRectangle(cornerRadius: 14))
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Brand.malt.opacity(0.1)))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding()
        }
        .background(Brand.background)
        .navigationTitle("Claim your venue")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $selected) { venue in
            ClaimConfirmSheet(venue: venue, defaultEmail: session.user?.email ?? "") {
                onClaimed()
                dismiss()
            }
        }
    }

    private func runSearch() {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard q.count >= 2 else { return }
        searching = true
        Task {
            results = (try? await PartnerService.searchVenues(q)) ?? []
            searching = false
        }
    }
}

private struct ClaimConfirmSheet: View {
    let venue: VenueSearchResult
    let defaultEmail: String
    var onDone: () -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var role = "owner"
    @State private var submitting = false
    @State private var done = false
    @State private var errorText: String?

    private let roles = ["owner", "manager", "staff"]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if done {
                        VStack(spacing: 12) {
                            Image(systemName: "checkmark.seal.fill").font(.system(size: 44)).foregroundStyle(Brand.hop)
                            Text("Claim submitted").font(.system(.title2, design: .rounded).weight(.heavy)).foregroundStyle(Brand.text)
                            Text("We verify claims by hand so nobody can hijack your page. Once approved, your tools and analytics unlock right here.")
                                .font(.subheadline).foregroundStyle(Brand.muted).multilineTextAlignment(.center)
                        }.frame(maxWidth: .infinity).padding(.vertical, 24)
                    } else {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(venue.name).font(.system(.title3, design: .rounded).weight(.bold)).foregroundStyle(Brand.text)
                            if !venue.placeLine.isEmpty {
                                Text(venue.placeLine).font(.subheadline).foregroundStyle(Brand.muted)
                            }
                        }
                        Text("Your role").font(.system(.headline, design: .rounded)).foregroundStyle(Brand.text)
                        HStack(spacing: 8) {
                            ForEach(roles, id: \.self) { r in
                                Button { role = r } label: {
                                    Text(r.capitalized).font(.caption.weight(.semibold))
                                        .padding(.horizontal, 14).padding(.vertical, 8)
                                        .background(role == r ? Brand.gold : Brand.surface, in: Capsule())
                                        .foregroundStyle(role == r ? Brand.malt : Brand.text)
                                        .overlay(Capsule().stroke(Brand.malt.opacity(0.12)))
                                }.buttonStyle(.plain)
                            }
                        }
                        Text("Account email").font(.system(.headline, design: .rounded)).foregroundStyle(Brand.text)
                        HStack(spacing: 10) {
                            Image(systemName: "envelope.fill").foregroundStyle(Brand.gold)
                            Text(defaultEmail.isEmpty ? "No email on this account" : defaultEmail)
                                .font(.subheadline)
                                .foregroundStyle(defaultEmail.isEmpty ? Brand.copper : Brand.text)
                                .lineLimit(1)
                                .minimumScaleFactor(0.75)
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Brand.surface, in: RoundedRectangle(cornerRadius: 13))
                        .overlay(RoundedRectangle(cornerRadius: 13).stroke(Brand.malt.opacity(0.12)))
                        Text("Claims use your verified sign-in email and are reviewed before partner tools unlock.")
                            .font(.caption).foregroundStyle(Brand.muted)

                        if let errorText {
                            Text(errorText).font(.footnote).foregroundStyle(.red)
                        }

                        Button { submit() } label: {
                            Text(submitting ? "Submitting…" : "Submit claim")
                                .font(.system(.headline, design: .rounded))
                                .frame(maxWidth: .infinity).padding(.vertical, 14)
                                .background(Brand.gold, in: RoundedRectangle(cornerRadius: 14)).foregroundStyle(Brand.malt)
                        }
                        .buttonStyle(.plain)
                        .disabled(!defaultEmail.contains("@") || submitting)
                        .opacity(defaultEmail.contains("@") && !submitting ? 1 : 0.5)
                    }
                }
                .padding()
            }
            .background(Brand.background)
            .navigationTitle("Claim venue")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(done ? "Done" : "Cancel") { if done { onDone() }; dismiss() }
                }
            }
        }
    }

    private func submit() {
        submitting = true
        errorText = nil
        Task {
            do {
                try await PartnerService.claimVenue(
                    venueId: venue.venueId,
                    email: defaultEmail,
                    role: role
                )
                done = true
            } catch {
                errorText = "Could not submit that claim. You may have already claimed it. Check Your venues."
            }
            submitting = false
        }
    }
}

struct ClaimPendingView: View {
    let venueName: String
    let status: String
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "clock.badge.checkmark.fill").font(.system(size: 54)).foregroundStyle(Brand.copper)
            Text(venueName).font(.system(.title2, design: .rounded).weight(.heavy)).foregroundStyle(Brand.text)
            Text("Your claim is \(status). We verify by hand so nobody can hijack your page. Once approved, your live menu, printable QR, and local analytics unlock here.")
                .font(.subheadline).foregroundStyle(Brand.muted).multilineTextAlignment(.center).padding(.horizontal)
            Link(destination: URL(string: PartnerLinks.portal)!) {
                Text("Set up taps on the web portal")
                    .font(.system(.subheadline, design: .rounded).weight(.bold)).foregroundStyle(Brand.malt)
                    .padding(.horizontal, 18).padding(.vertical, 12).background(Brand.gold, in: Capsule())
            }
            Spacer()
        }
        .padding(.top, 40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Brand.background)
        .navigationTitle("Claim pending")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Claimed-owner dashboard

struct VenueDashboardView: View {
    let venueId: String
    let venueName: String
    @State private var analytics: VenueAnalytics?
    @State private var loading = true
    @State private var showQR = false

    private var menuURL: String { PartnerLinks.menuURL(venueId) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if loading {
                    ProgressView().frame(maxWidth: .infinity).padding(.top, 40)
                } else if let a = analytics {
                    statRow(a)
                    if a.poursTotal == 0 {
                        emptyState
                    } else {
                        topBeers(a)
                    }
                }

                sectionTitle("Your menu")
                Button { showQR = true } label: {
                    HStack(spacing: 14) {
                        Image(systemName: "qrcode").font(.title).foregroundStyle(Brand.malt)
                            .frame(width: 54, height: 54).background(Brand.gold, in: RoundedRectangle(cornerRadius: 14))
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Table QR code").font(.system(.headline, design: .rounded).weight(.bold)).foregroundStyle(Brand.text)
                            Text("Print it for tables and the door. Drinkers scan to your live menu.").font(.caption).foregroundStyle(Brand.muted)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Brand.surface, in: RoundedRectangle(cornerRadius: 16))
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(Brand.gold.opacity(0.3)))
                }
                .buttonStyle(.plain)
                .padding(.horizontal)

                Link(destination: URL(string: menuURL)!) {
                    Text("Open your public menu").font(.subheadline.weight(.semibold)).foregroundStyle(Brand.copper)
                }.padding(.horizontal)

                Link(destination: URL(string: PartnerLinks.portal)!) {
                    HStack {
                        Image(systemName: "slider.horizontal.3")
                        Text("Edit taps, events & logo on the web portal")
                    }
                    .font(.system(.subheadline, design: .rounded).weight(.bold)).foregroundStyle(Brand.malt)
                    .frame(maxWidth: .infinity).padding(.vertical, 13)
                    .background(Brand.gold, in: RoundedRectangle(cornerRadius: 14))
                }
                .padding(.horizontal)
            }
            .padding(.vertical)
        }
        .background(Brand.background)
        .navigationTitle(venueName)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            analytics = try? await PartnerService.analytics(venueId: venueId)
            loading = false
        }
        .sheet(isPresented: $showQR) { QRSheet(url: menuURL, venueName: venueName) }
    }

    private func sectionTitle(_ t: String) -> some View {
        Text(t).font(.system(.title3, design: .rounded).weight(.bold)).foregroundStyle(Brand.text).padding(.horizontal)
    }

    private func statRow(_ a: VenueAnalytics) -> some View {
        HStack(spacing: 12) {
            stat("\(a.poursTotal)", "pours all-time")
            stat("\(a.pours7d)", "this week")
            stat("\(a.uniqueDrinkers)", "drinkers")
            stat(a.avgRating.map { String(format: "%.1f", $0) } ?? "—", "avg rating")
        }
        .padding(.horizontal)
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 4) {
            Text(value).font(.system(.title2, design: .rounded).weight(.heavy)).foregroundStyle(Brand.text)
                .minimumScaleFactor(0.6).lineLimit(1)
            Text(label).font(.caption2).foregroundStyle(Brand.muted).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 14)
        .background(Brand.surface, in: RoundedRectangle(cornerRadius: 14))
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "chart.bar.doc.horizontal").font(.system(size: 34)).foregroundStyle(Brand.muted)
            Text("No pours logged here yet").font(.system(.headline, design: .rounded)).foregroundStyle(Brand.text)
            Text("Print your QR and drop it on the tables. Your top beers, weekly pours, and drinker signal fill in here as people check in. Real numbers only, never estimated.")
                .font(.caption).foregroundStyle(Brand.muted).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity).padding(20)
        .background(Brand.surface, in: RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal)
    }

    private func topBeers(_ a: VenueAnalytics) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Top pours")
            ForEach(Array(a.topBeers.enumerated()), id: \.element.id) { idx, beer in
                HStack(spacing: 12) {
                    Text("\(idx + 1)").font(.system(.headline, design: .rounded).weight(.heavy)).foregroundStyle(Brand.copper).frame(width: 24)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(beer.name).font(.system(.subheadline, design: .rounded).weight(.semibold)).foregroundStyle(Brand.text).lineLimit(1)
                        if let br = beer.brewery, !br.isEmpty { Text(br).font(.caption2).foregroundStyle(Brand.muted).lineLimit(1) }
                    }
                    Spacer(minLength: 0)
                    Text("\(beer.pours)").font(.system(.subheadline, design: .rounded).weight(.bold)).foregroundStyle(Brand.text)
                    Text("pours").font(.caption2).foregroundStyle(Brand.muted)
                }
                .padding(.horizontal).padding(.vertical, 8)
            }
        }
    }
}

private struct QRSheet: View {
    let url: String
    let venueName: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                Text(venueName).font(.system(.title3, design: .rounded).weight(.bold)).foregroundStyle(Brand.text)
                if let img = qrImage(from: url) {
                    Image(uiImage: img)
                        .interpolation(.none).resizable().scaledToFit()
                        .frame(maxWidth: 260, maxHeight: 260)
                        .padding(16).background(Color.white, in: RoundedRectangle(cornerRadius: 20))
                    ShareLink(item: URL(string: url)!) {
                        Label("Share / save QR link", systemImage: "square.and.arrow.up")
                            .font(.system(.subheadline, design: .rounded).weight(.bold)).foregroundStyle(Brand.malt)
                            .padding(.horizontal, 18).padding(.vertical, 12).background(Brand.gold, in: Capsule())
                    }
                } else {
                    Text("Could not render the QR.").foregroundStyle(Brand.muted)
                }
                Text("Drinkers who scan this land on your live Tapt menu. No app required.")
                    .font(.caption).foregroundStyle(Brand.muted).multilineTextAlignment(.center).padding(.horizontal)
                Spacer()
            }
            .padding(.top, 24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Brand.background)
            .navigationTitle("Your table QR")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
        }
    }
}
