import Foundation

// Real, well-established beer facts. Zero fabrication: keep additions sourced.

struct BrewStep: Identifiable {
    let id = UUID()
    let n: Int
    let title: String
    let what: String
    let machine: String
}

struct GlossaryTerm: Identifiable {
    let id = UUID()
    let term: String
    let definition: String
    let slang: Bool
}

struct Milestone: Identifiable {
    let id = UUID()
    let year: String
    let title: String
    let detail: String
}

struct BreweryOrigin: Identifiable {
    let id = UUID()
    let name: String
    let founded: String
    let place: String
    let story: String
    let fact: String
}

enum LearnData {
    static let brewing: [BrewStep] = [
        .init(n: 1, title: "Malting", what: "Barley is soaked, sprouted, then kiln-dried. That locks in the sugars and sets the color, from pale gold to roasty black.", machine: "The kiln"),
        .init(n: 2, title: "Milling", what: "The malt is cracked open so hot water can reach the starch inside. Not ground to flour, just cracked.", machine: "The roller mill"),
        .init(n: 3, title: "Mashing", what: "Cracked malt steeps in hot water and enzymes turn starch into sugar, making a sweet liquid called wort.", machine: "The mash tun"),
        .init(n: 4, title: "Lautering", what: "The sweet wort is drained off and separated from the leftover grain husks.", machine: "The lauter tun"),
        .init(n: 5, title: "The boil", what: "The wort boils hard and hops go in: early hops add bitterness, late hops add aroma.", machine: "The brew kettle"),
        .init(n: 6, title: "Fermentation", what: "Cooled wort meets yeast, which eats the sugar and makes alcohol and CO2 over days to weeks. This is where beer becomes beer.", machine: "The fermentation tank"),
        .init(n: 7, title: "Conditioning & packaging", what: "The beer matures, clears, and carbonates, then it is kegged, canned, or bottled and sent out fresh.", machine: "Bright tanks & the canning line"),
    ]

    static let glossary: [GlossaryTerm] = [
        .init(term: "ABV", definition: "Alcohol by volume. The percent of the drink that is alcohol.", slang: false),
        .init(term: "IBU", definition: "International Bitterness Units. Roughly how bitter the hops make it.", slang: false),
        .init(term: "SRM", definition: "The color scale, from pale straw to pitch black.", slang: false),
        .init(term: "Wort", definition: "The sweet, unfermented liquid before yeast turns it into beer.", slang: false),
        .init(term: "Dry hopping", definition: "Adding hops after the boil for big aroma without extra bitterness.", slang: false),
        .init(term: "Hazy / NEIPA", definition: "New England IPA. Soft, juicy, cloudy, low bitterness.", slang: false),
        .init(term: "Sessionable", definition: "Low enough in alcohol to enjoy a few over a session.", slang: false),
        .init(term: "Crushable", definition: "So easy to drink you immediately want another. High praise.", slang: true),
        .init(term: "Growler", definition: "A refillable jug, usually 32 or 64 oz, filled straight from the tap.", slang: false),
        .init(term: "Crowler", definition: "A big single-use can filled and sealed at the bar.", slang: false),
        .init(term: "Flight", definition: "A row of small pours so you can taste several beers at once.", slang: false),
        .init(term: "Keg", definition: "A pressurized metal barrel that serves beer on tap.", slang: false),
        .init(term: "Cask / real ale", definition: "Unfiltered beer that keeps conditioning in the cask, served soft and low-carb.", slang: false),
        .init(term: "Nitro", definition: "Poured with nitrogen for a creamy, cascading head.", slang: false),
        .init(term: "Lacing", definition: "The rings of foam a good beer leaves down the inside of the glass.", slang: false),
        .init(term: "Gravity (OG/FG)", definition: "How much sugar is in the wort before and after fermenting. It tells you the strength.", slang: false),
        .init(term: "Adjunct", definition: "Anything fermentable besides malt: corn, rice, oats, fruit, and more.", slang: false),
        .init(term: "Lager vs ale", definition: "Two yeast families. Lagers ferment cold and clean, ales ferment warm and fruity.", slang: false),
        .init(term: "Whale", definition: "A rare, hard-to-find beer that collectors chase.", slang: true),
        .init(term: "Haul", definition: "The beers you scored on a run, drop, or trade.", slang: true),
        .init(term: "Tick", definition: "To log a beer you have tried for the first time.", slang: true),
        .init(term: "Tap takeover", definition: "When one brewery takes over most of a bar's taps for a night.", slang: false),
    ]

