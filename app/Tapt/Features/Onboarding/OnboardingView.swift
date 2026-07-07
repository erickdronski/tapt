import SwiftUI
import Supabase

/// First-run onboarding: welcome, taste preferences, home region. Springy, brand-forward,
/// and it seeds the taste profile (region_code + taste_vector.top_styles).
struct OnboardingView: View {
    @Environment(Session.self) private var session
    @AppStorage("onboarded") private var onboarded = false
    @AppStorage("favoriteStyles") private var favoriteStyles = ""
    @AppStorage("homeRegion") private var homeRegion = "New Jersey"
    @AppStorage("noLowDefault") private var noLowDefault = false

    @State private var step = 0
    @State private var styles: Set<String> = []
    @State private var region = "New Jersey"

    private let allStyles = ["IPA", "Hazy IPA", "Pilsner", "Lager", "Stout", "Porter",
                             "Sour", "Belgian", "Wheat", "Pale Ale", "No / Low"]
    private let total = 4

    var body: some View {
        ZStack {
            Brand.background.ignoresSafeArea()
            VStack(spacing: 20) {
                progress
                TabView(selection: $step) {
                    welcome.tag(0)
                    stylesStep.tag(1)
                    regionStep.tag(2)
                    finishStep.tag(3)
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
            PourGlass()
            Text("Welcome to Tapt")
                .font(.system(size: 34, weight: .heavy, design: .rounded)).foregroundStyle(Brand.text)
            Text("The whole beer world, in your pocket. Scan it, score it, and see what the planet is drinking.")
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

    private var regionStep: some View {
        VStack(spacing: 18) {
            stepTitle("Where is home base?", "So we can show what is hot in your area.")
            ScrollView {
                VStack(spacing: 10) {
                    ForEach(BeerRegions.all.filter { $0 != "Global" }, id: \.self) { r in
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
            PourGlass()
            Text("You are all set\(firstName)")
                .font(.system(size: 30, weight: .heavy, design: .rounded)).foregroundStyle(Brand.text).multilineTextAlignment(.center)
            Text("\(styles.count) styles picked, home base \(region). Time to fill your Cellar.")
                .font(.body).foregroundStyle(Brand.muted).multilineTextAlignment(.center).padding(.horizontal, 24)
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
        favoriteStyles = styles.sorted().joined(separator: ",")
        homeRegion = region
        noLowDefault = styles.contains("No / Low")
        if let uid = session.user?.id {
            let picked = Array(styles)
            Task {
                await ProfileService.setRegion(region, userId: uid)
                await ProfileService.setTopStyles(picked, userId: uid)
            }
        }
        withAnimation(.spring) { onboarded = true }
    }
}

/// Animated filling pint used on the welcome + finish steps.
private struct PourGlass: View {
    @State private var fill: CGFloat = 0

    var body: some View {
        RoundedRectangle(cornerRadius: 18)
            .fill(Brand.surface)
            .frame(width: 120, height: 168)
            .overlay(
                GeometryReader { geo in
                    VStack(spacing: 0) {
                        Rectangle().fill(Brand.foam).frame(height: 12)
                        Rectangle().fill(Brand.gold)
                    }
                    .frame(height: geo.size.height * fill)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                }
                .clipShape(RoundedRectangle(cornerRadius: 18))
            )
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(Brand.malt, lineWidth: 4))
            .onAppear {
                fill = 0
                withAnimation(.spring(response: 1.1, dampingFraction: 0.72).delay(0.15)) { fill = 0.82 }
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
