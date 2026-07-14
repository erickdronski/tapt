import Foundation

/// The passport's earned metrics. All reward VARIETY, DISCOVERY, and KNOWLEDGE of
/// the beer world - never volume of drinking. `pours` is only used for the very
/// first stamp; everything else counts distinct beers, styles, places, and
/// exploration. No / Low badges reward responsible choices on purpose.
struct PassportStats {
    let pours: Int
    let beers: Int?
    let styles: Int
    let states: Int
    let countries: Int
    // Exploration dimensions (default 0 so existing call sites still compile).
    var breweries: Int = 0
    var styleFamilies: Int = 0
    var continents: Int = 0
    var seasons: Int = 0
    var noLow: Int = 0
    // Style-discovery flags (count of DISTINCT beers of that family you have logged).
    var hoppy: Int = 0
    var dark: Int = 0
    var wheat: Int = 0
    var sour: Int = 0
    var belgian: Int = 0
    var crisp: Int = 0

    /// Build the full stat set from a user's check-ins (own passport). Mirrors the
    /// server aggregation in public_profile() so the shareable card agrees.
    static func from(checkins: [MyCheckin], beers: Int, styles: Int, states: Int, countries: Int) -> PassportStats {
        var brewery = Set<String>(), continent = Set<String>(), season = Set<String>(), family = Set<String>()
        var noLow = Set<String>(), hoppy = Set<String>(), dark = Set<String>(), wheat = Set<String>()
        var sour = Set<String>(), belgian = Set<String>(), crisp = Set<String>()
        for c in checkins {
            let key = PassportProgress.collectionKey(c)
            if let br = c.beer?.brewery?.name, !br.isEmpty { brewery.insert(br.lowercased()) }
            if let ct = c.beer?.brewery?.country, let cont = PassportTaxonomy.continent(for: ct) { continent.insert(cont) }
            if let s = PassportTaxonomy.season(fromISO: c.eventTs) { season.insert(s) }
            let style = (c.beer?.styleRef ?? c.style ?? "").lowercased()
            let name = (c.beer?.name ?? "").lowercased()
            if let fam = PassportTaxonomy.family(style) { family.insert(fam) }
            if style.contains("non-alco") || style.contains("alcohol-free") || style.contains("0.0")
                || name.contains("non-alco") || name.contains("0.0") { noLow.insert(key) }
            if style.contains("ipa") || style.contains("pale ale") || style.contains("hazy") { hoppy.insert(key) }
            if style.contains("stout") || style.contains("porter") || style.contains("schwarz") || style.contains("dunkel") { dark.insert(key) }
            if style.contains("wheat") || style.contains("wit") || style.contains("hefe") || style.contains("weizen") || style.contains("weiss") { wheat.insert(key) }
            if style.contains("sour") || style.contains("lambic") || style.contains("gose") || style.contains("berliner") || style.contains("kriek") { sour.insert(key) }
            if style.contains("saison") || style.contains("dubbel") || style.contains("tripel") || style.contains("quad") || style.contains("abbey") || style.contains("belgian") { belgian.insert(key) }
            if style.contains("pils") || style.contains("lager") || style.contains("helles") || style.contains("kolsch") || style.contains("k\u{00f6}lsch") { crisp.insert(key) }
        }
        return PassportStats(
            pours: checkins.count, beers: beers, styles: styles, states: states, countries: countries,
            breweries: brewery.count, styleFamilies: family.count, continents: continent.count,
            seasons: season.count, noLow: noLow.count, hoppy: hoppy.count, dark: dark.count,
            wheat: wheat.count, sour: sour.count, belgian: belgian.count, crisp: crisp.count)
    }
}

/// Shared mappings so the client and the server keep the same taxonomy.
enum PassportTaxonomy {
    static func season(fromISO iso: String) -> String? {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let date = f.date(from: iso) ?? ISO8601DateFormatter().date(from: iso)
        guard let date else { return nil }
        let m = Calendar(identifier: .gregorian).component(.month, from: date)
        switch m {
        case 12, 1, 2: return "winter"
        case 3, 4, 5:  return "spring"
        case 6, 7, 8:  return "summer"
        default:       return "fall"
        }
    }

