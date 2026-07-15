import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]


class ReleaseContractTests(unittest.TestCase):
    def test_review_demo_account_is_required_and_secret_backed(self):
        prepare = (REPO_ROOT / "scripts" / "asc_release_prepare.py").read_text()
        audit = (REPO_ROOT / "scripts" / "asc_release_audit.py").read_text()
        workflow = (
            REPO_ROOT / ".github" / "workflows" / "asc-release-prepare.yml"
        ).read_text()

        required = (
            "ASC_REVIEW_FIRST_NAME",
            "ASC_REVIEW_LAST_NAME",
            "ASC_REVIEW_EMAIL",
            "ASC_REVIEW_PHONE",
            "ASC_DEMO_ACCOUNT_NAME",
            "ASC_DEMO_ACCOUNT_PASSWORD",
        )
        for secret in required:
            self.assertIn(secret, prepare)
            self.assertIn(f"secrets.{secret}", workflow)

        self.assertIn('"demoAccountRequired": True', prepare)
        self.assertNotIn('"demoAccountRequired": False', prepare)
        self.assertIn("must be configured with an active demo account", audit)

    def test_device_build_exposes_password_sign_in(self):
        sign_in = (
            REPO_ROOT / "app" / "Tapt" / "Features" / "Auth" / "SignInView.swift"
        ).read_text()
        session = (REPO_ROOT / "app" / "Tapt" / "Core" / "Session.swift").read_text()

        self.assertIn('"Sign in with password"', sign_in)
        self.assertIn("session.signInWithPassword", sign_in)
        self.assertIn("func signInWithPassword", session)


if __name__ == "__main__":
    unittest.main()
