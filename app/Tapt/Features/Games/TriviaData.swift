import Foundation

struct TriviaQuestion: Identifiable {
    let id = UUID()
    let q: String
    let options: [String]
    let correct: Int
    let why: String
}

enum TriviaData {
    static let questions: [TriviaQuestion] = [
        .init(q: "What does IBU measure?", options: ["Bitterness", "Alcohol", "Color", "Calories"], correct: 0,
              why: "IBU is International Bitterness Units, roughly how bitter the hops make a beer."),
        .init(q: "What grain is the backbone of most beer?", options: ["Rice", "Corn", "Barley", "Wheat"], correct: 2,
              why: "Malted barley provides most of the sugar that yeast turns into alcohol."),
        .init(q: "Where was the first pale lager (pilsner) brewed in 1842?", options: ["Germany", "Czechia", "Belgium", "USA"], correct: 1,
              why: "Pilsner Urquell was brewed in Plze, Bohemia, and the golden pilsner was born."),
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
        .init(q: "What is a 'growler'?", options: ["A bitter hop", "A refillable jug from the tap", "A yeast strain", "A type of glass"], correct: 1,
              why: "A growler is a refillable jug, usually 32 or 64 oz, filled straight from the tap."),
        .init(q: "The 1516 Bavarian beer purity law is called the...", options: ["Reinheitsgebot", "Oktoberfest", "Lagergesetz", "Hefeweizen"], correct: 0,
              why: "The Reinheitsgebot limited beer to water, barley, and hops. Yeast was not known yet."),
        .init(q: "Hazy IPAs are also known as ___ IPAs.", options: ["West Coast", "New England", "English", "Imperial"], correct: 1,
              why: "New England IPA (NEIPA) is soft, juicy, cloudy, and low in bitterness."),
    ]
}