    static func family(_ style: String) -> String? {
        if style.isEmpty { return nil }
        if style.contains("ipa") || style.contains("pale ale") || style.contains("hazy") { return "hoppy" }
        if style.contains("stout") || style.contains("porter") || style.contains("schwarz") || style.contains("dunkel") { return "dark" }
        if style.contains("wheat") || style.contains("wit") || style.contains("hefe") || style.contains("weizen") || style.contains("weiss") { return "wheat" }
        if style.contains("sour") || style.contains("lambic") || style.contains("gose") || style.contains("berliner") || style.contains("kriek") { return "sour" }
        if style.contains("saison") || style.contains("dubbel") || style.contains("tripel") || style.contains("quad") || style.contains("abbey") || style.contains("belgian") { return "belgian" }
        if style.contains("pils") || style.contains("lager") || style.contains("helles") || style.contains("kolsch") || style.contains("k\u{00f6}lsch") { return "crisp" }
        if style.contains("bock") || style.contains("m\u{00e4}rzen") || style.contains("marzen") || style.contains("amber") || style.contains("brown") { return "malty" }
        return "other"
    }

    /// Continent for a country name (covers Tapt's real beer countries).
    static func continent(for country: String) -> String? {
        let c = country.lowercased()
        let europe = ["germany","poland","czech","belgium","ireland","united kingdom","england","scotland","spain","netherlands","austria","denmark","norway","sweden","italy","france","iceland","finland","lithuania","ukraine","estonia","russia","switzerland","greece","portugal","hungary","romania","croatia","slovenia","slovakia","serbia","latvia","belarus","luxembourg"]
        let asia = ["japan","south korea","korea","china","thailand","vietnam","singapore","philippines","india","sri lanka","taiwan","turkey","indonesia","malaysia","cambodia","laos","nepal","israel"]
        let namer = ["united states","usa","canada","mexico"]
        let samer = ["brazil","argentina","peru","chile","colombia","uruguay","ecuador","bolivia","venezuela"]
        let africa = ["south africa","namibia","kenya","nigeria","ethiopia","egypt","morocco","tanzania","ghana","uganda"]
        let oceania = ["australia","new zealand","fiji"]
        if namer.contains(where: c.contains) { return "NA" }
        if europe.contains(where: c.contains) { return "EU" }
        if asia.contains(where: c.contains) { return "AS" }
        if samer.contains(where: c.contains) { return "SA" }
        if africa.contains(where: c.contains) { return "AF" }
        if oceania.contains(where: c.contains) { return "OC" }
        if c.contains("jamaica") || c.contains("cuba") || c.contains("bahamas") { return "NA" }
        return nil
    }
}

enum BadgeMetric {
    case pours, beers, styles, states, countries
    case breweries, styleFamilies, continents, seasons, noLow
    case hoppy, dark, wheat, sour, belgian, crisp
}

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

    func earned(_ s: PassportStats) -> Bool { current(s) >= threshold }

    /// How far along the user is toward this badge (used for the locked progress ring).
    func current(_ s: PassportStats) -> Int {
        switch metric {
        case .pours: s.pours
        case .beers: s.beers ?? 0
        case .styles: s.styles
        case .states: s.states
        case .countries: s.countries
        case .breweries: s.breweries
        case .styleFamilies: s.styleFamilies
        case .continents: s.continents
        case .seasons: s.seasons
        case .noLow: s.noLow
        case .hoppy: s.hoppy
        case .dark: s.dark
        case .wheat: s.wheat
        case .sour: s.sour
        case .belgian: s.belgian
        case .crisp: s.crisp
        }
    }

    func progress(_ s: PassportStats) -> Double {
        min(1, Double(current(s)) / Double(max(threshold, 1)))
    }
}

