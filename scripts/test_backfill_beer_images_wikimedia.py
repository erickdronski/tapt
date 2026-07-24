from __future__ import annotations

import unittest
from unittest.mock import patch

from scripts.backfill_beer_images_wikimedia import (
    allowed_license,
    build_attribution,
    clean_metadata_text,
    commons_sources,
    preferred_p18_filename,
)


class WikidataImageTests(unittest.TestCase):
    def test_preferred_p18_wins(self) -> None:
        entity = {
            "claims": {
                "P18": [
                    {"rank": "normal", "mainsnak": {"datavalue": {"value": "Old.jpg"}}},
                    {"rank": "preferred", "mainsnak": {"datavalue": {"value": "Current.jpg"}}},
                ]
            }
        }

        self.assertEqual(preferred_p18_filename(entity), "Current.jpg")

    def test_metadata_html_is_removed(self) -> None:
        self.assertEqual(
            clean_metadata_text('<a href="https://example.com">Jane &amp; John</a>'),
            "Jane & John",
        )

    def test_free_licenses_are_allowed(self) -> None:
        for license_name in ("CC BY 4.0", "CC BY-SA 3.0", "CC0 1.0", "Public domain"):
            self.assertTrue(allowed_license(license_name), license_name)
        self.assertFalse(allowed_license("Fair use"))
        self.assertFalse(allowed_license("All rights reserved"))

    def test_attribution_requires_author_for_cc_by(self) -> None:
        metadata = {
            "LicenseShortName": {"value": "CC BY-SA 4.0"},
            "Artist": {"value": "<b>Jane Example</b>"},
        }
        self.assertEqual(
            build_attribution(metadata),
            "Jane Example - CC BY-SA 4.0 - Wikimedia Commons",
        )
        self.assertIsNone(build_attribution({
            "LicenseShortName": {"value": "CC BY 4.0"},
        }))

    def test_public_domain_can_stand_without_author(self) -> None:
        self.assertEqual(
            build_attribution({"LicenseShortName": {"value": "Public domain"}}),
            "Public domain - Wikimedia Commons",
        )

    @patch("scripts.backfill_beer_images_wikimedia.request_json")
    def test_commons_source_retains_audit_metadata(self, request_json) -> None:
        request_json.return_value = {
            "query": {
                "pages": {
                    "42": {
                        "title": "File:Example lager.jpg",
                        "fullurl": "https://commons.wikimedia.org/wiki/File:Example_lager.jpg",
                        "lastrevid": 123456,
                        "imageinfo": [{
                            "url": "https://upload.wikimedia.org/original.jpg",
                            "thumburl": "https://upload.wikimedia.org/thumb.jpg",
                            "descriptionurl": "https://commons.wikimedia.org/wiki/File:Example_lager.jpg",
                            "sha1": "a" * 40,
                            "timestamp": "2026-07-23T12:00:00Z",
                            "width": 2400,
                            "height": 3200,
                            "mime": "image/jpeg",
                            "extmetadata": {
                                "Artist": {"value": "Jane Example"},
                                "LicenseShortName": {"value": "CC BY-SA 4.0"},
                                "LicenseUrl": {
                                    "value": "https://creativecommons.org/licenses/by-sa/4.0/"
                                },
                            },
                        }],
                    }
                }
            }
        }

        source = commons_sources(["Example lager.jpg"])["example lager.jpg"]

        self.assertEqual(source["source_revision"], "123456")
        self.assertEqual(source["source_sha1"], "a" * 40)
        self.assertEqual(source["source_creator"], "Jane Example")
        self.assertEqual(source["source_width"], 2400)
        self.assertEqual(source["source_metadata"]["original_url"], "https://upload.wikimedia.org/original.jpg")


if __name__ == "__main__":
    unittest.main()
