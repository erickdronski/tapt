import XCTest
@testable import Tapt

final class TastePreferencesTests: XCTestCase {
    func testDecodeReturnsCanonicalStylesWithoutDuplicates() {
        XCTAssertEqual(
            TastePreferences.decode("stout, IPA,stout,unknown"),
            ["IPA", "Stout"]
        )
    }

    func testEncodeUsesStablePickerOrder() {
        XCTAssertEqual(
            TastePreferences.encode(["Stout", "IPA", "No / Low"]),
            "IPA,Stout,No / Low"
        )
    }

    func testMatchesStyleFamiliesAndNoLow() {
        XCTAssertTrue(TastePreferences.matches(
            style: "Belgian Tripel",
            isNaLow: false,
            selectedStyles: ["Belgian"]
        ))
        XCTAssertTrue(TastePreferences.matches(
            style: "Non-Alcoholic Lager",
            isNaLow: true,
            selectedStyles: ["No / Low"]
        ))
        XCTAssertFalse(TastePreferences.matches(
            style: "Irish Stout",
            isNaLow: false,
            selectedStyles: ["Pilsner"]
        ))
    }
}
