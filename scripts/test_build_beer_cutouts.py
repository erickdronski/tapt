from __future__ import annotations

import unittest
from typing import Any

from PIL import Image, ImageDraw

from scripts.build_beer_cutouts import (
    PipelineError,
    SupabaseAPI,
    validate_normalized_cutout,
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

    def test_explicit_multipack_can_be_wide(self) -> None:
        validate_normalized_cutout(
            self.canvas((150, 300, 874, 700)),
            "Test lager 12 pack",
        )


if __name__ == "__main__":
    unittest.main()
