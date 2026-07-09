import Foundation

struct PassportStats {
    let pours: Int
    let styles: Int
    let states: Int
    let countries: Int
}

enum BadgeMetric { case pours, styles, states, countries }

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
        case .styles: s.styles >= threshold
        case .states: s.states >= threshold
        case .countries: s.countries >= threshold
        }
    }
}

enum PassportData {
    static let badges: [Badge] = [
        .init(id: "first",    title: "First Pour",      detail: "Log your first beer", icon: "drop.fill",             metric: .pours,     threshold: 1),
        .init(id: "thirsty",  title: "Getting Thirsty", detail: "5 pours logged",      icon: "5.circle.fill",         metric: .pours,     threshold: 5),
        .init(id: "styleexp", title: "Style Explorer",  detail: "5 styles tried",      icon: "square.grid.2x2.fill",  metric: .styles,    threshold: 5),
        .init(id: "taptrail", title: "Tap Trail",       detail: "5 states visited",    icon: "map.fill",              metric: .states,    threshold: 5),
        .init(id: "globe",    title: "Globetrotter",    detail: "Beers from 3 lands",  icon: "globe",                 metric: .countries, threshold: 3),
        .init(id: "worldly",  title: "Citizen of Beer", detail: "5 countries",         icon: "airplane",              metric: .countries, threshold: 5),
        .init(id: "century",  title: "Centurion",       detail: "100 pours",           icon: "trophy.fill",           metric: .pours,     threshold: 100),
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
