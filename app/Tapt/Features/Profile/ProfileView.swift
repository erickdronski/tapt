import SwiftUI
import Supabase

/// The "You" tab: account, appearance (dark/light/system), and preferences.
struct ProfileView: View {
    @Environment(Session.self) private var session
    @AppStorage("appearance") private var appearanceRaw = Appearance.system.rawValue
    @AppStorage("beerGeekMode") private var beerGeekMode = false
    @AppStorage("noLowDefault") private var noLowDefault = false

    private var displayName: String {
        if let name = session.user?.userMetadata["full_name"]?.stringValue, !name.isEmpty { return name }
        return session.user?.email ?? "Beer fan"
    }
    private var email: String { session.user?.email ?? "" }
    private var initial: String { String(displayName.first ?? "T").uppercased() }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 14) {
                        Text(initial)
                            .font(.system(size: 26, weight: .heavy, design: .rounded))
                            .foregroundStyle(Brand.malt)
                            .frame(width: 58, height: 58)
                            .background(Brand.gold, in: Circle())
                            .overlay(Circle().stroke(Brand.malt, lineWidth: 2))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(displayName).font(.system(.title3, design: .rounded).weight(.bold))
                            if !email.isEmpty {
                                Text(email).font(.subheadline).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(.vertical, 6)
                }

                Section("Appearance") {
                    Picker("Theme", selection: $appearanceRaw) {
                        ForEach(Appearance.allCases) { Text($0.label).tag($0.rawValue) }
                    }
                    .pickerStyle(.segmented)
                }

                Section {
                    Toggle("Beer-geek mode", isOn: $beerGeekMode)
                    Toggle("No / Low lens by default", isOn: $noLowDefault)
                } header: {
                    Text("Preferences")
                } footer: {
                    Text("Beer-geek mode swaps in the lexicon: Cellar, Tick a Pour, Whales, Haul.")
                }

                Section("About") {
                    LabeledContent("Version", value: AppInfo.version)
                    Link("Privacy Policy", destination: URL(string: "https://tapt.app/privacy")!)
                    Link("Terms of Service", destination: URL(string: "https://tapt.app/terms")!)
                }

                Section {
                    Button("Sign out", role: .destructive) {
                        Task { await session.signOut() }
                    }
                }
            }
            .navigationTitle("You")
            .onChange(of: beerGeekMode) { _, newValue in syncBeerGeek(newValue) }
        }
    }

    /// Persist beer-geek mode to the profile so it follows the account across devices.
    private func syncBeerGeek(_ value: Bool) {
        guard let id = session.user?.id else { return }
        Task {
            try? await Supa.client
                .from("user_profile")
                .update(["beer_geek_mode": value])
                .eq("id", value: id.uuidString)
                .execute()
        }
    }
}
