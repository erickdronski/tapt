import SwiftUI
import Supabase

// The searchable global beer catalog: every beer in the Tapt database, growing
// as ingestion runs. Fuzzy search over name + brewery, style + No/Low filters,
// image thumbnails, infinite scroll, tap through to the full beer page.

struct CatalogEntry: Identifiable, Decodable, Hashable {
    let id: String
    let name: String
    let style: String?
    let abv: Double?
    let isNaLow: Bool?
    let breweryName: String?
    let country: String?
    let imageUrl: String?
    let total: Int?

    enum CodingKeys: String, CodingKey {
        case id, name, style, abv, country, total
        case isNaLow = "is_na_low"
        case breweryName = "brewery_name"
        case imageUrl = "image_url"
    }
}

enum CatalogService {
    static func search(query: String, style: String? = nil, naOnly: Bool = false,
                       limit: Int = 30, offset: Int = 0) async throws -> [CatalogEntry] {
        struct Params: Encodable {
            let p_query: String?
            let p_style: String?
            let p_na_only: Bool
            let p_limit: Int
            let p_offset: Int
        }
        return try await Supa.client.rpc("catalog_search", params: Params(
            p_query: query.isEmpty ? nil : query,
            p_style: (style?.isEmpty ?? true) ? nil : style,
            p_na_only: naOnly, p_limit: limit, p_offset: offset
        )).execute().value
    }
}

struct CatalogView: View {
    private let pageSize = 30
    private let styles = ["IPA", "Lager", "Pilsner", "Stout", "Porter", "Sour", "Wheat", "Pale Ale", "Amber"]

    @State private var query = ""
    @State private var style: String? = nil
    @State private var naOnly = false
    @State private var results: [CatalogEntry] = []
    @State private var total = 0
    @State private var loading = false
    @State private var loadingMore = false

    private var canLoadMore: Bool { results.count < total }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                header

