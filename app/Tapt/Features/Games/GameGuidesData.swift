import Foundation

// Game Night Guides — original rule summaries for classic party games.
// House law, non-negotiable: Tapt games NEVER require drinking. Every guide
// uses penalty/point framing ("a sip if you're drinking, a point if you're
// not"), zero-proof always counts, and the safety banner ships on every
// surface. Game mechanics are public tradition; all text here is our own.

struct GameGuide: Identifiable {
    let id: String
    let title: String
    let needs: String
    let players: String
    let vibe: String
    let steps: [String]
    let houseRule: String
    let kind: GuideKind
}

enum GuideKind: String, CaseIterable, Identifiable {
    case cards = "With a deck of cards"
    case noProps = "No props needed"
    case templates = "Party templates"
    var id: String { rawValue }
}

enum GameGuidesData {
    static let safetyLine = "Tapt games never require alcohol. Penalties can be sips, points, or dares — zero-proof counts everywhere. Be of legal age if you drink, know your limits, and never drive after drinking."

    static let guides: [GameGuide] = [
        // ------------------------------------------------ with a real deck
        .init(
            id: "kings",
            title: "Kings (Ring of Fire)",
            needs: "One deck, one big cup, a table",
            players: "4–10",
            vibe: "The classic circle game — every card is a mini-rule.",
            steps: [
                "Spread the deck face-down in a ring around a center cup.",
                "Take turns drawing a card. Each rank has a rule — agree on your table's set before you start.",
                "A common set: Ace = everyone pays a penalty, 2 = pick someone, 3 = you pay, 4 = floor (last to touch pays), 5 = guys, 6 = girls, 7 = heaven (last hand up pays), 8 = pick a mate who shares your penalties, 9 = rhyme until someone breaks, 10 = categories, J = make a rule, Q = questions, K = add to the center cup.",
                "Breaking the ring or fumbling a rule costs a penalty.",
                "Whoever draws the fourth King takes the center-cup forfeit — decide what that is up front."
            ],
            houseRule: "A 'penalty' is whatever your table says: a sip if you're drinking, a point against you if you're not. The center-cup forfeit can be a dare or a silly chore.",
            kind: .cards
        ),
        .init(
            id: "presidents",
            title: "Presidents",
            needs: "One deck",
            players: "4–8",
            vibe: "A shedding race with a power ladder — win the round, rule the next.",
            steps: [
                "Deal the whole deck. The goal is to empty your hand first.",
                "Play cards equal to or higher than the last play (singles on singles, pairs on pairs). 2s clear the pile.",
                "First out is President, last out is the Peasant.",
                "Next round: the Peasant hands the President their best card; the President returns any card.",
                "Ranks shift every round — the ladder is the game."
            ],
            houseRule: "Traditionally the President may hand out penalties. Keep them as points, sips, or dares — your table's call.",
            kind: .cards
        ),
        .init(
            id: "horserace",
            title: "Horse Race",
            needs: "One deck",
            players: "3–12",
            vibe: "The loudest card game there is. Aces are horses, everyone bets.",
            steps: [
                "Pull the four Aces and line them up — those are the horses.",
                "Deal a sideline of 6–8 face-down cards perpendicular to the track.",
                "Everyone bets a penalty amount on a suit.",
                "Flip deck cards one at a time — the matching Ace advances one length.",
                "Each time the lead horse passes a sideline card, flip it: that suit's horse falls back one.",
                "First Ace past the last sideline card wins. Losing bettors pay their bet; winners hand theirs out."
            ],
            houseRule: "Bets are penalties: sips, points, or the loser refills snacks. Commentate the race like it's the Derby — that's the whole point.",
            kind: .cards
        ),
        .init(
            id: "cheat",
            title: "Cheat (Call Your Bluff)",
            needs: "One deck",
            players: "3–8",
            vibe: "Lie with a straight face, catch your friends lying with theirs.",
            steps: [
                "Deal the whole deck. First player discards face-down claiming 'two Aces' (or however many).",
                "Play continues up the ranks — 2s, 3s, 4s — each player claiming what they put down.",
                "Anyone can call 'Cheat!' Flip the cards: if the claim was a lie, the liar takes the pile; if it was true, the caller takes it.",
                "First player to shed every card wins."
            ],
            houseRule: "Taking the pile can also cost a penalty — points or sips per your table.",
            kind: .cards
        ),
        // ------------------------------------------------ no props
        .init(
            id: "categories",
            title: "Categories",
            needs: "Nothing",
            players: "3–12",
            vibe: "Name things fast. Blank = you pay.",
            steps: [
                "Pick a category — beer styles, world capitals, cereal brands.",
                "Go around the circle; each person names one item, no repeats.",
                "Hesitate, repeat, or blank and you take the penalty.",
                "Loser picks the next category."
            ],
            houseRule: "Use Tapt's Beer School glossary as a category and call it studying.",
            kind: .noProps
        ),
        .init(
            id: "mostlikely",
            title: "Most Likely",
            needs: "Nothing",
            players: "4–12",
            vibe: "The group decides who'd do it. Democracy at its funniest.",
            steps: [
                "Someone asks 'Who's most likely to…' — sleep through a flight, adopt a fifth dog, become a regular at a taproom.",
                "On three, everyone points at their pick.",
                "The most-pointed-at person takes a penalty per finger, or just owns the title.",
                "They ask the next question."
            ],
            houseRule: "Keep it kind — roast the behavior, not the person.",
            kind: .noProps
        ),
        .init(
            id: "straightface",
            title: "Straight Face",
            needs: "Phones or paper",
            players: "4–10",
            vibe: "Read absurd lines without cracking. Harder than it sounds.",
            steps: [
                "Everyone writes the most ridiculous (clean-ish) sentence they can.",
                "Fold the papers into a pile.",
                "Take turns drawing one and reading it aloud, dead-serious.",
                "Smile or laugh while reading and you take the penalty."
            ],
            houseRule: "Two-round minimum: sentences get unhinged once people learn the meta.",
            kind: .noProps
        ),
        .init(
            id: "buzz",
            title: "Buzz",
            needs: "Nothing",
            players: "3–10",
            vibe: "Count to 100 as a group. You won't make it.",
            steps: [
                "Count around the circle: 1, 2, 3…",
                "Any number with a 7 in it or divisible by 7 becomes 'buzz'.",
                "Say the number instead of buzz — or buzz at the wrong time — and you pay, and the count restarts.",
                "Feeling strong? Add 'fizz' for 5s."
            ],
            houseRule: "The table's record becomes a standing challenge for next time.",
            kind: .noProps
        ),
        // ------------------------------------------------ templates
        .init(
            id: "beer-olympics",
            title: "Beer Olympics",
            needs: "Teams, events, the Tapt scoreboard",
            players: "6–20 (2–6 teams)",
            vibe: "An opening ceremony, a medal table, and bragging rights that last all year.",
            steps: [
                "Draft 2–6 teams — names and countries mandatory, costumes encouraged.",
                "Pick 3–7 events. Mix Tapt digital games (Trivia, Pong, Flip Cup, Quarters) with table events (cornhole, cup stack relay, Categories).",
                "Run each event; the Tapt scoreboard (Games → Beer Olympics) tracks gold/silver/bronze.",
                "Medal points decide the champion: gold 3, silver 2, bronze 1.",
                "Podium photo with the share card. Loser team plans the next Olympics."
            ],
            houseRule: "Hydration station is an official event sponsor. Zero-proof athletes medal the same as anyone.",
            kind: .templates
        ),
        .init(
            id: "tasting-night",
            title: "Tasting Flight Night",
            needs: "4–6 different beers (NA welcome), small glasses, Tapt",
            players: "2–8",
            vibe: "The classy one. Taste, rate, argue, stamp your Passport.",
            steps: [
                "Everyone brings a bottle or can nobody else has tried — mix styles, countries, and at least one No/Low pick.",
                "Pour small — a flight is a journey, not a race.",
                "Scan and log each pour in Tapt as you go; rate before discussing so nobody anchors.",
                "Reveal ratings together. Debate accordingly.",
                "Highest-rated bottle's bringer picks next month's theme."
            ],
            houseRule: "Use Beer School's flavor vocab between rounds — palate practice is the secret goal.",
            kind: .templates
        ),
        .init(
            id: "trivia-night",
            title: "Pub Trivia Night",
            needs: "Tapt Trivia + a scorekeeper",
            players: "4–16 (teams of 2–4)",
            vibe: "Run your own pub quiz — Tapt is the question master.",
            steps: [
                "Split into teams; each round is one 5-question Tapt Daily 5 run, passed around.",
                "Teams lock answers before flipping — honor system, loudly enforced.",
                "Three rounds plus a final wager round: bet any or all of your points.",
                "Champion team names the next trivia night's theme."
            ],
            houseRule: "Wrong-answer penalties are points by default; your table can house-rule anything.",
            kind: .templates
        ),
    ]
}
