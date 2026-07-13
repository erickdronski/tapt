import SwiftUI
import Supabase

/// First-run onboarding: welcome, taste preferences, home region. Springy, brand-forward,
/// and it seeds the taste profile (region_code + taste_vector.top_styles).
struct OnboardingView: View {
    @Environment(Session.self) private var session
    @AppStorage("onboardedUserIDs") private var onboardedUserIDs = ""
    @AppStorage("passport.seenBadges") private var seenBadgesRaw = ""
    @AppStorage("passport.badgesSeeded") private var badgesSeeded = false
    @AppStorage("favoriteStyles") private var favoriteStyles = ""
    @AppStorage("homeRegion") private var homeRegion = "Global"
    @AppStorage("noLowDefault") private var noLowDefault = false
    @AppStorage("locationConsent") private var savedLocationConsent = false
    @AppStorage("aggregateConsent") private var savedAggregateConsent = false
    @AppStorage("dataSaleConsent") private var savedDataSaleConsent = false
    @AppStorage("legalAgeConfirmed") private var legalAgeConfirmed = false

    @State private var step = 0
    @State private var styles: Set<String> = []
    @State private var region = "Global"
    @State private var locationConsent = false
    @State private var aggregateConsent = false
    @State private var dataSaleConsent = false
    @State private var newsletterOptIn = false
    @State private var saving = false
    @State private var saveError: String?

    private let allStyles = ["IPA", "Hazy IPA", "Pilsner", "Lager", "Stout", "Porter",
                             "Sour", "Belgian", "Wheat", "Pale Ale", "No / Low"]
    private let total = 5

