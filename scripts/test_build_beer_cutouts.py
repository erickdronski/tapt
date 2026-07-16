from __future__ import annotations

import unittest
from typing import Any

import numpy as np
from PIL import Image, ImageDraw

from scripts.build_beer_cutouts import (
    Candidate,
    PipelineError,
    SupabaseAPI,
    add_studio_depth,
    preferred_source_urls,
    validate_candidate,
    validate_normalized_cutout,
    validate_source_mask,
)


class FakeResponse:
    def __init__(self, value: Any):
        self.value = value

    def json(self) -> Any:
        return self.value


class PagingAPI(SupabaseAPI):
    def __init__(self) -> None:
        self.catalog_offsets: list[int] = []
        self.old_rows = [
            {
                "id": f"old-{index}",
                "name": f"Old {index}",
                "label_image_url": f"https://images.openfoodfacts.org/old-{index}.jpg",
                "label_image_license": "Open Food Facts",
            }
            for index in range(500)
        ]
        self.new_row = {
            "id": "new-500",
            "name": "Next Product",
            "label_image_url": "https://images.openfoodfacts.org/new-500.jpg",
            "label_image_license": "Open Food Facts",
        }

    def request(self, method: str, path: str, **kwargs: Any) -> FakeResponse:
        params = kwargs["params"]
        if path == "/rest/v1/beer_catalog":
            offset = int(params["offset"])
            self.catalog_offsets.append(offset)
            return FakeResponse(self.old_rows if offset == 0 else [self.new_row])

        raw_ids = params["beer_id"][4:-1]
        ids = raw_ids.split(",") if raw_ids else []
        statuses = [
            {
                "beer_id": beer_id,
                "status": "rejected",
                "attempts": 3,
                "source_url": f"https://images.openfoodfacts.org/{beer_id}.jpg",
                "error_code": "visual_quality_review",
                "pipeline_version": "v2",
            }
            for beer_id in ids
            if beer_id.startswith("old-")
        ]
        return FakeResponse(statuses)


class CandidatePagingTests(unittest.TestCase):
    def test_terminal_first_page_does_not_hide_later_candidates(self) -> None:
        api = PagingAPI()

        candidates = api.candidates(target_count=1, retry_rejected=False)

        self.assertEqual([candidate.id for candidate in candidates], ["new-500"])
        self.assertEqual(api.catalog_offsets, [0, 500])


