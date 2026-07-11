import SwiftUI
import Supabase

/// The "You" tab: account, appearance (dark/light/system), and preferences.
struct ProfileView: View {
    @Environment(Session.self) private var session
    @AppStorage("appearance") private var appearanceRaw = Appearance.system.rawValue
    @AppStorage("beerGeekMode") private var beerGeekMode = false
    @AppStorage("noLowDefault") private var noLowDefault = false
    @AppStorage("locationConsent") private var locationConsent = true
    @AppStorage("aggregateConsent") private var aggregateConsent = true
    @AppStorage("dataSaleConsent") private var dataSaleConsent = false
    @AppStorage("appLanguage") private var appLanguage = AppLanguage.system.rawValue
    @State private var languageChanged = false
    @State private var deletionRequested = false
    @State private var deletionError: String?

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
                    Picker("Language", selection: $appLanguage) {
                        ForEach(AppLanguage.allCases) { lang in
                            Text(lang.label).tag(lang.rawValue)
                        }
                    }
                    if languageChanged {
                        Label("Close and reopen Tapt to apply the new language.", systemImage: "arrow.triangle.2.circlepath")
                            .font(.footnote)
                            .foregroundStyle(Brand.copper)
                    }
                } header: {
                    Text("Language")
                } footer: {
                    Text("Tapt is global. Core screens are translated today; more strings and languages roll out over time.")
                }

                Section {
                    Toggle("Beer-geek mode", isOn: $beerGeekMode)
                    Toggle("No / Low lens by default", isOn: $noLowDefault)
                } header: {
                    Text("Preferences")
                } footer: {
                    Text("Beer-geek mode swaps in the lexicon: Cellar, Tick a Pour, Whales, Haul.")
                }

                Section {
                    Toggle("Nearby beer spots", isOn: $locationConsent)
                    Toggle("Anonymous trend reports", isOn: $aggregateConsent)
                    Toggle("Partner insight aggregates", isOn: $dataSaleConsent)
                } header: {
                    Text("Privacy Choices")
                } footer: {
                    Text("These choices are saved to your account and can be changed any time.")
                }

                Section {
                    NewsletterCard()
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                } header: {
                    Text("The Tapt Dispatch")
                }

                Section {
                    NavigationLink { PartnerInquiryView() } label: {
                        Label("Partner with Tapt", systemImage: "storefront.fill")
                    }
                } header: {
                    Text("For breweries & bars")
                } footer: {
                    Text("Free profile. Featured placement puts your taps and events in front of nearby drinkers.")
                }

                Section {
                    Label("Drink responsibly. Never drink and drive.", systemImage: "hand.raised.fill")
                        .foregroundStyle(Brand.text)
                    Link(destination: URL(string: "tel://18006624357")!) {
                        Label("Get support (SAMHSA, US)", systemImage: "phone.fill")
                    }
                } header: {
                    Text("Responsibility")
                } footer: {
                    Text("Tapt is for people of legal drinking age and does not sell alcohol.")
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
                    Button("Request account deletion", role: .destructive) {
                        requestDeletion()
                    }
                }

                if deletionRequested || deletionError != nil {
                    Section {
                        if deletionRequested {
                            Label("Deletion request received.", systemImage: "checkmark.seal.fill")
                                .foregroundStyle(Brand.hop)
                        }
                        if let deletionError {
                            Text(deletionError).foregroundStyle(.red)
                        }
                    }
                }
            }
            .navigationTitle("You")
            .onChange(of: appLanguage) { _, newValue in
                (AppLanguage(rawValue: newValue) ?? .system).apply()
                languageChanged = true
            }
            .onChange(of: beerGeekMode) { _, newValue in syncBeerGeek(newValue) }
            .onChange(of: locationConsent) { _, newValue in
                syncPrivacy("location", granted: newValue, text: "Nearby beer spots")
            }
            .onChange(of: aggregateConsent) { _, newValue in
                syncPrivacy("aggregate_analytics", granted: newValue, text: "Anonymous trend reports")
            }
            .onChange(of: dataSaleConsent) { _, newValue in
                syncPrivacy("data_sale", granted: newValue, text: "Partner insight aggregates")
            }
        }
    }

    /// Persist beer-geek mode to the profile so it follows the account across devices.
    private func syncBeerGeek(_ value: Bool) {
        guard let id = session.user?.id else { return }
        Task { await ProfileService.setBeerGeek(value, userId: id) }
    }

    private func syncPrivacy(_ purpose: String, granted: Bool, text: String) {
        guard let id = session.user?.id else { return }
        Task {
            await ProfileService.setPrivacyChoice(
                purpose: purpose,
                granted: granted,
                uiText: text,
                userId: id
            )
        }
    }

    private func requestDeletion() {
        guard let id = session.user?.id else { return }
        deletionError = nil
        Task {
            do {
                try await ProfileService.requestAccountDeletion(userId: id)
                deletionRequested = true
            } catch {
                deletionError = error.localizedDescription
            }
        }
    }
}