    var body: some View {
        ZStack {
            Brand.background.ignoresSafeArea()
            VStack(spacing: 20) {
                progress
                TabView(selection: $step) {
                    welcome.tag(0)
                    legalStep.tag(1)
                    stylesStep.tag(2)
                    regionStep.tag(3)
                    finishStep.tag(4)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(.spring(response: 0.5, dampingFraction: 0.8), value: step)
                footer
            }
            .padding()
        }
    }

    private var progress: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Brand.haze)
                Capsule().fill(Brand.gold)
                    .frame(width: geo.size.width * CGFloat(step + 1) / CGFloat(total))
                    .animation(.spring(response: 0.5, dampingFraction: 0.8), value: step)
            }
        }
        .frame(height: 8)
    }

    private var welcome: some View {
        VStack(spacing: 22) {
            Spacer()
            BeerGlassView(pour: 0.82).frame(width: 132)
            Text("Welcome to Tapt")
                .font(.system(size: 34, weight: .heavy, design: .rounded)).foregroundStyle(Brand.text)
            Text("The Beer Superapp in your pocket. Scan it, score it, play a round, and find local beer spots.")
                .font(.body).foregroundStyle(Brand.muted).multilineTextAlignment(.center).padding(.horizontal, 24)
            Spacer()
        }
    }

    private var stylesStep: some View {
        VStack(spacing: 18) {
            stepTitle("What do you love?", "Pick your go-to styles. We will tune your feed.")
            ScrollView { FlowChips(items: allStyles, selection: $styles) }
            Spacer(minLength: 0)
        }
    }

    private var legalStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            stepTitle("Your privacy choices", "Optional data choices stay attached to your account and can change any time.")
            VStack(spacing: 12) {
                Toggle("Use my location for nearby pubs, bars, breweries, taprooms, and beer gardens.", isOn: $locationConsent)
                Toggle("Use my check-ins for anonymous aggregate trend reports.", isOn: $aggregateConsent)
                Toggle("Share anonymized aggregates with partners.", isOn: $dataSaleConsent)
            }
            .toggleStyle(.switch)
            .font(.system(.body, design: .rounded))
            .foregroundStyle(Brand.text)
            .padding(16)
            .background(Brand.surface, in: RoundedRectangle(cornerRadius: 18))
            Text("Age was confirmed before sign-in. Tapt stores only that confirmation, not your date of birth.")
                .font(.footnote)
                .foregroundStyle(Brand.muted)
            Spacer()
        }
    }

    private var regionStep: some View {
        VStack(spacing: 18) {
            stepTitle("Where is home base?", "So we can show what is hot in your area.")
            ScrollView {
                VStack(spacing: 10) {
                    ForEach(["Global"] + BeerRegions.countries + BeerRegions.states, id: \.self) { r in
                        Button { region = r } label: {
                            HStack {
                                Text(r).font(.system(.headline, design: .rounded)).foregroundStyle(Brand.text)
                                Spacer()
                                if region == r { Image(systemName: "checkmark.circle.fill").foregroundStyle(Brand.hop) }
                            }
                            .padding(14)
                            .background(region == r ? Brand.gold.opacity(0.2) : Brand.surface, in: RoundedRectangle(cornerRadius: 14))
                            .overlay(RoundedRectangle(cornerRadius: 14).stroke(region == r ? Brand.gold : Brand.malt.opacity(0.1), lineWidth: region == r ? 2 : 1))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
            }
        }
    }

    private var finishStep: some View {
        VStack(spacing: 18) {
            Spacer()
            BeerGlassView(pour: 0.82).frame(width: 132)
            Text("You are all set\(firstName)")
                .font(.system(size: 30, weight: .heavy, design: .rounded)).foregroundStyle(Brand.text).multilineTextAlignment(.center)
            Text("\(styles.count) styles picked, home base \(region). Scan a label or barcode, log the pour, and stamp the Passport.")
                .font(.body).foregroundStyle(Brand.muted).multilineTextAlignment(.center).padding(.horizontal, 24)

            Toggle(isOn: $newsletterOptIn) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Send me The Tapt Dispatch")
                        .font(.system(.subheadline, design: .rounded).weight(.bold))
                        .foregroundStyle(Brand.text)
                    Text("The free beer newsletter: trends, new spots, what the world is pouring.")
                        .font(.caption)
                        .foregroundStyle(Brand.muted)
                }
            }
            .toggleStyle(.switch)
            .padding(14)
            .background(Brand.surface, in: RoundedRectangle(cornerRadius: 16))
            .padding(.horizontal, 24)
            Spacer()
        }
    }

    private var footer: some View {
        HStack {
            if step > 0 {
                Button("Back") { withAnimation { step -= 1 } }
                    .foregroundStyle(Brand.muted).font(.system(.headline, design: .rounded))
            }
            Spacer()
            Button(step < total - 1 ? "Continue" : "Start pouring") {
                if step < total - 1 { withAnimation { step += 1 } } else { complete() }
            }
            .font(.system(.headline, design: .rounded))
            .padding(.horizontal, 26).padding(.vertical, 14)
            .background(Brand.gold, in: Capsule()).foregroundStyle(Brand.malt)
            .disabled(saving)
            .opacity(saving ? 0.45 : 1)
        }
        .overlay(alignment: .top) {
            if saving {
                ProgressView("Saving...")
                    .padding(10)
                    .background(Brand.surface, in: Capsule())
            } else if let saveError {
                Text(saveError)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(10)
                    .background(Brand.surface, in: RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    private func stepTitle(_ t: String, _ s: String) -> some View {
        VStack(spacing: 6) {
            Text(t).font(.system(size: 28, weight: .heavy, design: .rounded)).foregroundStyle(Brand.text).multilineTextAlignment(.center)
            Text(s).font(.subheadline).foregroundStyle(Brand.muted).multilineTextAlignment(.center)
        }
        .padding(.top)
    }

    private var firstName: String {
        guard let full = session.user?.userMetadata["full_name"]?.stringValue,
              let first = full.split(separator: " ").first else { return "" }
        return ", \(first)"
    }

    private func complete() {
        guard legalAgeConfirmed, let uid = session.user?.id else {
            saveError = "Confirm legal drinking age before continuing."
            return
        }
        favoriteStyles = styles.sorted().joined(separator: ",")
        homeRegion = region
        noLowDefault = styles.contains("No / Low")
        savedLocationConsent = locationConsent
        savedAggregateConsent = aggregateConsent
        savedDataSaleConsent = dataSaleConsent
        saving = true
        saveError = nil
        let picked = Array(styles)
        Task {
            do {
                try await ProfileService.completeOnboarding(
                    userId: uid,
                    ageConfirmed: legalAgeConfirmed,
                    region: region,
                    topStyles: picked,
                    locationConsent: locationConsent,
                    aggregateConsent: aggregateConsent,
                    dataSaleConsent: dataSaleConsent
                )
                if newsletterOptIn, let email = session.user?.email, email.contains("@") {
                    try? await NewsletterService.subscribe(email: email, source: "onboarding")
                }
                var ids = Set(onboardedUserIDs.split(separator: ",").map(String.init))
                ids.insert(uid.uuidString)
                onboardedUserIDs = ids.sorted().joined(separator: ",")
                // Seed the passport badge tracker at this known-empty point so
                // the very first badge (First Pour) still gets its celebration.
                seenBadgesRaw = ""
                badgesSeeded = true
            } catch {
                saveError = "Could not save your setup. Try again."
            }
            saving = false
        }
    }
}

/// Wrapping selectable chips.
private struct FlowChips: View {
    let items: [String]
    @Binding var selection: Set<String>
    private let cols = [GridItem(.adaptive(minimum: 104), spacing: 10)]

    var body: some View {
        LazyVGrid(columns: cols, spacing: 10) {
            ForEach(items, id: \.self) { item in
                let on = selection.contains(item)
                Button {
                    if on { selection.remove(item) } else { selection.insert(item) }
                } label: {
                    Text(item)
                        .font(.system(.subheadline, design: .rounded).weight(.semibold))
                        .frame(maxWidth: .infinity).padding(.vertical, 12)
                        .background(on ? Brand.gold : Brand.surface, in: Capsule())
                        .foregroundStyle(on ? Brand.malt : Brand.text)
                        .overlay(Capsule().stroke(on ? Brand.gold : Brand.malt.opacity(0.15)))
                        .scaleEffect(on ? 1.04 : 1)
                }
                .buttonStyle(.plain)
                .animation(.spring(response: 0.3, dampingFraction: 0.6), value: on)
            }
        }
        .padding(.horizontal)
    }
}