    static let timeline: [Milestone] = [
        .init(year: "c. 3400 BC", title: "The ancient roots", detail: "Some of the oldest chemical evidence of barley beer comes from the ancient Near East. Beer is about as old as farming."),
        .init(year: "c. 1800 BC", title: "The Hymn to Ninkasi", detail: "The Sumerian goddess of beer gets a hymn that doubles as a brewing recipe, one of the oldest we know of."),
        .init(year: "c. 1754 BC", title: "Beer in the law books", detail: "The Code of Hammurabi regulates beer sellers in Babylon, beer rules are older than most empires."),
        .init(year: "822 AD", title: "Hops on the record", detail: "A Frankish abbot writes one of the first clear mentions of using hops in beer."),
        .init(year: "Middle Ages", title: "The monastery era", detail: "European monasteries turn brewing into a craft, better records, better methods, and beer safe enough to drink daily. Trappist brewing survives to this day."),
        .init(year: "1516", title: "The Reinheitsgebot", detail: "Bavaria limits beer to water, barley, and hops, the famous purity law. Yeast had not been discovered yet."),
        .init(year: "1722", title: "Porter conquers London", detail: "A dark, hoppy beer brewed for London's working porters becomes arguably the world's first industrial-scale beer style."),
        .init(year: "1759", title: "Guinness signs a 9,000-year lease", detail: "Arthur Guinness leases St. James's Gate in Dublin for 45 pounds a year, and bets on dark porter."),
        .init(year: "1800s", title: "IPA rides the trade routes", detail: "Strongly hopped pale ales survive the long sea voyage to British India, the style that would someday rule American craft taps."),
        .init(year: "1842", title: "The first pale lager", detail: "Pilsner Urquell is brewed in Plze. The clear, golden pilsner is born and takes over the world."),
        .init(year: "1840s", title: "Lager crosses the Atlantic", detail: "German immigrants bring lager yeast and brewing tradition to America, Milwaukee, St. Louis, and Cincinnati become beer towns."),
        .init(year: "1857", title: "Pasteur explains yeast", detail: "Louis Pasteur shows that living yeast drives fermentation, turning brewing into a science."),
        .init(year: "1883", title: "Pure yeast", detail: "Emil Hansen at the Carlsberg Laboratory isolates a single lager yeast strain for clean, repeatable beer."),
        .init(year: "1920", title: "US Prohibition", detail: "For 13 years, making and selling beer is banned across the United States."),
        .init(year: "1933", title: "Beer comes back", detail: "Prohibition ends; only a fraction of America's breweries reopen, and light lager giants define the next half-century."),
        .init(year: "1978", title: "Homebrewing legalized in the US", detail: "A new law makes home brewing legal again, and the craft beer movement starts to build."),
        .init(year: "1980", title: "Sierra Nevada opens", detail: "Ken Grossman's Pale Ale makes bold American hops the star and helps define modern craft beer."),
        .init(year: "2010s", title: "The haze craze", detail: "New England's soft, juicy, cloudy IPAs flip the script on bitterness and become craft beer's biggest style story in decades."),
        .init(year: "2020s", title: "The zero-proof wave", detail: "Non-alcoholic craft beer becomes one of the industry's fastest-growing segments, big flavor, no proof, first-class in Tapt."),
    ]

    static let origins: [BreweryOrigin] = [
        .init(name: "Guinness", founded: "1759", place: "Dublin, Ireland", story: "Arthur Guinness took over a small Dublin brewery and signed a legendary 9,000-year lease. He bet everything on a dark porter, and the dry Irish stout became a global icon.", fact: "The 'surge' in a nitro Guinness is bubbles sinking, not rising."),
        .init(name: "Heineken", founded: "1864", place: "Amsterdam, Netherlands", story: "Gerard Heineken bought a brewery at 22 and chased one thing: consistency. The 'A-yeast' his lab developed in 1886 still flavors every Heineken today.", fact: "The tilted 'e's in the logo are meant to look like little smiling faces."),
        .init(name: "Budweiser (Anheuser-Busch)", founded: "1876", place: "St. Louis, USA", story: "Adolphus Busch used new refrigerated rail cars and pasteurization to ship a light lager coast to coast, something no brewer had done at that scale.", fact: "It became one of the first truly national beer brands in America."),
        .init(name: "Carlsberg", founded: "1847", place: "Copenhagen, Denmark", story: "J.C. Jacobsen was obsessed with science. His Carlsberg Laboratory isolated the first pure lager yeast and gave the discovery to the world for free.", fact: "That same lab invented the pH scale in 1909."),
        .init(name: "Pilsner Urquell", founded: "1842", place: "Plze, Czechia", story: "Fed up with bad beer, the townspeople of Plze built a new brewery and hired Bavarian brewer Josef Groll. His pale lager created a whole new style: pilsner.", fact: "'Urquell' means 'original source'. Most of the world's beer descends from it."),
        .init(name: "Sierra Nevada", founded: "1980", place: "Chico, California, USA", story: "Ken Grossman built his brewery partly from repurposed dairy tanks and scrap. Sierra Nevada Pale Ale made citrusy American hops famous.", fact: "It helped kick off the modern American craft beer boom."),
        .init(name: "Samuel Adams (Boston Beer)", founded: "1984", place: "Boston, USA", story: "Jim Koch brewed his great-great-grandfather's recipe in his kitchen, then sold it bar to bar out of a briefcase.", fact: "It's named for a founding father who was also a maltster."),
        .init(name: "Stella Artois", founded: "1366", place: "Leuven, Belgium", story: "The Den Hoorn brewery in Leuven traces back to 1366. Its 'Stella' (Latin for star) Christmas lager launched in 1926 and simply never left.", fact: "The star and '1366' on the label point back to that medieval brewery."),
    ]
}
