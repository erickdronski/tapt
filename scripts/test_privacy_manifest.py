import plistlib
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
PRIVACY_MANIFEST = REPO_ROOT / "app" / "Tapt" / "PrivacyInfo.xcprivacy"
INFO_PLIST = REPO_ROOT / "app" / "Tapt" / "Info.plist"


class PrivacyManifestTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        with PRIVACY_MANIFEST.open("rb") as handle:
            cls.manifest = plistlib.load(handle)
        with INFO_PLIST.open("rb") as handle:
            cls.info_plist = plistlib.load(handle)

    def test_collected_data_matches_release_disclosure(self):
        entries = self.manifest["NSPrivacyCollectedDataTypes"]
        actual = [entry["NSPrivacyCollectedDataType"] for entry in entries]
        expected = {
            "NSPrivacyCollectedDataTypeAdvertisingData",
            "NSPrivacyCollectedDataTypeCoarseLocation",
            "NSPrivacyCollectedDataTypeEmailAddress",
            "NSPrivacyCollectedDataTypeName",
            "NSPrivacyCollectedDataTypeOtherDiagnosticData",
            "NSPrivacyCollectedDataTypeOtherUserContent",
            "NSPrivacyCollectedDataTypePhotosorVideos",
            "NSPrivacyCollectedDataTypePreciseLocation",
            "NSPrivacyCollectedDataTypeProductInteraction",
            "NSPrivacyCollectedDataTypeUserID",
        }

        self.assertEqual(set(actual), expected)
        self.assertEqual(len(actual), len(expected), "Privacy data types must be unique")

    def test_collected_data_is_linked_but_not_used_for_tracking(self):
        for entry in self.manifest["NSPrivacyCollectedDataTypes"]:
            self.assertTrue(entry["NSPrivacyCollectedDataTypeLinked"])
            self.assertFalse(entry["NSPrivacyCollectedDataTypeTracking"])
            self.assertTrue(entry["NSPrivacyCollectedDataTypePurposes"])

        self.assertFalse(self.manifest["NSPrivacyTracking"])
        self.assertEqual(self.manifest["NSPrivacyTrackingDomains"], [])

    def test_app_does_not_request_address_book_access(self):
        self.assertNotIn("NSContactsUsageDescription", self.info_plist)


if __name__ == "__main__":
    unittest.main()