enum PassportData {
    /// The passport sticker collection: real, earnable milestones across the beer
    /// world. Every badge rewards exploration - distinct beers, styles, places,
    /// seasons, and smart choices - never how much you drink.
    static let badges: [Badge] = [
        // --- Collection ladder (DISTINCT beers = breadth of palate, not volume) ---
        .init(id: "first",   title: "First Pour",       detail: "Log your first beer",          icon: "drop.fill",               emoji: "🍺", tier: .bronze, metric: .pours,   threshold: 1),
        .init(id: "sampler", title: "Sampler",          detail: "5 distinct beers explored",    icon: "square.stack.3d.up.fill", emoji: "🍻", tier: .bronze, metric: .beers,   threshold: 5),
        .init(id: "explorer",title: "Explorer",         detail: "15 distinct beers explored",   icon: "binoculars.fill",         emoji: "🧭", tier: .silver, metric: .beers,   threshold: 15),
        .init(id: "conn",    title: "Connoisseur",      detail: "30 distinct beers explored",   icon: "hands.sparkles.fill",     emoji: "🎩", tier: .silver, metric: .beers,   threshold: 30),
        .init(id: "somm",    title: "Beer Sommelier",   detail: "60 distinct beers explored",   icon: "graduationcap.fill",      emoji: "🎓", tier: .gold,   metric: .beers,   threshold: 60),
        .init(id: "legend",  title: "Palate of Legend", detail: "120 distinct beers explored",  icon: "crown.fill",              emoji: "👑", tier: .elite,  metric: .beers,   threshold: 120),
        // --- Styles ---
        .init(id: "curious", title: "Style Curious",    detail: "3 styles tried",               icon: "square.grid.2x2.fill",    emoji: "🔎", tier: .bronze, metric: .styles,  threshold: 3),
        .init(id: "styleexp",title: "Style Explorer",   detail: "6 styles tried",               icon: "square.grid.3x3.fill",    emoji: "🗂️", tier: .silver, metric: .styles,  threshold: 6),
        .init(id: "scholar", title: "Style Scholar",    detail: "12 styles tried",              icon: "book.fill",               emoji: "📚", tier: .gold,   metric: .styles,  threshold: 12),
        .init(id: "stylemaster",title: "Style Master",  detail: "20 styles tried",              icon: "star.circle.fill",        emoji: "🌟", tier: .elite,  metric: .styles,  threshold: 20),
        // --- Style families (fun discovery easter eggs, one distinct beer each) ---
        .init(id: "hophead",  title: "Hop Head",        detail: "Explore an IPA or pale",       icon: "leaf.fill",               emoji: "🌿", tier: .bronze, metric: .hoppy,   threshold: 1),
        .init(id: "dark",     title: "Into the Dark",   detail: "Explore a stout or porter",    icon: "moon.stars.fill",         emoji: "🖤", tier: .bronze, metric: .dark,    threshold: 1),
        .init(id: "wheat",    title: "Wheat Fields",    detail: "Explore a wheat beer",         icon: "leaf.circle.fill",        emoji: "🌾", tier: .bronze, metric: .wheat,   threshold: 1),
        .init(id: "sour",     title: "Pucker Up",       detail: "Explore a sour",               icon: "face.dashed.fill",        emoji: "😮", tier: .bronze, metric: .sour,    threshold: 1),
        .init(id: "abbey",    title: "Abbey Road",      detail: "Explore a Belgian style",      icon: "building.columns.fill",   emoji: "⛪", tier: .bronze, metric: .belgian, threshold: 1),
        .init(id: "crisp",    title: "Crisp One",       detail: "Explore a lager or pils",      icon: "snowflake",               emoji: "❄️", tier: .bronze, metric: .crisp,   threshold: 1),
        .init(id: "spectrum", title: "Full Spectrum",   detail: "6 style families explored",    icon: "rainbow",                 emoji: "🌈", tier: .gold,   metric: .styleFamilies, threshold: 6),
        // --- No / Low (rewards responsible choices) ---
        .init(id: "clearhead",title: "Clear Head",      detail: "Enjoy a great No / Low beer",  icon: "brain.head.profile",      emoji: "🧠", tier: .silver, metric: .noLow,   threshold: 1),
        .init(id: "zerohero", title: "Zero Hero",       detail: "5 No / Low beers explored",    icon: "figure.walk.circle.fill", emoji: "🦸", tier: .gold,   metric: .noLow,   threshold: 5),
        // --- The world (countries) ---
        .init(id: "stamped", title: "Passport Stamped", detail: "Beer from 1 country",          icon: "seal.fill",               emoji: "🛂", tier: .bronze, metric: .countries, threshold: 1),
        .init(id: "border",  title: "Border Hopper",    detail: "Beers from 3 countries",       icon: "globe",                   emoji: "🌍", tier: .silver, metric: .countries, threshold: 3),
        .init(id: "worldly", title: "Continental",      detail: "5 countries",                  icon: "airplane",                emoji: "✈️", tier: .gold,   metric: .countries, threshold: 5),
        .init(id: "trotter", title: "Globe Trotter",    detail: "10 countries",                 icon: "globe.americas.fill",     emoji: "🌐", tier: .elite,  metric: .countries, threshold: 10),
        .init(id: "worldcls",title: "World Class",      detail: "20 countries",                 icon: "trophy.fill",             emoji: "🏆", tier: .elite,  metric: .countries, threshold: 20),
        // --- Continents (global reach) ---
        .init(id: "twocont", title: "Two Worlds",       detail: "Beers from 2 continents",      icon: "map.fill",                emoji: "🗺️", tier: .silver, metric: .continents, threshold: 2),
        .init(id: "fourcont",title: "Four Corners",     detail: "Beers from 4 continents",      icon: "globe.asia.australia.fill", emoji: "🌏", tier: .gold,  metric: .continents, threshold: 4),
        .init(id: "planet",  title: "Beer Planet",      detail: "Beers from 6 continents",      icon: "globe.central.south.asia.fill", emoji: "🪐", tier: .elite, metric: .continents, threshold: 6),
        // --- Breweries ---
        .init(id: "brewhop", title: "Brewery Hopper",   detail: "5 breweries explored",         icon: "building.2.fill",         emoji: "🏭", tier: .bronze, metric: .breweries, threshold: 5),
        .init(id: "regular", title: "The Regular",      detail: "15 breweries explored",        icon: "mug.fill",                emoji: "🍺", tier: .silver, metric: .breweries, threshold: 15),
        .init(id: "brewhound",title: "Brewhound",       detail: "40 breweries explored",        icon: "pawprint.fill",           emoji: "🐕", tier: .gold,   metric: .breweries, threshold: 40),
        // --- Seasons (across the year) ---
        .init(id: "twoseason",title: "Turning Leaves",  detail: "Log across 2 seasons",         icon: "leaf.arrow.circlepath",   emoji: "🍂", tier: .bronze, metric: .seasons, threshold: 2),
        .init(id: "fourseason",title: "Four Seasons",   detail: "Log across all 4 seasons",     icon: "calendar",                emoji: "🗓️", tier: .gold,   metric: .seasons, threshold: 4),
        // --- The road (US states) ---
        .init(id: "roadie",  title: "Road Beer",        detail: "Beer in 3 states",             icon: "car.fill",                emoji: "🚗", tier: .bronze, metric: .states,  threshold: 3),
        .init(id: "taptrail",title: "Tap Trail",        detail: "5 states",                     icon: "map.fill",                emoji: "🛣️", tier: .silver, metric: .states,  threshold: 5),
        .init(id: "stateline",title: "State Line",      detail: "10 states",                    icon: "flag.checkered",          emoji: "🚩", tier: .gold,   metric: .states,  threshold: 10),
        .init(id: "coast2coast",title: "Coast to Coast",detail: "25 states",                    icon: "flag.2.crossed.fill",     emoji: "🇺🇸", tier: .elite,  metric: .states,  threshold: 25),
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
