import SwiftUI

// Partner surfaces: a featured rail (real, curated partners only, when none
// exist yet it shows an honest "your spot here" card) and an inquiry form so
// breweries, bars, pubs, and taprooms can raise their hand.

/// Horizontal rail of featured partners for Explore / Discover.
struct FeaturedPartnersRail: View {
    @State private var partners: [FeaturedPartner] = []
    @State private var loaded = false
    @State private var loadError: String?
    @State private var impressedPartnerIDs: Set<String> = []
    @AppStorage("homeRegion") private var homeRegion = "Global"

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Featured beer spots")
                        .font(.system(.title3, design: .rounded).weight(.bold))
                        .foregroundStyle(Brand.text)
                    Text(partners.isEmpty ? "Breweries & bars pour with Tapt" : "Partners pouring with Tapt")
                        .font(.caption).foregroundStyle(Brand.muted)
                }
                Spacer()
            }
            .padding(.horizontal)

            if !loaded {
                TaptSkeletonList(rows: 1)
                    .frame(height: 168)
                    .padding(.horizontal)
            } else if let loadError {
                HStack(spacing: 12) {
                    Image(systemName: "wifi.exclamationmark").foregroundStyle(Brand.copper)
                    Text(loadError).font(.caption).foregroundStyle(Brand.muted)
                    Spacer(minLength: 0)
                    Button("Retry") { Task { await load() } }
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Brand.malt)
                }
                .padding(14)
                .background(Brand.surface, in: RoundedRectangle(cornerRadius: 14))
                .padding(.horizontal)
            } else if partners.isEmpty {
                // No partners yet (pre-launch) -- show one intentional, full-width
                // invite instead of a lone placeholder card floating in a scroll.
                NavigationLink { PartnerInquiryView() } label: { emptyInvite }
                    .buttonStyle(.plain)
                    .padding(.horizontal)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(partners) { partner in
                            partnerCard(partner)
                        }
                        NavigationLink { PartnerInquiryView() } label: {
                            inviteCard
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal)
                }
            }
        }
        .task {
            guard !loaded else { return }
            await load()
        }
    }

    private func partnerCard(_ partner: FeaturedPartner) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: partner.kind == "event" ? "calendar.badge.clock" : "mug.fill")
                    .foregroundStyle(Brand.malt)
                    .frame(width: 38, height: 38)
                    .background(Brand.gold, in: RoundedRectangle(cornerRadius: 10))
                Spacer()
                Text(partner.tier == "spotlight" ? "SPOTLIGHT" : "PARTNER")
                    .font(.system(.caption2, design: .rounded).weight(.heavy))
                    .foregroundStyle(Brand.malt)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(partner.tier == "spotlight" ? Brand.copper : Brand.gold, in: Capsule())
            }
            Text(partner.title)
                .font(.system(.headline, design: .rounded).weight(.bold))
                .foregroundStyle(Brand.text)
                .lineLimit(1)
            if !partner.placeLine.isEmpty {
                Text(partner.placeLine)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Brand.copper)
                    .lineLimit(1)
            }
            if let blurb = partner.blurb, !blurb.isEmpty {
                Text(blurb).font(.caption).foregroundStyle(Brand.muted).lineLimit(2)
            }
            Spacer(minLength: 0)
            if let cta = partner.ctaUrl, let url = URL(string: cta) {
                Link(destination: url) {
                    Text(partner.ctaLabel ?? "Learn more")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Brand.malt)
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(Brand.gold, in: Capsule())
                }
                .simultaneousGesture(TapGesture().onEnded {
                    let region = homeRegion.isEmpty ? nil : homeRegion
                    Task { await PartnerService.logFeatured(id: partner.id, event: "tap", region: region) }
                })
            }
        }
        .padding(14)
        .frame(width: 220, height: 168, alignment: .topLeading)
        .background(Brand.surface, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Brand.gold.opacity(0.3)))
        .onAppear { recordImpression(partner) }
    }

    @MainActor
    private func load() async {
        loaded = false
        loadError = nil
        let region = homeRegion.isEmpty ? nil : homeRegion
        do {
            partners = try await PartnerService.featured(region: region)
            loadError = nil
        } catch {
            partners = []
            loadError = "Featured spots could not be loaded."
        }
        loaded = true
    }

    private func recordImpression(_ partner: FeaturedPartner) {
        guard impressedPartnerIDs.insert(partner.id).inserted else { return }
        let region = homeRegion.isEmpty ? nil : homeRegion
        Task { await PartnerService.logFeatured(id: partner.id, event: "impression", region: region) }
    }

    private var inviteCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: "storefront.fill")
                .foregroundStyle(Brand.malt)
                .frame(width: 38, height: 38)
                .background(Brand.hop, in: RoundedRectangle(cornerRadius: 10))
            Text("Your spot here")
                .font(.system(.headline, design: .rounded).weight(.bold))
                .foregroundStyle(Brand.text)
            Text("Run a brewery, bar, pub, or taproom? Get featured to beer fans nearby.")
                .font(.caption).foregroundStyle(Brand.muted)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Text("Partner with Tapt")
                .font(.caption.weight(.bold))
                .foregroundStyle(Brand.malt)
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(Brand.hop, in: Capsule())
        }
        .padding(14)
        .frame(width: 220, height: 168, alignment: .topLeading)
        .background(Brand.surface, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Brand.hop.opacity(0.35), style: StrokeStyle(lineWidth: 1.4, dash: [6, 4])))
    }

    /// Full-width, designed invite shown when no venue has been featured yet, so the
    /// section reads as intentional rather than an empty placeholder rail.
    private var emptyInvite: some View {
        HStack(spacing: 14) {
            Image(systemName: "storefront.fill")
                .font(.title2).foregroundStyle(Brand.malt)
                .frame(width: 52, height: 52)
                .background(Brand.hop, in: RoundedRectangle(cornerRadius: 14))
            VStack(alignment: .leading, spacing: 3) {
                Text("Feature your beer spot")
                    .font(.system(.headline, design: .rounded).weight(.bold))
                    .foregroundStyle(Brand.text)
                Text("Brewery, bar, pub, or taproom? Get in front of nearby beer fans. Free to start.")
                    .font(.caption).foregroundStyle(Brand.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.footnote.weight(.bold)).foregroundStyle(Brand.hop)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Brand.surface, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18)
            .stroke(Brand.hop.opacity(0.4), style: StrokeStyle(lineWidth: 1.4, dash: [7, 5])))
    }
}

