import SwiftUI
import Supabase

/// The "You" tab: account, appearance (dark/light/system), and preferences.
struct ProfileView: View {
    @Environment(Session.self) private var session
    @AppStorage("appearance") private var appearanceRaw = Appearance.system.rawValue
    @AppStorage("beerGeekMode") private var beerGeekMode = false
    @AppStorage("noLowDefault") private var noLowDefault = false
    @AppStorage("favoriteStyles") private var favoriteStyles = ""
    @AppStorage("locationConsent") private var locationConsent = false
    @AppStorage("aggregateConsent") private var aggregateConsent = false
    @AppStorage("dataSaleConsent") private var dataSaleConsent = false
    @AppStorage("socialVisible") private var socialVisible = false
    @AppStorage("appLanguage") private var appLanguage = AppLanguage.system.rawValue
    @State private var languageChanged = false
    @State private var isHydratingPrivacy = true
    // What the server currently holds, keyed by purpose. Writes that only echo
    // these values back are skipped: hydration can fire onChange after the
    // isHydratingPrivacy window closes, and those are not user edits.
    @State private var serverConsents: [String: Bool] = [:]
    @State private var privacyError: String?
    @State private var showDeleteConfirmation = false
    @State private var deleting = false
    @State private var deletionError: String?
    @State private var myActivity: [MyBeerActivity] = []
    @State private var activityError: String?

    private var displayName: String {
        if let name = session.user?.userMetadata["full_name"]?.stringValue, !name.isEmpty { return name }
        return session.user?.email ?? "Guest explorer"
    }
    private var email: String { session.user?.email ?? "" }
    private var initial: String { String(displayName.first ?? "T").uppercased() }
    private var tasteSummary: String {
        let count = TastePreferences.decode(favoriteStyles).count
        return count == 0 ? "Choose" : "\(count) selected"
    }

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

                if session.user == nil {
                    Section {
                        Button {
                            session.endGuestSession()
                        } label: {
                            Label("Sign in or create an account", systemImage: "person.crop.circle.badge.plus")
                                .font(.headline)
                                .foregroundStyle(Brand.malt)
                        }
                    } footer: {
                        Text("Sign in to log pours, vote, follow friends, save privacy choices, and build your Passport.")
                    }
                }

