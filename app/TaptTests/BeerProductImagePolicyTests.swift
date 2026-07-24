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

    func testRawSourceIsNotTreatedAsReviewedCutout() {
        XCTAssertNil(BeerProductImagePolicy.approvedURL(
            "https://images.openfoodfacts.org/images/products/500/021/310/1223/front.full.jpg"
        ))
    }

    func testAcceptsTrustedProductPhotoSources() {
        let openFoodFacts = "https://images.openfoodfacts.org/images/products/500/021/310/1223/front.full.jpg"
        let wikimediaUpload = "https://upload.wikimedia.org/wikipedia/commons/a/a2/Beer_can.png"
        let wikimediaFilePath = "https://commons.wikimedia.org/wiki/Special:FilePath/Beer%20can.jpg?width=1200"

        XCTAssertEqual(BeerProductImagePolicy.approvedSourceURL(openFoodFacts)?.absoluteString, openFoodFacts)
        XCTAssertEqual(BeerProductImagePolicy.approvedSourceURL(wikimediaUpload)?.absoluteString, wikimediaUpload)
        XCTAssertEqual(BeerProductImagePolicy.approvedSourceURL(wikimediaFilePath)?.absoluteString, wikimediaFilePath)
    }

    func testDisplayAssetPreservesCutoutThenTrustedSourcePriority() {
        let reviewed = "https://qfwiizvqxrhjlthbjosz.supabase.co/storage/v1/object/public/beer-cutouts/v2/00000000-0000-0000-0000-000000000000.png"
        let source = "https://images.openfoodfacts.org/images/products/500/021/310/1223/front.full.jpg"

        XCTAssertEqual(BeerProductImagePolicy.displayAsset(reviewed)?.kind, .reviewedCutout)
        XCTAssertEqual(BeerProductImagePolicy.displayAsset(source)?.kind, .trustedSource)
        XCTAssertNil(BeerProductImagePolicy.displayAsset("https://example.com/beer.jpg"))
    }

    func testAcceptsReviewedV3Cutout() {
        let reviewed = "https://qfwiizvqxrhjlthbjosz.supabase.co/storage/v1/object/public/beer-cutouts/v3/00000000-0000-0000-0000-000000000000.png"

        XCTAssertEqual(BeerProductImagePolicy.approvedURL(reviewed)?.absoluteString, reviewed)
        XCTAssertEqual(BeerProductImagePolicy.displayAsset(reviewed)?.kind, .reviewedCutout)
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
            "https://qfwiizvqxrhjlthbjosz.supabase.co/storage/v1/object/public/beer-cutouts/v4/00000000-0000-0000-0000-000000000000.png"
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

    func testRejectsTrustedHostLookalikesAndUnexpectedNetworkFeatures() {
        XCTAssertNil(BeerProductImagePolicy.approvedSourceURL(
            "https://images.openfoodfacts.org.example.com/images/products/500/front.jpg"
        ))
        XCTAssertNil(BeerProductImagePolicy.approvedSourceURL(
            "http://images.openfoodfacts.org/images/products/500/front.jpg"
        ))
        XCTAssertNil(BeerProductImagePolicy.approvedSourceURL(
            "https://user:password@images.openfoodfacts.org/images/products/500/front.jpg"
        ))
        XCTAssertNil(BeerProductImagePolicy.approvedSourceURL(
            "https://images.openfoodfacts.org:8443/images/products/500/front.jpg"
        ))
        XCTAssertNil(BeerProductImagePolicy.approvedSourceURL(
            "https://images.openfoodfacts.org/images/products/500/front.jpg#label"
        ))
    }

    func testRejectsNonProductPathsAndUnsafeSourceQueries() {
        XCTAssertNil(BeerProductImagePolicy.approvedSourceURL(
            "https://images.openfoodfacts.org/assets/images/logo.png"
        ))
        XCTAssertNil(BeerProductImagePolicy.approvedSourceURL(
            "https://images.openfoodfacts.org/images/products/500/front.jpg?download=1"
        ))
        XCTAssertNil(BeerProductImagePolicy.approvedSourceURL(
            "https://upload.wikimedia.org/wikipedia/en/a/a2/Beer_can.png"
        ))
        XCTAssertNil(BeerProductImagePolicy.approvedSourceURL(
            "https://commons.wikimedia.org/wiki/File:Beer_can.jpg"
        ))
        XCTAssertNil(BeerProductImagePolicy.approvedSourceURL(
            "https://commons.wikimedia.org/wiki/Special:FilePath/Beer_can.jpg?download=1"
        ))
        XCTAssertNil(BeerProductImagePolicy.approvedSourceURL(
            "https://commons.wikimedia.org/wiki/Special:FilePath/Beer_can.jpg?width=9000"
        ))
    }

    func testRejectsUnsafeOrNonImageSourcePaths() {
        XCTAssertNil(BeerProductImagePolicy.approvedSourceURL(
            "https://images.openfoodfacts.org/images/products/%2e%2e/private/front.jpg"
        ))
        XCTAssertNil(BeerProductImagePolicy.approvedSourceURL(
            "https://images.openfoodfacts.org/images/products/500%2F..%2Fprivate/front.jpg"
        ))
        XCTAssertNil(BeerProductImagePolicy.approvedSourceURL(
            "https://images.openfoodfacts.org/images/products/500/front.svg"
        ))
    }
}
