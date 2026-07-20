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

    def test_manifest_names_look_like_identifiers(self):
        for name in json.loads(guard.CONTRACT.read_text())["allowed"]:
            self.assertRegex(name, r"^[a-z_][a-z0-9_]*$", f"suspicious name: {name}")


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

    def test_missing_key_skips_rather_than_fails(self):
        with mock.patch.dict("os.environ", {"SUPABASE_SERVICE_ROLE_KEY": ""}):
            self.assertEqual(guard.main(), 0)

    def test_unreachable_prod_fails_loudly(self):
        with mock.patch.dict("os.environ", {"SUPABASE_SERVICE_ROLE_KEY": "test-key"}), \
             mock.patch.object(guard, "live_surface", side_effect=OSError("network down")):
            self.assertEqual(guard.main(), 1)


if __name__ == "__main__":
    unittest.main()
