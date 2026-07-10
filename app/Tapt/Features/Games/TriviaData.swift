import Foundation

// Real, verifiable trivia only, zero fabrication. Mixed topics so anyone can
// play, not just beer nerds: Beer, Pop Culture, Fun Facts & Feats, General.

struct TriviaQuestion: Identifiable {
    let id = UUID()
    let q: String
    let options: [String]
    let correct: Int
    let why: String
    var category: TriviaCategory = .beer
}

enum TriviaCategory: String, CaseIterable, Identifiable {
    case mixed = "Mixed"
    case beer = "Beer"
    case popCulture = "Pop Culture"
    case funFacts = "Fun Facts"
    case general = "General"
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .mixed: "shuffle"
        case .beer: "mug.fill"
        case .popCulture: "film.fill"
        case .funFacts: "sparkles"
        case .general: "globe"
        }
    }
}

enum TriviaData {
    static func pool(_ category: TriviaCategory) -> [TriviaQuestion] {
        category == .mixed ? questions : questions.filter { $0.category == category }
    }

    static let questions: [TriviaQuestion] = beer + popCulture + funFacts + general

    // MARK: - Beer
    static let beer: [TriviaQuestion] = [
        .init(q: "What does IBU measure?", options: ["Bitterness", "Alcohol", "Color", "Calories"], correct: 0,
              why: "IBU is International Bitterness Units, roughly how bitter the hops make a beer."),
        .init(q: "What grain is the backbone of most beer?", options: ["Rice", "Corn", "Barley", "Wheat"], correct: 2,
              why: "Malted barley provides most of the sugar that yeast turns into alcohol."),
        .init(q: "Where was the first pale lager (pilsner) brewed in 1842?", options: ["Germany", "Czechia", "Belgium", "USA"], correct: 1,
              why: "Pilsner Urquell was brewed in Plzen, Bohemia, and the golden pilsner was born."),
        .init(q: "In brewing, what is 'wort'?", options: ["Spent grain", "The sweet liquid before fermenting", "A hop variety", "Foam"], correct: 1,
              why: "Wort is the sugary liquid from the mash, before yeast turns it into beer."),
        .init(q: "What gives beer its bitterness and aroma?", options: ["Yeast", "Malt", "Hops", "Water"], correct: 2,
              why: "Hops add bitterness early in the boil and aroma late (or via dry hopping)."),
        .init(q: "Guinness is famously from which city?", options: ["London", "Dublin", "Cork", "Edinburgh"], correct: 1,
              why: "Arthur Guinness signed a 9,000-year lease at St. James's Gate in Dublin in 1759."),
        .init(q: "What does 'ABV' stand for?", options: ["Average Beer Value", "Alcohol By Volume", "Ale Body Variance", "Additive Base Volume"], correct: 1,
              why: "ABV is the percent of the drink that is alcohol."),
        .init(q: "A 'flight' at a taproom is:", options: ["A strong ale", "A set of small tasting pours", "A hop blend", "A brewing step"], correct: 1,
              why: "A flight is a row of small pours so you can taste several beers at once."),
        .init(q: "Compared to ales, lagers ferment at what temperature?", options: ["Hotter", "Colder", "The same", "It varies randomly"], correct: 1,
              why: "Lager yeast ferments cold and clean; ale yeast ferments warm and fruity."),
        .init(q: "The 1516 Bavarian beer purity law is called the...", options: ["Reinheitsgebot", "Oktoberfest", "Lagergesetz", "Hefeweizen"], correct: 0,
              why: "The Reinheitsgebot limited beer to water, barley, and hops. Yeast was not known yet."),
        .init(q: "Hazy IPAs are also known as ___ IPAs.", options: ["West Coast", "New England", "English", "Imperial"], correct: 1,
              why: "New England IPA (NEIPA) is soft, juicy, cloudy, and low in bitterness."),
        .init(q: "What does SRM measure?", options: ["Color", "Alcohol", "Bitterness", "Foam height"], correct: 0,
              why: "SRM is a beer color scale, from pale straw to deep black."),
        .init(q: "What does 'dry hopping' mainly add?", options: ["Aroma", "Color", "Salt", "Carbonation"], correct: 0,
              why: "Dry hopping adds hop aroma after the boil without adding much extra bitterness."),
        .init(q: "Which beer family often features banana and clove notes?", options: ["Hefeweizen", "Dry stout", "Gose", "West Coast IPA"], correct: 0,
              why: "German wheat yeast can create banana-like esters and clove-like phenols."),
        .init(q: "Which greeting means cheers in Japanese?", options: ["Kanpai", "Prost", "Salud", "Skal"], correct: 0,
              why: "Kanpai is the Japanese toast."),
        .init(q: "A gose is known for tartness plus:", options: ["Salt", "Smoke", "Chocolate", "Vanilla"], correct: 0,
              why: "Gose is a tart wheat ale traditionally touched with coriander and salinity."),
    ]