                if loading && results.isEmpty {
                    TaptSkeletonList(rows: 8)
                } else if results.isEmpty {
                    empty
                } else {
                    ForEach(results) { beer in
                        NavigationLink { BeerDetailView(beerId: beer.id) } label: { row(beer) }
                            .buttonStyle(.plain)
                            .task { if beer.id == results.last?.id { await loadMore() } }
                        Divider().overlay(Brand.malt.opacity(0.06)).padding(.leading, 78)
                    }
                    if loadingMore {
                        ProgressView().tint(Brand.gold).frame(maxWidth: .infinity).padding(.vertical, 18)
                    }
                }
            }
            .padding(.vertical, 8)
        }
        .background(Brand.background)
        .navigationTitle("Catalog")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always),
                    prompt: "Search every beer, brewery, style")
        .task(id: SearchKey(query: query, style: style, naOnly: naOnly)) { await reload() }
    }

    // debounce + filter identity
    private struct SearchKey: Equatable { let query: String; let style: String?; let naOnly: Bool }

    // MARK: - Header (count + filters)

    private var header: some View {
        VStack(spacing: 12) {
            HStack {
                Text(total > 0 ? "\(total.formatted()) beers" : "Browse the catalog")
                    .font(.system(.subheadline, design: .rounded).weight(.bold))
                    .foregroundStyle(Brand.text)
                Spacer()
                Toggle(isOn: $naOnly) {
                    Label("No / Low", systemImage: "leaf.fill").font(.caption.weight(.semibold))
                }
                .toggleStyle(.button)
                .tint(Brand.hop)
                .controlSize(.small)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    chip("All", active: style == nil) { style = nil }
                    ForEach(styles, id: \.self) { s in
                        chip(s, active: style == s) { style = (style == s ? nil : s) }
                    }
                }
            }
        }
        .padding(.horizontal)
        .padding(.bottom, 10)
    }

    private func chip(_ label: String, active: Bool, _ tap: @escaping () -> Void) -> some View {
        Button(action: tap) {
            Text(label)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(active ? Brand.gold : Brand.surface, in: Capsule())
                .foregroundStyle(active ? Brand.malt : Brand.text)
                .overlay(Capsule().stroke(Brand.malt.opacity(0.10)))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Row

    private func row(_ beer: CatalogEntry) -> some View {
        HStack(spacing: 12) {
            thumbnail(beer)
            VStack(alignment: .leading, spacing: 2) {
                Text(beer.name)
                    .font(.system(.subheadline, design: .rounded).weight(.bold))
                    .foregroundStyle(Brand.text)
                    .lineLimit(1)
                Text([beer.breweryName, beer.country].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.caption).foregroundStyle(Brand.muted).lineLimit(1)
                HStack(spacing: 6) {
                    if let style = beer.style, !style.isEmpty {
                        Text(style).font(.caption2.weight(.semibold)).foregroundStyle(Brand.copper)
                    }
                    if let abv = beer.abv {
                        Text("\(abv, specifier: "%.1f")%").font(.caption2.weight(.semibold)).foregroundStyle(Brand.muted)
                    }
                    if beer.isNaLow == true {
                        Text("NA/Low").font(.caption2.weight(.heavy)).foregroundStyle(Brand.hop)
                    }
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(Brand.muted.opacity(0.5))
        }
        .padding(.horizontal).padding(.vertical, 10)
        .contentShape(Rectangle())
    }

    private func thumbnail(_ beer: CatalogEntry) -> some View {
        BeerThumb(imageUrl: beer.imageUrl, size: 54)
    }

    private var empty: some View {
        VStack(spacing: 8) {
            Image(systemName: "magnifyingglass").font(.largeTitle).foregroundStyle(Brand.muted)
            Text(query.isEmpty ? "The catalog is loading." : "No beers match “\(query)” yet.")
                .font(.subheadline).foregroundStyle(Brand.muted).multilineTextAlignment(.center)
            if !query.isEmpty {
                Text("Scan its barcode to add it, or check back as the catalog grows.")
                    .font(.caption).foregroundStyle(Brand.muted.opacity(0.8)).multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity).padding(.top, 60).padding(.horizontal, 40)
    }

    // MARK: - Loading

    @MainActor private func reload() async {
        loading = true
        try? await Task.sleep(for: .milliseconds(280))  // debounce typing
        if Task.isCancelled { loading = false; return }
        do {
            let page = try await CatalogService.search(query: query, style: style, naOnly: naOnly,
                                                       limit: pageSize, offset: 0)
            // A superseded (cancelled) search must not clobber the newer one's results.
            if Task.isCancelled { return }
            results = page
            total = page.first?.total ?? page.count
        } catch is CancellationError {
            return
        } catch let error as URLError where error.code == .cancelled {
            return
        } catch {
            results = []; total = 0
        }
        loading = false
    }

    @MainActor private func loadMore() async {
        guard canLoadMore, !loadingMore, !loading else { return }
        loadingMore = true
        do {
            let page = try await CatalogService.search(query: query, style: style, naOnly: naOnly,
                                                       limit: pageSize, offset: results.count)
            let existing = Set(results.map(\.id))
            results.append(contentsOf: page.filter { !existing.contains($0.id) })
            if let t = page.first?.total { total = t }
        } catch { /* keep what we have */ }
        loadingMore = false
    }
}

#Preview {
    NavigationStack { CatalogView() }
}

/// A beer's real product photo when we have one (Open Food Facts label imagery,
/// ~95% of the catalog), with an honest tinted-glass fallback otherwise. Never a
/// fabricated or generated image. Reused anywhere a beer is named in a row.
struct BeerThumb: View {
    let imageUrl: String?
    var size: CGFloat = 44
    var corner: CGFloat = 11

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: corner).fill(Brand.surface)
            if let imageUrl, !imageUrl.isEmpty, let url = URL(string: imageUrl) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let img): img.resizable().scaledToFit().padding(size * 0.075)
                    default: Self.fallback(size)
                    }
                }
            } else {
                Self.fallback(size)
            }
        }
        .frame(width: size, height: size)
        .overlay(RoundedRectangle(cornerRadius: corner).stroke(Brand.malt.opacity(0.08)))
    }

    private static func fallback(_ size: CGFloat) -> some View {
        Image(systemName: "mug.fill")
            .font(.system(size: size * 0.37))
            .foregroundStyle(Brand.gold.opacity(0.7))
    }
}
