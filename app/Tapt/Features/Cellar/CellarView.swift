import SwiftUI

/// Cellar: your logged pours + a Passport strip (pours, styles, countries). Log flow wired in.
struct CellarView: View {
    @Environment(Session.self) private var session
    @State private var checkins: [MyCheckin] = []
    @State private var showLog = false

    private var styleCount: Int {
        Set(checkins.compactMap { ($0.style?.isEmpty == false) ? $0.style : nil }).count
    }
    private var countryCount: Int {
        Set(checkins.map(\.country).filter { !$0.isEmpty }).count
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Brand.background.ignoresSafeArea()
                if checkins.isEmpty { empty } else { content }
            }
            .navigationTitle("Cellar")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { showLog = true } label: {
                        Image(systemName: "plus.circle.fill").foregroundStyle(Brand.gold)
                    }
                }
            }
            .task { await load() }
            .sheet(isPresented: $showLog) {
                LogPourView(onLogged: { Task { await load() } })
            }
        }
    }

    private var empty: some View {
        VStack(spacing: 16) {
            Image(systemName: "square.stack.3d.up.fill").font(.system(size: 44)).foregroundStyle(Brand.gold)
            Text("Your Cellar is thirsty").font(.system(.title, design: .rounded).weight(.heavy)).foregroundStyle(Brand.text)
            Text("Log your first pour to start your Cellar and fill your Passport.")
                .font(.body).foregroundStyle(Brand.muted).multilineTextAlignment(.center).padding(.horizontal, 36)
            Button { showLog = true } label: {
                Label("Log a pour", systemImage: "plus.circle.fill")
                    .font(.system(.headline, design: .rounded))
                    .padding(.horizontal, 20).padding(.vertical, 13)
                    .background(Brand.gold, in: Capsule()).foregroundStyle(Brand.malt)
            }
            .padding(.top, 6)
        }
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Passport").font(.system(.title3, design: .rounded).weight(.bold)).foregroundStyle(Brand.text).padding(.horizontal)
                HStack(spacing: 12) {
                    stat("\(checkins.count)", "pours", "drop.fill", Brand.gold)
                    stat("\(styleCount)", "styles", "square.grid.2x2.fill", Brand.hop)
                    stat("\(countryCount)", "countries", "globe", Brand.copper)
                }
                .padding(.horizontal)

                Text("Your pours").font(.system(.title3, design: .rounded).weight(.bold)).foregroundStyle(Brand.text).padding(.horizontal).padding(.top, 4)
                VStack(spacing: 10) {
                    ForEach(checkins) { row($0) }
                }
                .padding(.horizontal)
            }
            .padding(.vertical)
        }
    }

    private func stat(_ n: String, _ label: String, _ icon: String, _ tint: Color) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon).foregroundStyle(tint)
            Text(n).font(.system(.title2, design: .rounded).weight(.heavy)).foregroundStyle(Brand.text)
            Text(label).font(.caption).foregroundStyle(Brand.muted)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 14)
        .background(Brand.surface, in: RoundedRectangle(cornerRadius: 16))
    }

    private func row(_ c: MyCheckin) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "mug.fill").foregroundStyle(Brand.malt)
                .frame(width: 40, height: 40).background(Brand.gold, in: RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 2) {
                Text(c.beerName).font(.system(.headline, design: .rounded)).foregroundStyle(Brand.text).lineLimit(1)
                Text("\(c.breweryName)  \(c.style ?? "")").font(.caption).foregroundStyle(Brand.muted).lineLimit(1)
            }
            Spacer()
            if let r = c.rating {
                HStack(spacing: 2) {
                    Image(systemName: "star.fill").font(.caption2).foregroundStyle(Brand.gold)
                    Text(String(format: "%.0f", r)).font(.system(.subheadline, design: .rounded).weight(.bold)).foregroundStyle(Brand.text)
                }
            }
        }
        .padding(12).background(Brand.surface, in: RoundedRectangle(cornerRadius: 14))
    }

    private func load() async {
        guard let uid = session.user?.id else { return }
        checkins = (try? await CheckinService.mine(userId: uid)) ?? []
    }
}
