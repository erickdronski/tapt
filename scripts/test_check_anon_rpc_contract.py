"""Offline tests for the anon RPC contract guard.

These run in Release Integrity's existing unittest step with no secrets, so the
DIFF LOGIC is always covered even when the live check skips (fork PRs). The live
half is exercised separately by the workflow step that has the service key.
"""
import json
import unittest
from pathlib import Path
from unittest import mock

import check_anon_rpc_contract as guard


class ContractManifest(unittest.TestCase):
    def test_manifest_is_sorted_and_unique(self):
        """A sorted, duplicate-free list keeps diffs readable and merges sane."""
        allowed = json.loads(guard.CONTRACT.read_text())["allowed"]
        self.assertEqual(allowed, sorted(allowed), "manifest must be sorted")
        self.assertEqual(len(allowed), len(set(allowed)), "manifest has duplicates")


class DriftDetection(unittest.TestCase):
    def setUp(self):
        self.allowed = sorted(json.loads(guard.CONTRACT.read_text())["allowed"])

    def _run_with(self, live):
        with mock.patch.dict("os.environ", {"SUPABASE_SERVICE_ROLE_KEY": "test-key"}), \
             mock.patch.object(guard, "live_surface", return_value=live):
            return guard.main()

    def test_exact_match_passes(self):
        self.assertEqual(self._run_with(list(self.allowed)), 0)

    def test_order_does_not_matter(self):
        self.assertEqual(self._run_with(list(reversed(self.allowed))), 0)

    def test_new_anon_function_fails(self):
        """The real failure mode: a new function inherits PUBLIC EXECUTE."""
        self.assertEqual(self._run_with(self.allowed + ["tapt_is_na_low"]), 1)

    def test_missing_function_fails(self):
        """Also catch the reverse, so the manifest cannot rot silently."""
        self.assertEqual(self._run_with(self.allowed[:-1]), 1)

    def test_missing_key_skips_on_untrusted_run(self):
        """Fork PRs get no secrets; do not block them on an unrunnable check."""
        with mock.patch.dict("os.environ", {
            "SUPABASE_SERVICE_ROLE_KEY": "", "GITHUB_REF": "refs/pull/7/merge",
            "GITHUB_EVENT_NAME": "pull_request",
        }):
            self.assertEqual(guard.main(), 0)

    def test_missing_key_FAILS_on_main(self):
        """A rotated or renamed secret must not silently disable the guard."""
        with mock.patch.dict("os.environ", {
            "SUPABASE_SERVICE_ROLE_KEY": "", "GITHUB_REF": "refs/heads/main",
            "GITHUB_EVENT_NAME": "push",
        }):
            self.assertEqual(guard.main(), 1)

    def test_missing_key_FAILS_on_scheduled_run(self):
        with mock.patch.dict("os.environ", {
            "SUPABASE_SERVICE_ROLE_KEY": "", "GITHUB_REF": "refs/heads/main",
            "GITHUB_EVENT_NAME": "schedule",
        }):
            self.assertEqual(guard.main(), 1)

    def test_new_overload_of_allowed_name_is_caught(self):
        """The v1 bug: keying on bare names let a new overload of an allowed
        name collapse onto the existing entry and pass green."""
        overload = "public.beer_detail(p_beer_id uuid, p_locale text)"
        self.assertNotIn(overload, self.allowed)
        self.assertEqual(self._run_with(self.allowed + [overload]), 1)

    def test_manifest_entries_are_signatures_not_bare_names(self):
        for name in json.loads(guard.CONTRACT.read_text())["allowed"]:
            self.assertIn("(", name, f"{name} is not a full signature")
            self.assertIn(".", name.split("(")[0], f"{name} is not schema-qualified")

    def test_unreachable_prod_fails_loudly(self):
        with mock.patch.dict("os.environ", {"SUPABASE_SERVICE_ROLE_KEY": "test-key"}), \
             mock.patch.object(guard, "live_surface", side_effect=OSError("network down")):
            self.assertEqual(guard.main(), 1)


if __name__ == "__main__":
    unittest.main()
