from __future__ import annotations

import json
import unittest
from types import SimpleNamespace
from unittest.mock import patch

from scripts import backfill_beer_images_off as backfill


class OpenFoodFactsBackfillTests(unittest.TestCase):
    def test_product_response_must_repeat_requested_gtin(self) -> None:
        payload = json.dumps({
            "status": 1,
            "code": "87654321",
            "product": {
                "code": "87654321",
                "image_front_url": "https://images.openfoodfacts.org/front.jpg",
            },
        })

        with patch.object(backfill, "off_get", return_value=("200", payload)):
            self.assertEqual(backfill.off_product_front("12345678"), ("notfound", None))

    def test_exact_product_response_returns_front_image(self) -> None:
        image_url = "https://images.openfoodfacts.org/front.jpg"
        payload = json.dumps({
            "status": 1,
            "code": "12345678",
            "product": {"code": "12345678", "image_front_url": image_url},
        })

        with patch.object(backfill, "off_get", return_value=("200", payload)):
            self.assertEqual(backfill.off_product_front("12345678"), ("found", image_url))

    def test_candidate_staging_accepts_postgrest_created_status(self) -> None:
        with patch.object(
            backfill.subprocess,
            "run",
            return_value=SimpleNamespace(stdout="201"),
        ):
            backfill.stage_image_candidate(
                "00000000-0000-0000-0000-000000000000",
                "https://images.openfoodfacts.org/front.jpg",
                "12345678",
            )


if __name__ == "__main__":
    unittest.main()
