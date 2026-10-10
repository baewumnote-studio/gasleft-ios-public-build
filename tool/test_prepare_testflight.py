"""Offline configuration checks. Fixture values are not publisher identities."""
import unittest
from prepare_testflight import publisher_inputs, TEST_APP_ID, TEST_AD_ID


class PublisherInputTests(unittest.TestCase):
    def setUp(self):
        self.environ = {
            "BUNDLE_ID": "org.fixture.gasleft",
            "APP_STORE_APPLE_ID": "1234567890",
            "DEVELOPMENT_TEAM": "ABCDE12345",
            "PRIVACY_POLICY_URL": "https://example.org/gasleft/privacy",
            "SUPPORT_EMAIL": "support@example.org",
            "ADMOB_USE_TEST_ADS": "true",
        }

    def test_beta_does_not_require_or_borrow_production_ad_ids(self):
        config = publisher_inputs(self.environ)
        self.assertEqual(config["admob_app_id"], TEST_APP_ID)
        self.assertEqual(config["defines"]["ADMOB_INTERSTITIAL_IOS"], TEST_AD_ID)

    def test_beta_still_blocks_missing_apple_identity_and_contacts(self):
        for name in ["APP_STORE_APPLE_ID", "BUNDLE_ID", "DEVELOPMENT_TEAM", "PRIVACY_POLICY_URL", "SUPPORT_EMAIL"]:
            with self.subTest(name=name):
                invalid = dict(self.environ, **{name: "__SET_VALUE__"})
                with self.assertRaisesRegex(ValueError, name):
                    publisher_inputs(invalid)

    def test_production_does_not_accept_sample_ads(self):
        self.environ.update({
            "ADMOB_USE_TEST_ADS": "false",
            "GAD_APPLICATION_IDENTIFIER": TEST_APP_ID,
            "ADMOB_INTERSTITIAL_IOS": TEST_AD_ID,
        })
        with self.assertRaisesRegex(ValueError, "production"):
            publisher_inputs(self.environ)


if __name__ == "__main__":
    unittest.main()
