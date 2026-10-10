"""Reject untrusted signing requests and accidental public credential/output paths."""
import json
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

import public_ios as public


class PublicBuildSecurityTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.event = Path(self.temp.name) / 'event.json'
        self.event.write_text(json.dumps({'repository': {'private': False}}))
        self.env = {'GITHUB_EVENT_NAME': 'workflow_dispatch', 'GITHUB_REPOSITORY': public.BUILD_REPO,
                    'GITHUB_REF': 'refs/heads/main', 'GITHUB_ACTOR': 'baewumnote-studio',
                    'GITHUB_TRIGGERING_ACTOR': 'baewumnote-studio', 'GITHUB_EVENT_PATH': str(self.event),
                    'GASLEFT_MODE': 'unsigned', 'GASLEFT_BUILD_NUMBER': '1', 'ADMOB_USE_TEST_ADS': 'true',
                    'GITHUB_SHA': 'a' * 40, 'GASLEFT_UNSIGNED_VERIFIED_SHA': ''}

    def test_untrusted_pr_actor_repository_and_branch_cannot_reach_signing(self):
        with patch.object(public.direct, 'verify_source') as source:
            public.guard(self.env)
            for field, value in [('GITHUB_EVENT_NAME', 'pull_request'), ('GITHUB_EVENT_NAME', 'pull_request_target'),
                                 ('GITHUB_REPOSITORY', 'attacker/gasleft'), ('GITHUB_REF', 'refs/heads/feature'),
                                 ('GITHUB_ACTOR', 'external-user'), ('GITHUB_TRIGGERING_ACTOR', 'external-user')]:
                source.reset_mock()
                with self.subTest(field=field, value=value), self.assertRaises(ValueError):
                    public.guard(dict(self.env, **{field: value}))
                source.assert_not_called()

    def test_private_staging_cannot_consume_paid_or_limited_runner_minutes(self):
        self.event.write_text(json.dumps({'repository': {'private': True}}))
        with self.assertRaises(ValueError):
            public.guard(self.env)

    def test_signing_requires_successful_unsigned_compilation_of_exact_commit(self):
        env = dict(self.env, GASLEFT_MODE='adhoc')
        with patch.object(public.direct, 'verify_source'):
            with self.assertRaises(ValueError):
                public.guard(env)
            with self.assertRaises(ValueError):
                public.guard(dict(env, GASLEFT_UNSIGNED_VERIFIED_SHA='b' * 40))
            public.guard(dict(env, GASLEFT_UNSIGNED_VERIFIED_SHA='a' * 40))

    def test_direct_device_build_rejects_live_ads_and_invalid_build_numbers(self):
        with patch.object(public.direct, 'verify_source'):
            for change in [{'ADMOB_USE_TEST_ADS': 'false'}, {'GASLEFT_BUILD_NUMBER': '0'},
                           {'GASLEFT_BUILD_NUMBER': '../ipa'}, {'GASLEFT_MODE': 'public-ipa'}]:
                with self.subTest(change=change), self.assertRaises(ValueError):
                    public.guard(dict(self.env, **change))

    def test_vault_requires_exact_private_writable_repository_before_upload(self):
        expected = {'full_name': public.VAULT_REPO, 'private': True, 'permissions': {'push': True}}
        for change in [{'private': False}, {'full_name': 'other/private'}, {'permissions': {'push': False}}]:
            with patch.object(public, 'vault_api', return_value=dict(expected, **change)):
                with self.assertRaises(ValueError):
                    public.private_vault()
        with patch.object(public, 'vault_api', return_value=expected):
            public.private_vault()

    def test_missing_private_token_stops_before_network(self):
        with patch.dict(os.environ, {}, clear=True), patch.object(public, 'build_opener') as network:
            with self.assertRaises(ValueError):
                public.vault_api('repos/' + public.VAULT_REPO)
            network.assert_not_called()

    def test_credential_redirects_are_blocked(self):
        with self.assertRaises(ValueError):
            public.NoCredentialRedirect().redirect_request(None, None, 302, '', {}, 'https://external.invalid/')


if __name__ == '__main__':
    unittest.main(verbosity=2)