    // MARK: - Pop Culture
    static let popCulture: [TriviaQuestion] = [
        .init(q: "In the TV show Cheers, what is the name of the bar?", options: ["Cheers", "Paddy's", "The Drunken Clam", "Moe's"], correct: 0,
              why: "Cheers was set in a Boston bar of the same name, 'where everybody knows your name.'", category: .popCulture),
        .init(q: "Which fictional beer is served at Moe's Tavern in The Simpsons?", options: ["Duff", "Pawtucket", "Alamo", "Heisler"], correct: 0,
              why: "Homer Simpson's beer of choice is Duff.", category: .popCulture),
        .init(q: "What's the name of the bar in It's Always Sunny in Philadelphia?", options: ["Paddy's Pub", "MacLaren's", "The Winchester", "Cheers"], correct: 0,
              why: "The gang runs Paddy's Pub in Philadelphia.", category: .popCulture),
        .init(q: "In How I Met Your Mother, the group's regular bar is named:", options: ["MacLaren's", "Central Perk", "The Regal Beagle", "Ten Forward"], correct: 0,
              why: "MacLaren's Pub sits below the characters' apartment.", category: .popCulture),
        .init(q: "Which movie features the line 'I love you, man' around beer and friendship?", options: ["I Love You, Man", "Superbad", "The Hangover", "Old School"], correct: 0,
              why: "The 2009 comedy I Love You, Man is built around a bromance.", category: .popCulture),
        .init(q: "The band that sang '99 Luftballons' is from which country?", options: ["Germany", "Sweden", "France", "USA"], correct: 0,
              why: "Nena, a German band, released it in 1983.", category: .popCulture),
        .init(q: "Which beer brand's slogan was 'The King of Beers'?", options: ["Budweiser", "Coors", "Miller", "Pabst"], correct: 0,
              why: "Budweiser has long used 'The King of Beers.'", category: .popCulture),
        .init(q: "In The Office (US), what is the name of Kevin's band?", options: ["Scrantonicity", "The Threat", "Here Comes Treble", "Wilkes-Barre"], correct: 0,
              why: "Kevin drums for a Police cover band, Scrantonicity.", category: .popCulture),
        .init(q: "Which country hosts the original Oktoberfest each year?", options: ["Germany", "Austria", "Belgium", "USA"], correct: 0,
              why: "Oktoberfest is held in Munich, Germany.", category: .popCulture),
        .init(q: "What drink does 'The Dude' famously order in The Big Lebowski?", options: ["White Russian", "Martini", "Old Fashioned", "Mojito"], correct: 0,
              why: "The Dude sips White Russians throughout the film.", category: .popCulture),
    ]

