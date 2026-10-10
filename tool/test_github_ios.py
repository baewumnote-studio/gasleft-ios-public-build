"""Offline checks for signing mismatches and account/cost-sensitive CI inputs."""
from datetime import datetime, timedelta, timezone
import hashlib
from pathlib import Path
import unittest

from github_ios import patch_release_signing, validate_inputs, validate_profile

NOW = datetime(2026, 10, 10, tzinfo=timezone.utc)
BUNDLE = "com.healthmanagementprepare.gasleft"
TEAM = "39762JRYD4"
PROFILE_ID = "acdcaaaa-1111-2222-3333-aaaaaaaaaaaa"
CERTIFICATE = b"offline-test-certificate"
IDENTITY = hashlib.sha1(CERTIFICATE).hexdigest().upper()


def inputs():
    return {
        "GASLEFT_TARGET": "testflight", "GASLEFT_UPLOAD": "false",
        "GASLEFT_APPLE_ACCOUNT_READY": "true", "GASLEFT_BUILD_NUMBER": "1",
        "BUNDLE_ID": BUNDLE, "DEVELOPMENT_TEAM": TEAM, "APP_STORE_APPLE_ID": "1234567890",
        "PRIVACY_POLICY_URL": "https://example.org/gasleft/privacy", "SUPPORT_EMAIL": "support@example.org",
        "ADMOB_USE_TEST_ADS": "true", "GASLEFT_P12_BASE64": "Zml4dHVyZQ==",
        "GASLEFT_P12_PASSWORD": "offline-fixture", "GASLEFT_PROFILE_BASE64": "Zml4dHVyZQ==",
    }


def profile():
    return {
        "TeamIdentifier": [TEAM], "UUID": PROFILE_ID, "ExpirationDate": NOW + timedelta(days=1),
        "DeveloperCertificates": [CERTIFICATE],
        "Entitlements": {
            "application-identifier": f"{TEAM}.{BUNDLE}",
            "com.apple.developer.team-identifier": TEAM, "get-task-allow": False,
        },
    }


class GitHubIosTests(unittest.TestCase):
    def test_simulator_needs_no_apple_account(self):
        validate_inputs({"GASLEFT_TARGET": "simulator"}, now=NOW)

    def test_simulator_cannot_upload(self):
        with self.assertRaisesRegex(ValueError, "simulator"):
            validate_inputs({"GASLEFT_TARGET": "simulator", "GASLEFT_UPLOAD": "true"}, now=NOW)

    def test_apple_work_is_blocked_before_requested_time(self):
        with self.assertRaisesRegex(ValueError, "14:00 KST"):
            validate_inputs(inputs(), now=datetime(2026, 10, 9, 4, 59, tzinfo=timezone.utc))

    def test_account_readiness_and_missing_signing_material_block_build(self):
        for key in ["GASLEFT_APPLE_ACCOUNT_READY", "GASLEFT_P12_BASE64", "GASLEFT_PROFILE_BASE64"]:
            with self.subTest(key=key), self.assertRaises(ValueError):
                data = inputs()
                data[key] = ""
                validate_inputs(data, now=NOW)

    def test_build_only_works_without_upload_credentials(self):
        validate_inputs(inputs(), now=NOW)
        data = inputs()
        data["GASLEFT_UPLOAD"] = "true"
        with self.assertRaisesRegex(ValueError, "GASLEFT_ASC_KEY_ID"):
            validate_inputs(data, now=NOW)

    def test_shell_like_build_number_is_rejected(self):
        data = inputs()
        data["GASLEFT_BUILD_NUMBER"] = "1; whoami"
        with self.assertRaisesRegex(ValueError, "build number"):
            validate_inputs(data, now=NOW)

    def test_profile_matches_exact_app_team_and_certificate(self):
        self.assertEqual(validate_profile(profile(), BUNDLE, TEAM, now=NOW), (PROFILE_ID, {IDENTITY}))

    def test_wrong_app_team_expiration_and_distribution_type_are_rejected(self):
        variations = []
        for key, value in [
            ("TeamIdentifier", ["AAAAAAAAAA"]), ("ExpirationDate", NOW - timedelta(seconds=1)),
            ("ProvisionedDevices", ["fixture-udid"]), ("ProvisionsAllDevices", True),
            ("DeveloperCertificates", []),
        ]:
            data = profile()
            data[key] = value
            variations.append(data)
        for key, value in [("application-identifier", f"{TEAM}.com.other.app"), ("application-identifier", f"{TEAM}.*"), ("get-task-allow", True)]:
            data = profile()
            data["Entitlements"][key] = value
            variations.append(data)
        for index, data in enumerate(variations):
            with self.subTest(index=index), self.assertRaises(ValueError):
                validate_profile(data, BUNDLE, TEAM, now=NOW)

    def test_only_runner_release_gets_manual_signing(self):
        path = Path(__file__).resolve().parents[1] / "ios/Runner.xcodeproj/project.pbxproj"
        source = path.read_text(encoding="utf-8").replace("com.example.gasleft", BUNDLE)
        patched = patch_release_signing(source, BUNDLE, PROFILE_ID, IDENTITY)
        self.assertEqual(patched.count("CODE_SIGN_STYLE = Manual;"), 1)
        self.assertEqual(patched.count(f'PROVISIONING_PROFILE_SPECIFIER = "{PROFILE_ID}";'), 1)
        self.assertEqual(patched.count("CODE_SIGN_STYLE = Automatic;"), source.count("CODE_SIGN_STYLE = Automatic;"))
        self.assertEqual(patched.count(BUNDLE + ".RunnerTests;"), 3)
        again = patch_release_signing(patched, BUNDLE, PROFILE_ID, IDENTITY)
        self.assertEqual(again.count("CODE_SIGN_STYLE = Manual;"), 1)
        with self.assertRaisesRegex(ValueError, "exactly one"):
            patch_release_signing(source, "com.unknown.app", PROFILE_ID, IDENTITY)


if __name__ == "__main__":
    unittest.main(verbosity=2)
