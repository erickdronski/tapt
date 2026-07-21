import argparse
import json
import sys
import types
import unittest
from unittest import mock


for dependency in ("duckdb", "h3", "pycountry"):
    sys.modules.setdefault(dependency, types.ModuleType(dependency))

from scripts import ingest_overture_venues as ingest


class OvertureUploadTests(unittest.TestCase):
    def setUp(self):
        self.args = argparse.Namespace(
            release="2026-06-17.0",
            confidence=0.86,
            max_rows=120_000,
            per_region=1_500,
            country=[],
            batch_size=400,
        )
        self.rows = [
            {"overture_id": "us-1", "country_code": "US"},
            {"overture_id": "ca-1", "country_code": "CA"},
            {"overture_id": "us-2", "country_code": "US"},
        ]

    def testLatestReleaseComesFromOfficialCatalog(self):
        response = mock.MagicMock()
        response.__enter__.return_value.read.return_value = json.dumps({
            "latest": "2026-07-22.0"
        }).encode("utf-8")

        with mock.patch.object(ingest.urllib.request, "urlopen", return_value=response):
            release = ingest.resolve_release("latest")

        self.assertEqual(release, "2026-07-22.0")

    def testExplicitReleaseIsValidatedWithoutNetwork(self):
        with mock.patch.object(ingest.urllib.request, "urlopen") as urlopen:
            self.assertEqual(ingest.resolve_release("2026-06-17.0"), "2026-06-17.0")
            with self.assertRaisesRegex(RuntimeError, "invalid Overture release"):
                ingest.resolve_release("../../private")

        urlopen.assert_not_called()

    def testUploadAppliesEachCountryExplicitlyAndAggregatesCounts(self):
        apply_payloads = []

        def request(path, *, payload=None, **_kwargs):
            if path.startswith("/rest/v1/overture_place_import"):
                return None
            self.assertEqual(path, "/rest/v1/rpc/apply_overture_place_import")
            apply_payloads.append(payload)
            if payload["p_country_code"] == "CA":
                return [{
                    "venues_inserted": 2,
                    "venues_updated": 3,
                    "venues_matched": 1,
                    "source_links_written": 6,
                }]
            return [{
                "venues_inserted": 5,
                "venues_updated": 7,
                "venues_matched": 2,
                "source_links_written": 14,
            }]

        with (
            mock.patch.object(ingest, "start_run", return_value="run-id"),
            mock.patch.object(ingest, "finish_run") as finish_run,
            mock.patch.object(ingest, "request_json", side_effect=request),
        ):
            counts = ingest.upload(self.rows, self.args)

        self.assertEqual(
            apply_payloads,
            [
                {"p_release": "2026-06-17.0", "p_country_code": "CA"},
                {"p_release": "2026-06-17.0", "p_country_code": "US"},
            ],
        )
        self.assertEqual(
            counts,
            {
                "venues_inserted": 7,
                "venues_updated": 10,
                "venues_matched": 3,
                "source_links_written": 20,
            },
        )
        finish_run.assert_called_once_with(
            "run-id",
            "succeeded",
            records_seen=3,
            records_inserted=7,
            records_updated=13,
            records_rejected=0,
            metadata={
                "release": "2026-06-17.0",
                "confidence": 0.86,
                "countries_applied": 2,
                "source_links_written": 20,
            },
        )

    def testUploadRecordsFailureWhenNoCountryCodedRowsExist(self):
        with (
            mock.patch.object(ingest, "start_run", return_value="run-id"),
            mock.patch.object(ingest, "finish_run") as finish_run,
            mock.patch.object(ingest, "request_json", return_value=None),
            self.assertRaisesRegex(RuntimeError, "no country-coded rows"),
        ):
            ingest.upload([{"overture_id": "unknown", "country_code": None}], self.args)

        finish_run.assert_called_once()
        self.assertEqual(finish_run.call_args.args[:2], ("run-id", "failed"))


if __name__ == "__main__":
    unittest.main()
