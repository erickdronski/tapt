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
        Set(checkins.map { checkin in
            let brewery = normalized(checkin.breweryName)
            let beer = normalized(checkin.beerName)
            if !brewery.isEmpty { return "name:\(brewery)|\(beer)" }
            if let beerId = checkin.beerId { return "id:\(beerId)" }
            return "name:|\(beer)"
        }).count
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

struct Badge: Identifiable {
    let id: String
    let title: String
    let detail: String
    let icon: String
    let metric: BadgeMetric
    let threshold: Int

    func earned(_ s: PassportStats) -> Bool {
        switch metric {
        case .pours: s.pours >= threshold
        case .beers: (s.beers ?? 0) >= threshold
        case .styles: s.styles >= threshold
        case .states: s.states >= threshold
        case .countries: s.countries >= threshold
        }
    }
}

enum PassportData {
    static let badges: [Badge] = [
        .init(id: "first",    title: "First Pour",      detail: "Log your first beer", icon: "drop.fill",             metric: .pours,     threshold: 1),
        .init(id: "flight",   title: "First Flight",    detail: "Try 5 distinct beers", icon: "5.circle.fill",         metric: .beers,     threshold: 5),
        .init(id: "styleexp", title: "Style Explorer",  detail: "5 styles tried",      icon: "square.grid.2x2.fill",  metric: .styles,    threshold: 5),
        .init(id: "taptrail", title: "Tap Trail",       detail: "5 states visited",    icon: "map.fill",              metric: .states,    threshold: 5),
        .init(id: "globe",    title: "Globetrotter",    detail: "Beers from 3 lands",  icon: "globe",                 metric: .countries, threshold: 3),
        .init(id: "worldly",  title: "Citizen of Beer", detail: "5 countries",         icon: "airplane",              metric: .countries, threshold: 5),
        .init(id: "century",  title: "Century Cellar",  detail: "Try 100 distinct beers", icon: "trophy.fill",         metric: .beers,     threshold: 100),
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