    // MARK: - Fun Facts & Feats
    static let funFacts: [TriviaQuestion] = [
        .init(q: "One of the oldest known beer 'recipes' is a hymn to which Sumerian goddess?", options: ["Ninkasi", "Ishtar", "Athena", "Freya"], correct: 0,
              why: "The ~1800 BC Hymn to Ninkasi doubles as a brewing recipe.", category: .funFacts),
        .init(q: "The word 'bridal' comes from 'bride-ale', a wedding celebration with what?", options: ["Beer", "Bread", "Flowers", "Rings"], correct: 0,
              why: "A 'bride-ale' was a wedding feast where ale was brewed and sold to fund the couple.", category: .funFacts),
        .init(q: "In 1814 London, a giant tank burst and flooded streets with what?", options: ["Beer", "Milk", "Molasses", "Wine"], correct: 0,
              why: "The London Beer Flood released over a million liters of porter.", category: .funFacts),
        .init(q: "Ancient Egyptian workers who built the pyramids were partly paid in:", options: ["Beer", "Gold", "Salt", "Cattle"], correct: 0,
              why: "Beer was a daily ration and a form of payment in ancient Egypt.", category: .funFacts),
        .init(q: "Which record book was created by the head of a famous brewery?", options: ["Guinness World Records", "Ripley's", "Farmer's Almanac", "Blue Book"], correct: 0,
              why: "Guinness's managing director started the record book in 1955 to settle pub arguments.", category: .funFacts),
        .init(q: "Vikings believed a goat in Valhalla provided an endless supply of what?", options: ["Mead", "Gold", "Fire", "Ships"], correct: 0,
              why: "The goat Heidrun was said to give endless mead in Norse myth.", category: .funFacts),
        .init(q: "Beer foam is technically a:", options: ["Colloid (gas in liquid)", "Solid", "Crystal", "Plasma"], correct: 0,
              why: "Foam is a colloid, gas bubbles suspended in liquid, stabilized by proteins.", category: .funFacts),
        .init(q: "The study of beer and brewing is called:", options: ["Zythology", "Oenology", "Enology", "Cerealogy"], correct: 0,
              why: "Zythology is the study of beer; oenology is the study of wine.", category: .funFacts),
        .init(q: "Cenosillicaphobia is the (tongue-in-cheek) fear of:", options: ["An empty glass", "Bitter beer", "Crowds", "Foam"], correct: 0,
              why: "It's a joke term for the fear of an empty beer glass.", category: .funFacts),
        .init(q: "Before hops, beers were bittered with a herb mix called:", options: ["Gruit", "Grist", "Trub", "Krausen"], correct: 0,
              why: "Gruit was a blend of herbs used to flavor beer before hops took over.", category: .funFacts),
    ]

    // MARK: - General
    static let general: [TriviaQuestion] = [
        .init(q: "How many continents are there?", options: ["5", "6", "7", "8"], correct: 2,
              why: "There are seven continents.", category: .general),
        .init(q: "What is the largest planet in our solar system?", options: ["Saturn", "Jupiter", "Neptune", "Earth"], correct: 1,
              why: "Jupiter is the largest planet.", category: .general),
        .init(q: "Which ocean is the largest?", options: ["Atlantic", "Indian", "Arctic", "Pacific"], correct: 3,
              why: "The Pacific is the largest and deepest ocean.", category: .general),
        .init(q: "What is the capital of Australia?", options: ["Sydney", "Melbourne", "Canberra", "Perth"], correct: 2,
              why: "Canberra is the capital, not Sydney.", category: .general),
        .init(q: "How many strings does a standard guitar have?", options: ["4", "5", "6", "7"], correct: 2,
              why: "A standard guitar has six strings.", category: .general),
        .init(q: "What gas do plants primarily absorb?", options: ["Oxygen", "Carbon dioxide", "Nitrogen", "Helium"], correct: 1,
              why: "Plants absorb carbon dioxide and release oxygen.", category: .general),
        .init(q: "Which country has the most people?", options: ["USA", "India", "China", "Indonesia"], correct: 1,
              why: "India is now the most populous country.", category: .general),
        .init(q: "The Great Wall is located in which country?", options: ["Japan", "China", "Mongolia", "India"], correct: 1,
              why: "The Great Wall of China spans northern China.", category: .general),
        .init(q: "How many minutes are in a full day?", options: ["1200", "1440", "1600", "2400"], correct: 1,
              why: "24 hours x 60 = 1,440 minutes.", category: .general),
        .init(q: "What is the tallest mountain above sea level?", options: ["K2", "Denali", "Everest", "Kilimanjaro"], correct: 2,
              why: "Mount Everest is the tallest above sea level.", category: .general),
    ]
}
