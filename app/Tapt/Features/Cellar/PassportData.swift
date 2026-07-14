import Foundation

struct PassportStats {
    let pours: Int
    let beers: Int?
    let styles: Int
    let states: Int
    let countries: Int
}

enum BadgeMetric { case pours, beers, styles, states, countries }

enum CountryFlag {
    static func symbol(for code: String?) -> String {
        let normalized = code?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased() ?? ""
        guard normalized.count == 2,
              normalized.unicodeScalars.allSatisfy({ (65...90).contains(Int($0.value)) }) else {
            return "🍺"
        }

        var flag = ""
        for scalar in normalized.unicodeScalars {
            guard let regionalIndicator = UnicodeScalar(127_397 + scalar.value) else {
                return "🍺"
            }
            flag += String(regionalIndicator)
        }
        return flag
    }
}

enum PassportProgress {
    static func uniqueBeerCount(in checkins: [MyCheckin]) -> Int {
        Set(checkins.map(collectionKey)).count
    }

    /// Stable identity for one distinct beer (same rule the count uses, so the
    /// collection shelf and the "distinct beers" stat never disagree).
    static func collectionKey(_ checkin: MyCheckin) -> String {
        let brewery = normalized(checkin.breweryName)
        let beer = normalized(checkin.beerName)
        if !brewery.isEmpty { return "name:\(brewery)|\(beer)" }
        if let beerId = checkin.beerId { return "id:\(beerId)" }
        return "name:|\(beer)"
    }

    private static func normalized(_ value: String) -> String {
        value
            .folding(
                options: [.caseInsensitive, .diacriticInsensitive],
                locale: Locale(identifier: "en_US_POSIX")
            )
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .joined()
    }
}

/// Visual tier for a badge sticker. Drives the medal color, not whether it is earned.
enum BadgeTier: Int { case bronze = 0, silver, gold, elite }

struct Badge: Identifiable {
    let id: String
    let title: String
    let detail: String
    let icon: String
    /// A fun sticker emoji, the hero of the die-cut medal.
    let emoji: String
    let tier: BadgeTier
    let metric: BadgeMetric
    let threshold: Int

    func earned(_ s: PassportStats) -> Bool {
        current(s) >= threshold
    }

    /// How far along the user is toward this badge (used for the locked progress ring).
    func current(_ s: PassportStats) -> Int {
        switch metric {
        case .pours: s.pours
        case .beers: s.beers ?? 0
        case .styles: s.styles
        case .states: s.states
        case .countries: s.countries
        }
    }

    func progress(_ s: PassportStats) -> Double {
        min(1, Double(current(s)) / Double(max(threshold, 1)))
    }
}