class CutoutQualityTests(unittest.TestCase):
    @staticmethod
    def canvas(
        box: tuple[int, int, int, int] = (350, 100, 674, 900),
        color: tuple[int, int, int, int] = (40, 150, 220, 255),
    ) -> Image.Image:
        image = Image.new("RGBA", (1024, 1024), (0, 0, 0, 0))
        draw = ImageDraw.Draw(image)
        draw.rectangle(box, fill=color)
        left, top, right, bottom = box
        accent = tuple(min(channel + 80, 255) for channel in color[:3]) + (color[3],)
        draw.rectangle(
            (left, top + (bottom - top) // 3, right, top + (bottom - top) // 2),
            fill=accent,
        )
        return image

    def assert_rejected(self, image: Image.Image, code: str) -> None:
        with self.assertRaises(PipelineError) as raised:
            validate_normalized_cutout(image, "Test lager")
        self.assertEqual(raised.exception.code, code)

    def test_clean_portrait_product_passes(self) -> None:
        validate_normalized_cutout(self.canvas(), "Test lager")

    def test_small_foreground_is_rejected(self) -> None:
        self.assert_rejected(self.canvas((400, 300, 624, 700)), "output_too_small")

    def test_wide_single_product_is_rejected(self) -> None:
        self.assert_rejected(self.canvas((150, 300, 874, 700)), "mask_not_portrait")

    def test_asymmetric_foreground_is_rejected(self) -> None:
        image = self.canvas((400, 100, 624, 900))
        ImageDraw.Draw(image).rectangle((624, 500, 850, 650), fill=(210, 130, 90, 255))
        self.assert_rejected(image, "mask_asymmetric")

    def test_soft_foreground_is_rejected(self) -> None:
        self.assert_rejected(
            self.canvas(color=(40, 150, 220, 180)),
            "alpha_too_soft",
        )

    def test_dark_foreground_is_rejected(self) -> None:
        self.assert_rejected(
            self.canvas(color=(8, 8, 8, 255)),
            "image_too_dark",
        )

    def test_explicit_multipack_is_rejected(self) -> None:
        with self.assertRaises(PipelineError) as raised:
            validate_normalized_cutout(self.canvas(), "Test lager 12 pack")
        self.assertEqual(raised.exception.code, "multipack_source")

    def test_detached_second_product_is_rejected(self) -> None:
        image = self.canvas((400, 100, 624, 900))
        ImageDraw.Draw(image).rectangle((700, 300, 790, 720), fill=(40, 150, 220, 255))
        self.assert_rejected(image, "multiple_foregrounds")

    def test_large_hole_through_product_is_rejected(self) -> None:
        image = self.canvas((400, 100, 624, 900))
        ImageDraw.Draw(image).ellipse((455, 430, 545, 520), fill=(0, 0, 0, 0))
        self.assert_rejected(image, "mask_internal_damage")

    def test_hand_like_base_flare_is_rejected(self) -> None:
        image = self.canvas((400, 100, 624, 900))
        ImageDraw.Draw(image).rectangle((340, 740, 684, 900), fill=(40, 150, 220, 255))
        self.assert_rejected(image, "mask_base_flare")

    def test_source_subject_touching_edge_is_rejected(self) -> None:
        mask = Image.new("L", (400, 600), 0)
        ImageDraw.Draw(mask).rectangle((0, 40, 180, 560), fill=255)
        with self.assertRaises(PipelineError) as raised:
            validate_source_mask(np.asarray(mask) > 0)
        self.assertEqual(raised.exception.code, "foreground_cropped")

    def test_studio_depth_keeps_transparent_background(self) -> None:
        image = self.canvas()
        result = add_studio_depth(image)
        alpha = result.getchannel("A")
        self.assertEqual(alpha.getpixel((0, 0)), 0)
        self.assertGreater(alpha.getpixel((512, 915)), 0)
        self.assertEqual(result.getpixel((512, 500))[:3], image.getpixel((512, 500))[:3])


class SourcePolicyTests(unittest.TestCase):
    def test_off_thumbnail_prefers_full_resolution(self) -> None:
        source = (
            "https://images.openfoodfacts.org/images/products/009/093/501/4364/"
            "front_pl.3.400.jpg"
        )
        self.assertEqual(
            preferred_source_urls(source),
            [
                source.replace(".400.jpg", ".full.jpg"),
                source,
            ],
        )

    def test_unapproved_source_host_is_rejected(self) -> None:
        candidate = Candidate(
            id="00000000-0000-0000-0000-000000000000",
            name="Test lager",
            source_url="https://example.com/product.jpg",
            license="CC BY-SA",
        )
        with self.assertRaises(PipelineError) as raised:
            validate_candidate(candidate)
        self.assertEqual(raised.exception.code, "source_not_allowed")

    def test_unapproved_supabase_bucket_is_rejected(self) -> None:
        candidate = Candidate(
            id="00000000-0000-0000-0000-000000000000",
            name="Test lager",
            source_url=(
                "https://qfwiizvqxrhjlthbjosz.supabase.co/"
                "storage/v1/object/public/avatars/user.png"
            ),
            license="CC BY-SA",
        )
        with self.assertRaises(PipelineError) as raised:
            validate_candidate(candidate)
        self.assertEqual(raised.exception.code, "source_not_allowed")

    def test_only_uuid_png_cutout_objects_are_accepted_from_supabase(self) -> None:
        accepted = Candidate(
            id="00000000-0000-0000-0000-000000000000",
            name="Test lager",
            source_url=(
                "https://qfwiizvqxrhjlthbjosz.supabase.co/"
                "storage/v1/object/public/beer-cutouts/"
                "00000000-0000-0000-0000-000000000000.png"
            ),
            license="CC BY-SA",
        )
        validate_candidate(accepted)

        rejected = Candidate(
            id=accepted.id,
            name=accepted.name,
            source_url=(
                "https://qfwiizvqxrhjlthbjosz.supabase.co/"
                "storage/v1/object/public/beer-cutouts/source-photo.jpg"
            ),
            license=accepted.license,
        )
        with self.assertRaises(PipelineError) as raised:
            validate_candidate(rejected)
        self.assertEqual(raised.exception.code, "source_not_allowed")

    def test_source_query_parameters_are_rejected(self) -> None:
        candidate = Candidate(
            id="00000000-0000-0000-0000-000000000000",
            name="Test lager",
            source_url="https://images.openfoodfacts.org/product.jpg?download=1",
            license="CC BY-SA",
        )
        with self.assertRaises(PipelineError) as raised:
            validate_candidate(candidate)
        self.assertEqual(raised.exception.code, "source_not_allowed")

    def test_candidate_requires_license(self) -> None:
        candidate = Candidate(
            id="00000000-0000-0000-0000-000000000000",
            name="Test lager",
            source_url="https://images.openfoodfacts.org/product.jpg",
            license=None,
        )
        with self.assertRaises(PipelineError) as raised:
            validate_candidate(candidate)
        self.assertEqual(raised.exception.code, "source_license_missing")


if __name__ == "__main__":
    unittest.main()
