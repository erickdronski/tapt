import SwiftUI
import VisionKit

/// The hero loop entry: scan a label/barcode/tap list, then (next) match to the catalog and rate.
struct ScanView: View {
    @Environment(Session.self) private var session
    @State private var scanned: String?
    @State private var showResult = false
    @State private var matches: [ScannedBeer] = []
    @State private var loadingMatches = false
    @State private var selected: BeerPick?
    @State private var rating: Double = 4
    @State private var saving = false
    @State private var loggedPour: PourCard?
    @State private var offBeer: OFFBeer?
    @State private var addingOFF = false
    @State private var visibleLines: [String] = []
    @State private var menuMatching = false
    @State private var partnerVenueId: String?

    private var scannerAvailable: Bool {
        DataScannerViewController.isSupported && DataScannerViewController.isAvailable
    }

    var body: some View {
        NavigationStack {
            Group {
                if scannerAvailable {
                    DataScannerView(scanned: $scanned, visibleLines: $visibleLines)
                        .ignoresSafeArea(edges: .bottom)
                        .overlay(alignment: .bottom) { hint }
                        .overlay(alignment: .bottomTrailing) {
                            if visibleLines.count >= 3 && !showResult {
                                Button {
                                    Haptic.firm()
                                    Task { await matchMenu() }
                                } label: {
                                    Label(menuMatching ? "Matching..." : "Match menu (\(visibleLines.count))",
                                          systemImage: "list.bullet.rectangle.fill")
                                        .font(.system(.subheadline, design: .rounded).weight(.bold))
                                        .foregroundStyle(Brand.malt)
                                        .padding(.horizontal, 14).padding(.vertical, 10)
                                        .background(Brand.gold, in: Capsule())
                                        .shadow(color: Brand.malt.opacity(0.3), radius: 8, y: 4)
                                }
                                .buttonStyle(.taptPress)
                                .disabled(menuMatching)
                                .padding(.trailing, 16)
                                .padding(.bottom, 76)
                            }
                        }
                } else {
                    unsupported
                }
            }
            .navigationTitle("Scan")
            .navigationBarTitleDisplayMode(.inline)
            .onChange(of: scanned) { _, value in
                guard let value else { return }
                // Partner QR: route straight to the venue's live menu in-app.
                if value.contains("menu?v="),
                   let venueId = value.components(separatedBy: "menu?v=").last?
                       .components(separatedBy: "&").first, venueId.count == 36 {
                    partnerVenueId = venueId
                    scanned = nil
                    return
                }
                showResult = true
                Task { await loadMatches(value) }
            }
            .sheet(item: $partnerVenueId) { venueId in
                PartnerMenuSheet(venueId: venueId)
            }
            .sheet(isPresented: $showResult, onDismiss: { scanned = nil }) { resultSheet }
            .sheet(item: $loggedPour) { pour in
                NavigationStack {
                    ScrollView {
                        VStack(spacing: 14) {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.system(size: 44))
                                .foregroundStyle(Brand.hop)
                                .symbolEffect(.bounce, value: pour.id)
                            Text("Pour logged")
                                .font(.system(.title, design: .rounded).weight(.heavy))
                                .foregroundStyle(Brand.text)
                            Text("Your Cellar and Passport just got a little deeper.")
                                .font(.subheadline)
                                .foregroundStyle(Brand.muted)
                                .multilineTextAlignment(.center)
                            CardShareView(pour: pour)
                        }
                        .padding(.top, 22)
                        .padding(.bottom, 28)
                    }
                    .background(Brand.background)
                    .navigationTitle("Nice pour")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { loggedPour = nil }
                        }
                    }
                }
            }
        }
    }

    private var hint: some View {
        Text("Point at a can, bottle barcode, or tap list")
            .font(.system(.subheadline, design: .rounded).weight(.semibold))
            .foregroundStyle(Brand.foam)
            .padding(.horizontal, 16).padding(.vertical, 10)
            .background(.black.opacity(0.5), in: Capsule())
            .padding(.bottom, 28)
    }

    private var unsupported: some View {
        ZStack {
            Brand.background.ignoresSafeArea()
            VStack(spacing: 14) {
                Image(systemName: "viewfinder").font(.system(size: 46)).foregroundStyle(Brand.accent)
                Text("Scanning needs a device camera")
                    .font(.system(.title3, design: .rounded).weight(.bold)).foregroundStyle(Brand.text)
                Text("Run Tapt on your iPhone to scan labels and barcodes.")
                    .font(.subheadline).foregroundStyle(Brand.muted).multilineTextAlignment(.center).padding(.horizontal, 40)
            }
        }
    }

    private var resultSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    Image(systemName: matches.isEmpty ? "viewfinder.circle.fill" : "checkmark.seal.fill")
                        .font(.system(size: 42))
                        .foregroundStyle(matches.isEmpty ? Brand.gold : Brand.hop)
                        .padding(.top, 20)
                    Text(matches.isEmpty ? "Scanned" : "Possible matches")
                        .font(.system(.title2, design: .rounded).weight(.bold))
                        .foregroundStyle(Brand.text)
                    Text(scanned ?? "")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(Brand.muted)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)

                    if loadingMatches {
                        ProgressView().tint(Brand.gold).padding(.top, 16)
                    } else if matches.isEmpty, let offBeer {
                        offCard(offBeer)
                    } else if matches.isEmpty {
                        Text("No catalog match yet. Try a clearer barcode or log it manually from Cellar.")
                            .font(.footnote)
                            .foregroundStyle(Brand.muted)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                    } else {
                        VStack(spacing: 10) {
                            ForEach(matches) { match in
                                matchRow(match)
                            }
                        }
                        .padding(.horizontal)
                    }

                    Button("Scan another") { showResult = false }
                        .font(.system(.headline, design: .rounded))
                        .frame(maxWidth: .infinity).padding(.vertical, 14)
                        .background(Brand.gold, in: RoundedRectangle(cornerRadius: 14))
                        .foregroundStyle(Brand.malt).padding(.horizontal)
                }
                .padding(.bottom, 20)
            }
            .background(Brand.background)
            .navigationTitle("Scan result")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium])
    }

    private func matchRow(_ match: ScannedBeer) -> some View {
        let isSelected = selected?.id == match.id
        return VStack(alignment: .leading, spacing: 10) {
            Button {
                selected = match.pick
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "mug.fill")
                        .foregroundStyle(Brand.malt)
                        .frame(width: 40, height: 40)
                        .background(Brand.gold, in: RoundedRectangle(cornerRadius: 10))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(match.name).font(.system(.headline, design: .rounded)).foregroundStyle(Brand.text)
                        Text("\(match.breweryName ?? "")  \(match.style ?? "")")
                            .font(.caption).foregroundStyle(Brand.muted)
                    }
                    Spacer()
                    Text("\(Int(match.confidence * 100))%")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Brand.hop)
                }
            }
            .buttonStyle(.plain)

            if isSelected {
                HStack(spacing: 8) {
                    ForEach(1...5, id: \.self) { i in
                        Image(systemName: Double(i) <= rating ? "star.fill" : "star")
                            .foregroundStyle(Brand.gold)
                            .onTapGesture { rating = Double(i) }
                    }
                    Spacer()
                    Button(saving ? "Saving..." : "Log") { save(match.pick) }
                        .font(.system(.subheadline, design: .rounded).weight(.bold))
                        .padding(.horizontal, 16).padding(.vertical, 8)
                        .background(Brand.hop, in: Capsule())
                        .foregroundStyle(Brand.malt)
                        .disabled(saving)
                }
            }
        }
        .padding(12)
        .background(Brand.surface, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(isSelected ? Brand.gold : Brand.malt.opacity(0.1)))
    }

    /// A card for a barcode that missed our catalog but exists in Open Food
    /// Facts, one tap adds the real product to Tapt (GTIN-dedup'd) and logs it.
    private func offCard(_ off: OFFBeer) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                AsyncImage(url: off.imageURL.flatMap(URL.init)) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    Image(systemName: "mug.fill").foregroundStyle(Brand.malt)
                }
                .frame(width: 54, height: 54)
                .background(Brand.gold, in: RoundedRectangle(cornerRadius: 12))
                .clipShape(RoundedRectangle(cornerRadius: 12))

                VStack(alignment: .leading, spacing: 2) {
                    Text(off.name)
                        .font(.system(.headline, design: .rounded).weight(.bold))
                        .foregroundStyle(Brand.text)
                        .lineLimit(2)
                    Text([off.brand, off.abv.map { String(format: "%.1f%% ABV", $0) }]
                        .compactMap { $0 }.joined(separator: "  "))
                        .font(.caption).foregroundStyle(Brand.muted)
                }
                Spacer(minLength: 0)
            }

            Text(off.isBeerCategory
                 ? "Found in Open Food Facts, new to Tapt. Add it and be the first to log it worldwide."
                 : "Found in Open Food Facts, but it may not be a beer. Add it only if it belongs in the Cellar.")
                .font(.caption)
                .foregroundStyle(Brand.muted)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                ForEach(1...5, id: \.self) { i in
                    Image(systemName: Double(i) <= rating ? "star.fill" : "star")
                        .foregroundStyle(Brand.gold)
                        .onTapGesture { rating = Double(i) }
                }
                Spacer()
                Button(addingOFF ? "Adding..." : "Add to Tapt + log") { addAndLog(off) }
                    .font(.system(.subheadline, design: .rounded).weight(.bold))
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(Brand.hop, in: Capsule())
                    .foregroundStyle(Brand.malt)
                    .disabled(addingOFF)
            }
        }
        .padding(14)
        .background(Brand.surface, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Brand.hop.opacity(0.35)))
        .padding(.horizontal)
    }

    private func addAndLog(_ off: OFFBeer) {
        guard let uid = session.user?.id else { return }
        addingOFF = true
        Task {
            do {
                if let pick = try await BarcodeCatalogService.addToCatalog(off) {
                    try await CheckinService.log(beer: pick, userId: uid, rating: rating)
                    let pour = PourCard(
                        beer: pick.name,
                        brewery: pick.breweryName.isEmpty ? "First on Tapt" : pick.breweryName,
                        style: pick.style ?? "Beer",
                        score: Int(rating * 20),
                        user: session.user?.email?.split(separator: "@").first.map(String.init) ?? "beerfan",
                        abv: pick.abv.map { String(format: "%.1f%%", $0) }
                    )
                    addingOFF = false
                    showResult = false
                    Haptic.celebrate()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        loggedPour = pour
                    }
                } else {
                    addingOFF = false
                }
            } catch {
                addingOFF = false
            }
        }
    }

    /// Menu mode: batch-match every visible text line against the catalog.
    private func matchMenu() async {
        menuMatching = true
        defer { menuMatching = false }
        var found: [ScannedBeer] = []
        for line in visibleLines.prefix(10) {
            if let hits = try? await CheckinService.matchScan(line), let best = hits.first, best.confidence >= 0.3 {
                if !found.contains(where: { $0.id == best.id }) { found.append(best) }
            }
        }
        matches = found
        offBeer = nil
        scanned = "Menu scan: \(visibleLines.count) lines read"
        showResult = true
    }

    private func loadMatches(_ raw: String) async {
        loadingMatches = true
        selected = nil
        offBeer = nil
        defer { loadingMatches = false }
        matches = (try? await CheckinService.matchScan(raw)) ?? []

        // Barcode with no catalog hit -> ask Open Food Facts (free, open data).
        let digits = raw.filter(\.isNumber)
        if matches.isEmpty, digits.count >= 8, digits.count <= 14, digits.count == raw.trimmingCharacters(in: .whitespaces).count {
            offBeer = try? await BarcodeCatalogService.lookup(barcode: digits)
        }
    }

    private func save(_ beer: BeerPick) {
        guard let uid = session.user?.id else { return }
        saving = true
        Task {
            do {
                try await CheckinService.log(beer: beer, userId: uid, rating: rating)
                let pour = PourCard(
                    beer: beer.name,
                    brewery: beer.breweryName.isEmpty ? "Tapt Cellar" : beer.breweryName,
                    style: beer.style ?? "Beer",
                    score: Int(rating * 20),
                    user: session.user?.email?.split(separator: "@").first.map(String.init) ?? "beerfan",
                    abv: beer.abv.map { String(format: "%.1f%%", $0) }
                )
                saving = false
                showResult = false
                Haptic.celebrate()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    loggedPour = pour
                }
            } catch {
                saving = false
            }
        }
    }
}

