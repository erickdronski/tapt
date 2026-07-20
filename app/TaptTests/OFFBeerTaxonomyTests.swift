import XCTest
@testable import Tapt

final class OFFBeerTaxonomyTests: XCTestCase {

    func testAcceptsCanonicalEnglishBeer() {
        XCTAssertTrue(OFFBeerTaxonomy.isBeer(
            categoryTags: ["en:beverages", "en:alcoholic-beverages", "en:beers", "en:lagers"],
            alcoholByVolume: 4.8
        ))
    }

    func testAcceptsForeignBeerNormalisedByOFF() {
        // OFF maps known categories to the canonical English id in every
        // language, so a French product still carries en:beers.
        XCTAssertTrue(OFFBeerTaxonomy.isBeer(
            categoryTags: ["en:beverages", "en:alcoholic-beverages", "en:beers", "fr:bieres-blondes"],
            alcoholByVolume: 5.0
        ))
    }

    func testAcceptsUntranslatedForeignBeerWithAlcoholSignal() {
        // The regression: contributor categories OFF has not translated.
        XCTAssertTrue(OFFBeerTaxonomy.isBeer(
            categoryTags: ["en:beverages", "en:alcoholic-beverages", "pl:piwa", "pl:piwo-jasne-pelne"],
            alcoholByVolume: nil
        ))
        XCTAssertTrue(OFFBeerTaxonomy.isBeer(
            categoryTags: ["it:birra-artigianale"],
            alcoholByVolume: 5.2
        ))
        XCTAssertTrue(OFFBeerTaxonomy.isBeer(
            categoryTags: ["de:biere", "de:helles-vollbier"],
            alcoholByVolume: 4.9
        ))
        XCTAssertTrue(OFFBeerTaxonomy.isBeer(
            categoryTags: ["cs:pivo-svetly-lezak", "en:alcoholic-beverages"],
            alcoholByVolume: nil
        ))
    }

    func testAcceptsAccentedAndUnderscoredTags() {
        XCTAssertTrue(OFFBeerTaxonomy.isBeer(
            categoryTags: ["fr:Bières_Blondes", "en:alcoholic-beverages"],
            alcoholByVolume: nil
        ))
    }

    func testAcceptsAlcoholFreeBeer() {
        XCTAssertTrue(OFFBeerTaxonomy.isBeer(
            categoryTags: ["en:beverages", "en:beers", "en:non-alcoholic-beers"],
            alcoholByVolume: 0.0
        ))
    }

    func testRejectsRootAndGingerBeerAndBeerFoods() {
        for tags in [
            ["en:beverages", "en:sodas", "en:root-beers"],
            ["en:beverages", "en:sodas", "en:ginger-beers"],
            ["en:beverages", "en:sodas", "en:birch-beers"],
            ["en:plant-based-foods", "en:breads", "en:beer-breads"],
            ["en:dairies", "en:cheeses", "en:beer-cheeses"],
            ["en:groceries", "en:beer-batter"],
        ] {
            XCTAssertFalse(
                OFFBeerTaxonomy.isBeer(categoryTags: tags, alcoholByVolume: nil),
                "expected \(tags) to be rejected"
            )
        }
        // Alcoholic ginger beer is still not beer for Tapt.
        XCTAssertFalse(OFFBeerTaxonomy.isBeer(
            categoryTags: ["en:alcoholic-beverages", "en:ginger-beers"],
            alcoholByVolume: 4.0
        ))
        XCTAssertFalse(OFFBeerTaxonomy.isBeer(
            categoryTags: ["en:alcoholic-beverages", "es:cerveza-de-jengibre"],
            alcoholByVolume: 4.0
        ))
    }

    func testRejectsUntranslatedBeerWordWithoutAlcoholSignal() {
        // Blank beats invented: no corroboration, no add.
        XCTAssertFalse(OFFBeerTaxonomy.isBeer(
            categoryTags: ["pl:piwa"],
            alcoholByVolume: nil
        ))
    }

    func testRejectsNonBeerAndEmptyInput() {
        XCTAssertFalse(OFFBeerTaxonomy.isBeer(categoryTags: [], alcoholByVolume: nil))
        XCTAssertFalse(OFFBeerTaxonomy.isBeer(
            categoryTags: ["en:beverages", "en:waters", "en:spring-waters"],
            alcoholByVolume: nil
        ))
        XCTAssertFalse(OFFBeerTaxonomy.isBeer(
            categoryTags: ["en:beverages", "en:alcoholic-beverages", "en:wines"],
            alcoholByVolume: 12.5
        ))
    }
}