enum PassportData {
    /// The passport sticker collection: real, earnable milestones across the beer
    /// world. Ordered as a progression so the shelf reads like a journey.
    static let badges: [Badge] = [
        // The collection ladder (distinct beers)
        .init(id: "first",   title: "First Pour",     detail: "Log your first beer",   icon: "drop.fill",              emoji: "🍺", tier: .bronze, metric: .pours,     threshold: 1),
        .init(id: "sampler", title: "Sampler",        detail: "5 distinct beers",      icon: "square.stack.3d.up.fill",emoji: "🍻", tier: .bronze, metric: .beers,     threshold: 5),
        .init(id: "case",    title: "Case Closed",    detail: "24 distinct beers",     icon: "shippingbox.fill",       emoji: "📦", tier: .silver, metric: .beers,     threshold: 24),
        .init(id: "half",    title: "Half Century",   detail: "50 distinct beers",     icon: "50.circle.fill",         emoji: "🎯", tier: .gold,   metric: .beers,     threshold: 50),
        .init(id: "century", title: "Century Cellar", detail: "100 distinct beers",    icon: "trophy.fill",            emoji: "🏆", tier: .elite,  metric: .beers,     threshold: 100),
        // Styles
        .init(id: "curious", title: "Style Curious",  detail: "3 styles tried",        icon: "square.grid.2x2.fill",   emoji: "🧭", tier: .bronze, metric: .styles,    threshold: 3),
        .init(id: "styleexp",title: "Style Explorer", detail: "5 styles tried",        icon: "square.grid.3x3.fill",   emoji: "🗂️", tier: .silver, metric: .styles,    threshold: 5),
        .init(id: "scholar", title: "Style Scholar",  detail: "10 styles tried",       icon: "graduationcap.fill",     emoji: "🎓", tier: .gold,   metric: .styles,    threshold: 10),
        // The world (countries)
        .init(id: "stamped", title: "Passport Stamped",detail: "Beer from 1 country",  icon: "seal.fill",              emoji: "🛂", tier: .bronze, metric: .countries, threshold: 1),
        .init(id: "border",  title: "Border Hopper",  detail: "Beers from 3 lands",    icon: "globe",                  emoji: "🌍", tier: .silver, metric: .countries, threshold: 3),
        .init(id: "worldly", title: "Continental",    detail: "5 countries",           icon: "airplane",               emoji: "✈️", tier: .gold,   metric: .countries, threshold: 5),
        .init(id: "trotter", title: "Globe Trotter",  detail: "10 countries",          icon: "globe.americas.fill",    emoji: "🌐", tier: .elite,  metric: .countries, threshold: 10),
        // The road (US states)
        .init(id: "roadie",  title: "Road Beer",      detail: "Beer in 3 states",      icon: "car.fill",               emoji: "🚗", tier: .bronze, metric: .states,    threshold: 3),
        .init(id: "taptrail",title: "Tap Trail",      detail: "5 states",              icon: "map.fill",               emoji: "🗺️", tier: .silver, metric: .states,    threshold: 5),
        .init(id: "stateline",title: "State Line",    detail: "10 states",             icon: "flag.checkered",         emoji: "🚩", tier: .gold,   metric: .states,    threshold: 10),
    ]

    /// Every country with real beers or venues in the Tapt catalog.
    static let countries: [(name: String, flag: String)] = [
        ("United States", "🇺🇸"), ("Germany", "🇩🇪"), ("Poland", "🇵🇱"), ("Czechia", "🇨🇿"),
        ("Belgium", "🇧🇪"), ("Ireland", "🇮🇪"), ("United Kingdom", "🇬🇧"), ("Mexico", "🇲🇽"),
        ("Japan", "🇯🇵"), ("Canada", "🇨🇦"), ("Spain", "🇪🇸"), ("Netherlands", "🇳🇱"),
        ("Austria", "🇦🇹"), ("Denmark", "🇩🇰"), ("Norway", "🇳🇴"), ("Sweden", "🇸🇪"),
        ("Italy", "🇮🇹"), ("France", "🇫🇷"), ("South Korea", "🇰🇷"), ("Brazil", "🇧🇷"),
        ("Australia", "🇦🇺"), ("New Zealand", "🇳🇿"), ("China", "🇨🇳"), ("Thailand", "🇹🇭"),
        ("Vietnam", "🇻🇳"), ("Singapore", "🇸🇬"), ("Philippines", "🇵🇭"), ("India", "🇮🇳"),
        ("Sri Lanka", "🇱🇰"), ("Taiwan", "🇹🇼"), ("Iceland", "🇮🇸"), ("Finland", "🇫🇮"),
        ("Lithuania", "🇱🇹"), ("Ukraine", "🇺🇦"), ("Estonia", "🇪🇪"), ("Russia", "🇷🇺"),
        ("Switzerland", "🇨🇭"), ("Greece", "🇬🇷"), ("Turkey", "🇹🇷"), ("Argentina", "🇦🇷"),
        ("Peru", "🇵🇪"), ("Jamaica", "🇯🇲"), ("South Africa", "🇿🇦"), ("Namibia", "🇳🇦"),
        ("Kenya", "🇰🇪"), ("Nigeria", "🇳🇬"), ("Portugal", "🇵🇹"),
    ]
}