extension String: @retroactive Identifiable {
    public var id: String { self }
}

/// A partner's live tap list, opened from their Tapt QR code.
struct PartnerMenuSheet: View {
    let venueId: String
    @State private var rows: [VenueMenuRow] = []
    @State private var events: [VenueEvent] = []
    @State private var loading = true

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    if loading {
                        TaptSkeletonList(rows: 4)
                    } else if rows.isEmpty {
                        TaptEmptyState(icon: "list.bullet.rectangle",
                                       title: "No live menu yet",
                                       message: "This venue hasn't published a current tap list. Tell them it's free, forever.",
                                       actionTitle: nil)
                    } else {
                        Text(rows[0].venueName)
                            .font(.system(.title, design: .rounded).weight(.heavy))
                            .foregroundStyle(Brand.text)
                            .padding(.horizontal)
                        ForEach(events) { event in
                            HStack(spacing: 10) {
                                Image(systemName: "calendar.badge.clock").foregroundStyle(Brand.malt)
                                    .frame(width: 34, height: 34)
                                    .background(Brand.gold, in: RoundedRectangle(cornerRadius: 9))
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(event.title)
                                        .font(.system(.subheadline, design: .rounded).weight(.bold))
                                        .foregroundStyle(Brand.text)
                                    Text(event.kindLabel)
                                        .font(.caption2.weight(.semibold)).foregroundStyle(Brand.copper)
                                }
                                Spacer()
                            }
                            .padding(11)
                            .background(Brand.gold.opacity(0.14), in: RoundedRectangle(cornerRadius: 13))
                            .padding(.horizontal)
                        }
                        ForEach(rows) { row in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(row.beerName)
                                        .font(.system(.headline, design: .rounded).weight(.bold))
                                        .foregroundStyle(Brand.text)
                                    Text([row.breweryName, row.style].compactMap { $0 }.joined(separator: " · "))
                                        .font(.caption).foregroundStyle(Brand.muted)
                                }
                                Spacer()
                                if let price = row.priceText {
                                    Text(price)
                                        .font(.system(.headline, design: .rounded).weight(.heavy))
                                        .foregroundStyle(Brand.copper)
                                }
                            }
                            .padding(13)
                            .background(Brand.surface, in: RoundedRectangle(cornerRadius: 14))
                            .padding(.horizontal)
                        }
                        Text("Live tap list, published by the venue on Tapt")
                            .font(.caption2).foregroundStyle(Brand.muted)
                            .padding(.horizontal)
                    }
                }
                .padding(.vertical)
            }
            .background(Brand.background)
            .navigationTitle("On tap")
            .navigationBarTitleDisplayMode(.inline)
        }
        .task {
            async let m = VenueMenuService.menu(venueId: venueId)
            async let e = VenueMenuService.events(venueId: venueId)
            rows = (try? await m) ?? []
            events = (try? await e) ?? []
            loading = false
        }
    }
}
