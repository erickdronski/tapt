import Foundation
import SwiftUI

struct FlightQuest: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let why: String
    let icon: String
    let tint: Color
    let stops: [FlightStop]
}

struct FlightStop: Identifiable {
    let id = UUID()
    let style: String
    let prompt: String
    let clue: String
    let noLowFriendly: Bool
}

enum FlightsData {
    static let quests: [FlightQuest] = [
        .init(
            id: "world-lager-lap",
            title: "World Lager Lap",
            subtitle: "A global intro that starts crisp and ends roasty.",
            why: "A friendly way to learn how different countries shape the clean lager family, with small pours and No / Low choices welcome.",
            icon: "globe.europe.africa.fill",
            tint: Brand.gold,
            stops: [
                .init(style: "Pilsner", prompt: "Start bright and snappy.", clue: "Look for Czech, German, or Italian pilsner.", noLowFriendly: true),
                .init(style: "Helles", prompt: "Try the softer cousin.", clue: "Bready malt, low bitterness, easy finish.", noLowFriendly: true),
                .init(style: "Vienna Lager", prompt: "Move into amber.", clue: "Toasty, smooth, still clean.", noLowFriendly: false),
                .init(style: "Dunkel", prompt: "Finish dark without going heavy.", clue: "Chocolate crust, not stout-level roast.", noLowFriendly: false),
            ]
        ),
        .init(
            id: "hop-spectrum",
            title: "Hop Spectrum",
            subtitle: "Find your hop lane without getting wrecked by bitterness.",
            why: "This helps IPA-curious drinkers learn aroma, bitterness, haze, and balance as separate ideas.",
            icon: "leaf.fill",
            tint: Brand.hop,
            stops: [
                .init(style: "Pale Ale", prompt: "Start balanced.", clue: "Citrus or pine, but still malt-backed.", noLowFriendly: true),
                .init(style: "West Coast IPA", prompt: "Go crisp and bitter.", clue: "Clear, dry, piney, sharper finish.", noLowFriendly: false),
                .init(style: "Hazy IPA", prompt: "Try soft and juicy.", clue: "Cloudy, plush, tropical, less bite.", noLowFriendly: true),
                .init(style: "Double IPA", prompt: "Only if you want the big version.", clue: "A stronger capstone, not a speed run.", noLowFriendly: false),
            ]
        ),
        .init(
            id: "dark-room",
            title: "Dark Room",
            subtitle: "Roast, chocolate, coffee, and cream without gatekeeping.",
            why: "Dark beer is intimidating for a lot of people. This flight makes it approachable and flavor-first.",
            icon: "moon.stars.fill",
            tint: Brand.copper,
            stops: [
                .init(style: "Brown Ale", prompt: "Start nutty.", clue: "Caramel, bread crust, easy roast.", noLowFriendly: false),
                .init(style: "Porter", prompt: "Move to chocolate.", clue: "Cocoa and toast before coffee.", noLowFriendly: false),
                .init(style: "Stout", prompt: "Go roasty.", clue: "Coffee, dark chocolate, dry finish.", noLowFriendly: true),
                .init(style: "Nitro Stout", prompt: "Try texture as flavor.", clue: "Creamy pour, soft body, cascading foam.", noLowFriendly: false),
            ]
        ),
        .init(
            id: "no-low-all-stars",
            title: "No / Low All-Stars",
            subtitle: "Big flavor, zero pressure. These count just as much.",
            why: "Non-alcoholic beer is growing fast, and Tapt should treat mindful drinkers as first-class beer fans.",
            icon: "sparkle.magnifyingglass",
            tint: Brand.hop,
            stops: [
                .init(style: "Non-Alcoholic Lager", prompt: "Start clean.", clue: "Crisp, cold, social, low commitment.", noLowFriendly: true),
                .init(style: "Non-Alcoholic Pale Ale", prompt: "Find aroma.", clue: "Citrus hops without a heavy finish.", noLowFriendly: true),
                .init(style: "Non-Alcoholic IPA", prompt: "Try the flagship NA style.", clue: "Look for hop aroma and a firm finish.", noLowFriendly: true),
                .init(style: "Hop Water", prompt: "Finish off-beer-adjacent.", clue: "Sparkling hop aroma, no malt body.", noLowFriendly: true),
            ]
        ),
        .init(
            id: "sour-curious",
            title: "Sour Curious",
            subtitle: "Tart, fruity, salty, funky: one small step at a time.",
            why: "Sours are a huge discovery lane for casual drinkers because they map to citrus, fruit, and cocktails.",
            icon: "sun.max.fill",
            tint: Brand.gold,
            stops: [
                .init(style: "Wheat Beer", prompt: "Start soft.", clue: "Citrus, banana, clove, gentle body.", noLowFriendly: true),
                .init(style: "Berliner Weisse", prompt: "Go light and tart.", clue: "Low ABV, lemony, refreshing.", noLowFriendly: true),
                .init(style: "Gose", prompt: "Add salt.", clue: "Tart wheat with coriander and salinity.", noLowFriendly: true),
                .init(style: "Fruit Sour", prompt: "Finish vivid.", clue: "Berry, stone fruit, tropical, or smoothie-style.", noLowFriendly: true),
            ]
        ),
    ]
}
