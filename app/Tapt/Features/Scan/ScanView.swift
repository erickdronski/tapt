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

    private var scannerAvailable: Bool {
        DataScannerViewController.isSupported && DataScannerViewController.isAvailable
    }

    var body: some View {
        NavigationStack {
            Group {
                if scannerAvailable {
                    DataScannerView(scanned: $scanned)
                        .ignoresSafeArea(edges: .bottom)
                        .overlay(alignment: .bottom) { hint }
                } else {
                    unsupported
                }
            }
            .navigationTitle("Scan")
            .navigationBarTitleDisplayMode(.inline)
            .onChange(of: scanned) { _, value in
                if let value {
                    showResult = true
                    Task { await loadMatches(value) }
                }
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

    private func loadMatches(_ raw: String) async {
        loadingMatches = true
        selected = nil
        defer { loadingMatches = false }
        matches = (try? await CheckinService.matchScan(raw)) ?? []
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
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    loggedPour = pour
                }
            } catch {
                saving = false
            }
        }
    }
}
