from __future__ import annotations

import unittest
from typing import Any

from scripts.build_beer_cutouts import SupabaseAPI


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


if __name__ == "__main__":
    unittest.main()
