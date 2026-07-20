import Foundation

/// Decides whether an Open Food Facts product is beer, using OFF's
/// language-independent category taxonomy instead of English substrings.
///
/// OFF returns `categories_tags` as a fully expanded hierarchy of `lang:slug`
/// ids. Categories that exist in the OFF taxonomy are normalised to their
/// canonical English id in every language (a French lager still carries
/// `en:beers`), while contributor categories that are not in the taxonomy keep
/// the entry language: `pl:piwa`, `de:helles-vollbier`, `it:birra-artigianale`,
/// `cs:pivo-svetly-lezak`. Looking for the English word "beer" therefore drops
/// real foreign beers, and accepting any tag that contains "beer" would let
/// root beer, ginger beer, beer bread, beer cheese and beer batter in.
///
/// The rules, in order:
///  1. Hard exclusions (soda and food named after beer) reject outright.
///  2. A canonical English taxonomy id ending in `beer`/`beers` accepts. This
///     covers every product whose category OFF recognises, in any language,
///     including `en:non-alcoholic-beers`.
///  3. An untranslated `lang:slug` tag whose first word is the word for beer in
///     that language accepts only when OFF also reports an alcohol signal
///     (`en:alcoholic-beverages`, an alcohol-free-beer id, or a positive
///     `alcohol_100g`). Without corroboration we stay blank rather than guess.
enum OFFBeerTaxonomy {

    // MARK: Hard exclusions

    /// Slug fragments that name a soda or a food, never a beer. Matched against
    /// the folded slug of every tag regardless of language.
    private static let excludedFragments: [String] = [
        "root-beer", "rootbeer", "ginger-beer", "gingerbeer",
        "birch-beer", "spruce-beer", "sarsaparilla",
        "beer-bread", "beer-cheese", "beer-batter",
        // Same products, contributor languages that OFF has not normalised.
        "wurzelbier", "ingwerbier", "gemberbier", "racinette",
        "biere-de-racine", "cerveza-de-raiz", "birra-di-radice",
    ]

    // MARK: Positive signals

    /// Canonical beer ids whose last word is not "beer"/"beers".
    private static let beerIDs: Set<String> = [
        "en:beers-and-ciders", "en:ales", "en:lagers", "en:stouts",
        "en:porters", "en:pilsners", "en:india-pale-ales", "en:pale-ales",
        "en:witbier", "en:weissbier", "en:shandy",
    ]

    /// First word of an untranslated tag, one language each, diacritics folded.
    private static let beerWords: Set<String> = [
        "bier", "biere", "bieres", "biers", "bieren",          // de, fr, nl
        "birra", "birre",                                       // it
        "cerveza", "cervezas", "cervesa", "cerveses",           // es, ca
        "cerveja", "cervejas",                                  // pt
        "piwo", "piwa",                                         // pl
        "pivo", "piva",                                         // cs, sk, sl, hr, sr
        "ol", "øl", "olut", "oluet", "olutta", "bjor",          // sv/da/no, fi, is
        "sor", "sorok",                                         // hu
        "bere", "beri",                                         // ro
        "bira", "biralar",                                      // tr
        "alus", "olu",                                          // lv/lt, et
        "bir",                                                  // id, ms
        "garagardo", "garagardoa",                              // eu
        "пиво", "пива", "бира",                                 // ru, uk, bg
        "μπιρα", "μπιρες",                                      // el (folded)
        "ビール", "啤酒", "맥주",                                  // ja, zh, ko
    ]

    /// Ids that prove the product sits in OFF's alcoholic-beverage hierarchy.
    private static let alcoholicIDs: Set<String> = [
        "en:alcoholic-beverages", "en:alcoholic-drinks", "en:beers-and-ciders",
    ]

    /// Alcohol-free beer is still beer, and carries no alcohol nutriment.
    private static let alcoholFreeBeerIDs: Set<String> = [
        "en:non-alcoholic-beers", "en:non-alcoholic-beer",
        "en:alcohol-free-beers", "en:low-alcohol-beers",
        "en:beers-without-alcohol",
    ]

    /// Words that turn a beer word into something that is not beer: root, ginger,
    /// birch, spruce, bread, cheese. Only consulted on the untranslated path,
    /// where the tag has not been normalised to a canonical id we can trust.
    /// Keeps `es:cerveza-de-jengibre` and `de:bier-brot` out even when the
    /// product reports alcohol.
    private static let nonBeerModifiers: Set<String> = [
        "racine", "racines", "racinette", "raiz", "radice", "wurzel", "wortel",
        "jengibre", "gengibre", "gingembre", "ingwer", "zenzero", "gember",
        "bouleau", "birke", "abedul", "betulla", "epinette", "fichte",
        "brot", "brood", "pane", "chleb", "kase", "queso", "formaggio", "kaas",
    ]

    private struct Tag {
        let id: String        // "en:beers"
        let language: String  // "en"
        let slug: String      // "beers"
        let words: [String]   // ["beers"]
    }

    /// Lowercases, folds diacritics, and normalises separators so that
    /// `fr:Bières-Blondes`, `fr:bieres_blondes` and `fr:bieres blondes`
    /// compare equal.
    private static func parse(_ raw: String) -> Tag? {
        let folded = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.diacriticInsensitive, .caseInsensitive],
                     locale: Locale(identifier: "en_US_POSIX"))
        guard !folded.isEmpty else { return nil }

        let language: String
        let slugSource: String
        if let colon = folded.firstIndex(of: ":") {
            language = String(folded[folded.startIndex..<colon])
            slugSource = String(folded[folded.index(after: colon)...])
        } else {
            language = "en"  // API v2 always prefixes; bare values are English.
            slugSource = folded
        }

        let slug = slugSource
            .replacingOccurrences(of: "_", with: "-")
            .replacingOccurrences(of: " ", with: "-")
        guard !slug.isEmpty else { return nil }
        let words = slug.split(separator: "-").map(String.init)
        return Tag(id: "\(language):\(slug)", language: language, slug: slug, words: words)
    }

    /// - Parameters:
    ///   - categoryTags: OFF `categories_tags`, the expanded `lang:slug` hierarchy.
    ///   - alcoholByVolume: OFF `nutriments.alcohol_100g`, when present.
    static func isBeer(categoryTags: [String], alcoholByVolume: Double? = nil) -> Bool {
        let tags = categoryTags.compactMap(parse)
        guard !tags.isEmpty else { return false }

        // 1. Root beer, ginger beer, beer bread and friends never qualify.
        for tag in tags where excludedFragments.contains(where: { tag.slug.contains($0) }) {
            return false
        }

        // 2. Canonical English taxonomy id, emitted for every language OFF knows.
        let hasCanonicalBeer = tags.contains { tag in
            guard tag.language == "en" else { return false }
            if beerIDs.contains(tag.id) { return true }
            guard let last = tag.words.last else { return false }
            return last == "beer" || last == "beers"
        }
        if hasCanonicalBeer { return true }

        // 3. Untranslated contributor category, corroborated by an alcohol signal.
        let hasLocalisedBeer = tags.contains { tag in
            guard tag.language != "en", let first = tag.words.first else { return false }
            guard beerWords.contains(first) else { return false }
            return !tag.words.contains(where: nonBeerModifiers.contains)
        }
        guard hasLocalisedBeer else { return false }

        let alcoholFreeBeer = tags.contains { alcoholFreeBeerIDs.contains($0.id) }
        let alcoholic = tags.contains { alcoholicIDs.contains($0.id) }
            || (alcoholByVolume ?? 0) >= 0.05
        return alcoholic || alcoholFreeBeer
    }
}