/// Inquiry form for venues that want to be featured.
struct PartnerInquiryView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var businessName = ""
    @State private var kind = "brewery"
    @State private var email = ""
    @State private var city = ""
    @State private var region = ""
    @State private var country = ""
    @State private var message = ""
    @State private var sending = false
    @State private var sent = false
    @State private var errorText: String?

    private let kinds = ["brewery", "bar", "pub", "taproom", "beer_garden", "bottle_shop", "festival", "distributor", "other"]

    private var canSend: Bool {
        businessName.trimmingCharacters(in: .whitespaces).count >= 2 && email.contains("@")
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                TaptHeroPanel(
                    title: "Partner with Tapt",
                    subtitle: "Free profile. Featured placement puts your taps and events in front of nearby drinkers.",
                    metric: "🤝",
                    caption: "Local businesses fund reach, drinkers never pay",
                    icon: "storefront.fill",
                    tint: Brand.hop
                )

                if sent {
                    VStack(spacing: 12) {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 44)).foregroundStyle(Brand.hop)
                        Text("Inquiry received")
                            .font(.system(.title2, design: .rounded).weight(.heavy))
                            .foregroundStyle(Brand.text)
                        Text("We read every one. You'll hear from Tapt at \(email).")
                            .font(.subheadline).foregroundStyle(Brand.muted)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 30)
                } else {
                    field("Business name", text: $businessName, prompt: "e.g. Iron City Taproom")

                    VStack(alignment: .leading, spacing: 8) {
                        Text("What kind of spot?").font(.system(.headline, design: .rounded)).foregroundStyle(Brand.text)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(kinds, id: \.self) { k in
                                    Button { kind = k } label: {
                                        Text(k.replacingOccurrences(of: "_", with: " ").capitalized)
                                            .font(.caption.weight(.semibold))
                                            .padding(.horizontal, 12).padding(.vertical, 8)
                                            .background(kind == k ? Brand.gold : Brand.surface, in: Capsule())
                                            .foregroundStyle(kind == k ? Brand.malt : Brand.text)
                                            .overlay(Capsule().stroke(Brand.malt.opacity(0.12)))
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }

                    field("Contact email", text: $email, prompt: "you@yourbrewery.com", keyboard: .emailAddress)
                    HStack(spacing: 10) {
                        field("City", text: $city, prompt: "City")
                        field("State / region", text: $region, prompt: "Region")
                    }
                    field("Country", text: $country, prompt: "Country")

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Anything else?").font(.system(.headline, design: .rounded)).foregroundStyle(Brand.text)
                        TextField("Tap count, events, what you'd love from Tapt...", text: $message, axis: .vertical)
                            .lineLimit(3...6)
                            .padding(12)
                            .background(Brand.surface, in: RoundedRectangle(cornerRadius: 13))
                            .overlay(RoundedRectangle(cornerRadius: 13).stroke(Brand.malt.opacity(0.1)))
                    }

                    if let errorText {
                        Text(errorText).font(.footnote).foregroundStyle(.red)
                    }

                    Button {
                        submit()
                    } label: {
                        Text(sending ? "Sending..." : "Send inquiry")
                            .font(.system(.headline, design: .rounded))
                            .frame(maxWidth: .infinity).padding(.vertical, 15)
                            .background(Brand.gold, in: RoundedRectangle(cornerRadius: 14))
                            .foregroundStyle(Brand.malt)
                    }
                    .buttonStyle(.plain)
                    .disabled(!canSend || sending)
                    .opacity(canSend && !sending ? 1 : 0.5)
                }
            }
            .padding()
        }
        .background(Brand.background)
        .navigationTitle("Partner with Tapt")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func field(_ title: String, text: Binding<String>, prompt: String, keyboard: UIKeyboardType = .default) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.system(.headline, design: .rounded)).foregroundStyle(Brand.text)
            TextField(prompt, text: text)
                .keyboardType(keyboard)
                .textInputAutocapitalization(keyboard == .emailAddress ? .never : .words)
                .autocorrectionDisabled(keyboard == .emailAddress)
                .padding(12)
                .background(Brand.surface, in: RoundedRectangle(cornerRadius: 13))
                .overlay(RoundedRectangle(cornerRadius: 13).stroke(Brand.malt.opacity(0.1)))
        }
    }

    private func submit() {
        sending = true
        errorText = nil
        Task {
            do {
                try await PartnerService.submitInquiry(
                    businessName: businessName.trimmingCharacters(in: .whitespaces),
                    kind: kind,
                    email: email.trimmingCharacters(in: .whitespaces),
                    city: city.isEmpty ? nil : city,
                    region: region.isEmpty ? nil : region,
                    country: country.isEmpty ? nil : country,
                    message: message.isEmpty ? nil : message
                )
                sent = true
                // Confirm receipt to the submitter and point them at the portal.
                // Fire and forget: a delivery miss must not undo a filed inquiry.
                Task { await PartnerService.sendInquiryAck() }
            } catch {
                errorText = "Could not send that yet. Check the fields and try again."
            }
            sending = false
        }
    }
}