                if !myActivity.isEmpty {
                    Section {
                        ForEach(myActivity) { a in
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
                        Text("Your beers")
                    } footer: {
                        Text("Your votes count on the Beer Market. Your notes are private to you.")
                    }
                }

                if let activityError {
                    Section {
                        Button {
                            Task { await loadActivity() }
                        } label: {
                            Label(activityError, systemImage: "arrow.clockwise")
                                .foregroundStyle(Brand.copper)
                        }
                    }
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
                    if session.user != nil {
                        NavigationLink { TastePreferencesView() } label: {
                            LabeledContent("Favorite styles", value: tasteSummary)
                        }
                    }
                } header: {
                    Text("Preferences")
                } footer: {
                    Text("Beer-geek mode swaps in the lexicon: Cellar, Tick a Pour, Whales, Haul.")
                }

                if session.user != nil {
                    Section {
                        Toggle("Nearby beer spots", isOn: $locationConsent)
                        Toggle("Anonymous trend reports", isOn: $aggregateConsent)
                        Toggle("Share anonymized aggregates with partners", isOn: $dataSaleConsent)
                        Toggle("Public social passport", isOn: $socialVisible)
                        if socialVisible, let userId = session.user?.id.uuidString {
                            NavigationLink {
                                PublicProfileView(userId: userId, initialName: displayName)
                            } label: {
                                Label("See your public profile", systemImage: "person.crop.circle")
                            }
                        }
                        if let privacyError {
                            Label(privacyError, systemImage: "exclamationmark.triangle.fill")
                                .font(.footnote)
                                .foregroundStyle(.red)
                        }
                    } header: {
                        Text("Privacy Choices")
                    } footer: {
                        Text("Optional sharing starts off. These choices are saved to your account and can be changed any time.")
                    }
                } else {
                    Section {
                        Toggle("Nearby beer spots", isOn: $locationConsent)
                    } header: {
                        Text("Location")
                    } footer: {
                        Text("Location stays optional and is used to find real beer spots near you.")
                    }
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
                    Link("Support", destination: URL(string: AppLinks.support)!)
                    Link("Contact & support", destination: URL(string: "mailto:hello@taptbeer.com")!)
                    Link("Privacy Policy", destination: URL(string: AppLinks.privacy)!)
                    Link("Terms of Service", destination: URL(string: AppLinks.terms)!)
                }

                if session.user != nil {
                    Section {
                        Button("Sign out", role: .destructive) {
                            Task { await session.signOut() }
                        }
                        Button(role: .destructive) {
                            showDeleteConfirmation = true
                        } label: {
                            Label(deleting ? "Deleting account..." : "Delete account", systemImage: "trash.fill")
                        }
                        .disabled(deleting)
                    }
                }

                if deletionError != nil {
                    Section {
                        if let deletionError {
                            Text(deletionError).foregroundStyle(.red)
                        }
                    }
                }
            }
            .navigationTitle("You")
            .task {
                await loadActivity()
                _ = await loadPrivacyChoices()
            }
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
                syncPrivacy("data_sale", granted: newValue, text: "Share anonymized aggregates with partners")
            }
            .onChange(of: socialVisible) { _, newValue in
                syncSocialVisibility(newValue)
            }
            .alert("Delete your Tapt account?", isPresented: $showDeleteConfirmation) {
                Button("Delete account", role: .destructive) { deleteAccount() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This permanently removes your profile, private notes, votes, pours, follows, venue claims, and sign-in identity. This cannot be undone.")
            }
        }
    }

    /// Persist beer-geek mode to the profile so it follows the account across devices.
    private func syncBeerGeek(_ value: Bool) {
        guard !isHydratingPrivacy, !deleting, let id = session.user?.id else { return }
        guard serverConsents["beer_geek_mode"] != value else { return }
        serverConsents["beer_geek_mode"] = value
        Task {
            do {
                try await ProfileService.setBeerGeek(value, userId: id)
                privacyError = nil
            } catch {
                let restored = await loadPrivacyChoices(reportErrors: false)
                privacyError = restored
                    ? "Beer-geek mode was not saved. Your server setting was restored."
                    : "Beer-geek mode was not saved. Reconnect and try again."
            }
        }
    }

    private func syncPrivacy(_ purpose: String, granted: Bool, text: String) {
        guard !isHydratingPrivacy, !deleting, let id = session.user?.id else { return }
        // No-op echoes of the server's own value are not consent events.
        guard serverConsents[purpose] != granted else { return }
        serverConsents[purpose] = granted  // optimistic; the failure path reloads
        Task {
            do {
                try await ProfileService.setPrivacyChoice(
                    purpose: purpose,
                    granted: granted,
                    uiText: text,
                    userId: id
                )
                privacyError = nil
            } catch {
                let restored = await loadPrivacyChoices(reportErrors: false)
                privacyError = restored
                    ? "That privacy choice was not saved. Your server setting was restored."
                    : "That privacy choice was not saved. Reconnect and try again."
            }
        }
    }

    private func syncSocialVisibility(_ visible: Bool) {
        guard !isHydratingPrivacy, !deleting else { return }
        guard serverConsents["social_visible"] != visible else { return }
        serverConsents["social_visible"] = visible
        Task {
            do {
                try await ProfileService.setSocialVisibility(visible)
                privacyError = nil
            } catch {
                let restored = await loadPrivacyChoices(reportErrors: false)
                privacyError = restored
                    ? "Social visibility was not saved. Your server setting was restored."
                    : "Social visibility was not saved. Reconnect and try again."
            }
        }
    }

    @discardableResult
    private func loadPrivacyChoices(reportErrors: Bool = true) async -> Bool {
        guard let id = session.user?.id else {
            isHydratingPrivacy = false
            return false
        }
        do {
            let choices = try await ProfileService.privacyChoices(userId: id)
            isHydratingPrivacy = true
            // The map goes first: if an onChange from these assignments lands
            // after the hydration window closes, the echo guard still holds.
            serverConsents = [
                "location": choices.location,
                "aggregate_analytics": choices.aggregateAnalytics,
                "data_sale": choices.dataSale,
                "social_visible": choices.socialVisible,
                "beer_geek_mode": choices.beerGeekMode
            ]
            locationConsent = choices.location
            aggregateConsent = choices.aggregateAnalytics
            dataSaleConsent = choices.dataSale
            socialVisible = choices.socialVisible
            beerGeekMode = choices.beerGeekMode
            await Task.yield()
            isHydratingPrivacy = false
            if reportErrors { privacyError = nil }
            return true
        } catch {
            isHydratingPrivacy = false
            if reportErrors {
                privacyError = "Your account privacy settings could not be loaded. Optional sharing remains off on this device."
            }
            return false
        }
    }

    private func deleteAccount() {
        guard let id = session.user?.id else { return }
        deletionError = nil
        deleting = true
        Task {
            do {
                try await ProfileService.requestAccountDeletion(userId: id)
                locationConsent = false
                aggregateConsent = false
                dataSaleConsent = false
                socialVisible = false
                beerGeekMode = false
                myActivity = []
                activityError = nil
                await session.signOut()
            } catch {
                deletionError = "Account deletion did not complete. Check your connection and try again, or contact support."
            }
            deleting = false
        }
    }

    /// The beers you've voted on or noted -- your votes feed the Beer Market, your
    /// notes stay private to you. Loaded from first-party data, never invented.
    private func loadActivity() async {
        guard session.user != nil else { return }
        do {
            myActivity = try await MyActivityService.fetch()
            activityError = nil
        } catch {
            activityError = "Your beer activity could not refresh. Tap to try again."
        }
    }
}

/// One beer you've engaged with: your private note and/or your market vote.
struct MyBeerActivity: Identifiable, Decodable, Sendable {
    let beerId: String
    let name: String
    let imageUrl: String?
    let style: String?
    let note: String?
    let vote: Int?

    var id: String { beerId }

    enum CodingKeys: String, CodingKey {
        case name, style, note, vote
        case beerId = "beer_id"
        case imageUrl = "image_url"
    }
}

enum MyActivityService {
    static func fetch() async throws -> [MyBeerActivity] {
        struct Empty: Encodable {}
        return try await Supa.authedRPC("my_beer_activity", params: Empty())
    }
}
