import XCTest
@testable import Tapt

final class BeerProductImagePolicyTests: XCTestCase {
    func testAcceptsReviewedTaptCutout() {
        let arbitrary = "https://qfwiizvqxrhjlthbjosz.supabase.co/storage/v1/object/public/beer-cutouts/v2/product.png"
        let reviewed = "https://qfwiizvqxrhjlthbjosz.supabase.co/storage/v1/object/public/beer-cutouts/v2/00000000-0000-0000-0000-000000000000.png"
        let legacy = "https://qfwiizvqxrhjlthbjosz.supabase.co/storage/v1/object/public/beer-cutouts/00000000-0000-0000-0000-000000000000.png"

        XCTAssertNil(BeerProductImagePolicy.approvedURL(arbitrary))
        XCTAssertEqual(BeerProductImagePolicy.approvedURL(reviewed)?.absoluteString, reviewed)
        XCTAssertEqual(BeerProductImagePolicy.approvedURL(legacy)?.absoluteString, legacy)
    }

    func testRejectsRawSourcePhoto() {
        XCTAssertNil(BeerProductImagePolicy.approvedURL(
            "https://images.openfoodfacts.org/images/products/500/021/310/1223/front.full.jpg"
        ))
    }

    func testRejectsWrongBucketAndHost() {
        XCTAssertNil(BeerProductImagePolicy.approvedURL(
            "https://qfwiizvqxrhjlthbjosz.supabase.co/storage/v1/object/public/beer-labels/00000000-0000-0000-0000-000000000000.png"
        ))
        XCTAssertNil(BeerProductImagePolicy.approvedURL(
            "https://example.com/storage/v1/object/public/beer-cutouts/v2/00000000-0000-0000-0000-000000000000.png"
        ))
    }

    func testRejectsArbitraryCutoutObjectsAndUnreviewedVersions() {
        XCTAssertNil(BeerProductImagePolicy.approvedURL(
            "https://qfwiizvqxrhjlthbjosz.supabase.co/storage/v1/object/public/beer-cutouts/source-photo.jpg"
        ))
        XCTAssertNil(BeerProductImagePolicy.approvedURL(
            "https://qfwiizvqxrhjlthbjosz.supabase.co/storage/v1/object/public/beer-cutouts/pending/product.png"
        ))
        XCTAssertNil(BeerProductImagePolicy.approvedURL(
            "https://qfwiizvqxrhjlthbjosz.supabase.co/storage/v1/object/public/beer-cutouts/v3/00000000-0000-0000-0000-000000000000.png"
        ))
    }

    func testRejectsCredentialsAndInsecureTransport() {
        XCTAssertNil(BeerProductImagePolicy.approvedURL(
            "http://qfwiizvqxrhjlthbjosz.supabase.co/storage/v1/object/public/beer-cutouts/v2/00000000-0000-0000-0000-000000000000.png"
        ))
        XCTAssertNil(BeerProductImagePolicy.approvedURL(
            "https://user:password@qfwiizvqxrhjlthbjosz.supabase.co/storage/v1/object/public/beer-cutouts/v2/00000000-0000-0000-0000-000000000000.png"
        ))
        XCTAssertNil(BeerProductImagePolicy.approvedURL(
            "https://qfwiizvqxrhjlthbjosz.supabase.co/storage/v1/object/public/beer-cutouts/v2/00000000-0000-0000-0000-000000000000.png?download=1"
        ))
    }
}
