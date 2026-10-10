"""Exercise actual CMS/P12 verification and fail-closed single-device checks offline."""
from copy import deepcopy
from datetime import datetime, timedelta
import hashlib
import json
import os
from pathlib import Path
import plistlib
import tempfile
import unittest
from unittest.mock import patch
import zipfile

import direct_iphone as direct

OPENSSL = os.environ.get("GASLEFT_OPENSSL", "openssl")
DEVICE = "A" * 40  # Synthetic fixture, never a real user's device identifier.
PROFILE_ID = "acdcaaaa-1111-2222-3333-aaaaaaaaaaaa"
PASSWORD = "offline-fixture-only"


class DirectSigningTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temporary = tempfile.TemporaryDirectory()
        cls.folder = Path(cls.temporary.name)
        cls.key, cls.cert = cls.folder / "fixture.key", cls.folder / "fixture.pem"
        config = cls.folder / "fixture.cnf"
        config.write_text("[req]\ndistinguished_name=dn\n[dn]\nCN=GasLeft Offline Fixture\n", encoding="ascii")
        direct.run([OPENSSL, "req", "-x509", "-newkey", "rsa:2048", "-nodes", "-days", "2",
                    "-config", config, "-subj", "/CN=GasLeft Offline Fixture", "-keyout", cls.key, "-out", cls.cert])
        cls.der = direct.run([OPENSSL, "x509", "-in", cls.cert, "-outform", "DER"])
        cls.fingerprint = hashlib.sha256(cls.der).hexdigest()
        cls.profile = {
            "UUID": PROFILE_ID, "TeamIdentifier": [direct.TEAM],
            "ExpirationDate": datetime.now() + timedelta(days=1),
            "ProvisionedDevices": [DEVICE], "DeveloperCertificates": [cls.der],
            "Entitlements": {"get-task-allow": False, "application-identifier": f"{direct.TEAM}.{direct.BUNDLE}",
                             "com.apple.developer.team-identifier": direct.TEAM},
        }
        cls.cms = cls.signed(cls.profile)
        p12_path = cls.folder / "fixture.p12"
        direct.run([OPENSSL, "pkcs12", "-export", "-inkey", cls.key, "-in", cls.cert,
                    "-out", p12_path, "-passout", "env:GASLEFT_FIXTURE_PASSWORD"],
                   environ=dict(os.environ, GASLEFT_FIXTURE_PASSWORD=PASSWORD))
        cls.p12 = p12_path.read_bytes()

    @classmethod
    def tearDownClass(cls):
        cls.temporary.cleanup()

    @classmethod
    def signed(cls, profile):
        return direct.run([OPENSSL, "cms", "-sign", "-binary", "-nodetach", "-outform", "DER",
                           "-signer", cls.cert, "-inkey", cls.key], data=plistlib.dumps(profile))

    def setUp(self):
        self.fingerprint_patch = patch.object(direct, "CERT_SHA256", self.fingerprint)
        self.fingerprint_patch.start()
        self.addCleanup(self.fingerprint_patch.stop)

    def test_actual_cms_signature_and_single_device_profile(self):
        profile = direct.decode_profile(self.cms, OPENSSL)
        self.assertEqual(direct.validate_adhoc_profile(profile, DEVICE)[0], PROFILE_ID)

    def test_tampered_cms_content_is_rejected(self):
        changed = self.cms.replace(direct.BUNDLE.encode(), b"com.healthmanagementprepare.changed")
        self.assertNotEqual(changed, self.cms)
        with self.assertRaises(ValueError):
            direct.decode_profile(changed, OPENSSL)

    def test_unsigned_plist_is_rejected(self):
        with self.assertRaises(ValueError):
            direct.decode_profile(plistlib.dumps(self.profile), OPENSSL)

    def test_real_encrypted_p12_key_certificate_and_password(self):
        direct.check_p12(self.p12, PASSWORD, self.profile, OPENSSL)

    def test_wrong_p12_password_does_not_print_credentials(self):
        with self.assertRaises(ValueError) as result:
            direct.check_p12(self.p12, "wrong-private-password", self.profile, OPENSSL)
        self.assertNotIn("wrong-private-password", str(result.exception))

    def test_unapproved_certificate_is_rejected(self):
        with patch.object(direct, "CERT_SHA256", "0" * 64):
            with self.assertRaises(ValueError):
                direct.check_p12(self.p12, PASSWORD, self.profile, OPENSSL)
            with self.assertRaises(ValueError):
                direct.validate_adhoc_profile(self.profile, DEVICE)

    def test_other_team_app_device_and_profile_type_are_rejected(self):
        variants = []
        for field, value in [("TeamIdentifier", ["OTHERTEAM00"]), ("ProvisionedDevices", ["B" * 40]),
                             ("ProvisionedDevices", [DEVICE, "B" * 40]), ("ProvisionsAllDevices", True),
                             ("ExpirationDate", datetime.now() - timedelta(days=1))]:
            item = deepcopy(self.profile)
            item[field] = value
            variants.append(item)
        for field, value in [("get-task-allow", True), ("get-task-allow", None),
                             ("application-identifier", f"{direct.TEAM}.other.app"),
                             ("com.apple.security.application-groups", ["group.other"]),
                             ("com.apple.developer.team-identifier", "OTHERTEAM00")]:
            item = deepcopy(self.profile)
            item["Entitlements"][field] = value
            variants.append(item)
        item = deepcopy(self.profile)
        item.pop("ProvisionedDevices")
        variants.append(item)
        for profile in variants:
            with self.subTest(profileType=list(profile)):
                with self.assertRaises(ValueError):
                    direct.validate_adhoc_profile(profile, DEVICE)

    def ipa(self, *, changes=None, extra=None):
        info = {"CFBundleIdentifier": direct.BUNDLE, "CFBundleShortVersionString": "1.0.0",
                "CFBundleVersion": "1", "MinimumOSVersion": "15.0", "UIDeviceFamily": [1],
                "GADApplicationIdentifier": direct.TEST_APP_ID}
        info.update(changes or {})
        path = self.folder / "fixture.ipa"
        with zipfile.ZipFile(path, "w") as archive:
            archive.writestr("Payload/Runner.app/Info.plist", plistlib.dumps(info))
            archive.writestr("Payload/Runner.app/embedded.mobileprovision", self.cms)
            if extra:
                archive.writestr(extra, b"fixture")
        return path

    def test_ipa_identity_and_signed_profile_are_verified(self):
        self.assertEqual(direct.inspect_ipa(self.ipa(), DEVICE, OPENSSL, "1"), "Runner.app")

    def test_ipa_other_identity_version_and_production_ads_rejected(self):
        for name, value in [("CFBundleIdentifier", "other.app"), ("CFBundleVersion", "2"),
                            ("CFBundleShortVersionString", "2.0"), ("MinimumOSVersion", "12.0"),
                            ("UIDeviceFamily", [1, 2]), ("GADApplicationIdentifier", "production-id")]:
            with self.subTest(name=name):
                with self.assertRaises(ValueError):
                    direct.inspect_ipa(self.ipa(changes={name: value}), DEVICE, OPENSSL, "1")

    def test_extensions_and_unsafe_archive_paths_rejected(self):
        for extra in ["Payload/Runner.app/PlugIns/Other.appex/Info.plist", "../outside", "/outside", r"..\outside"]:
            with self.subTest(extra=extra):
                with self.assertRaises(ValueError):
                    direct.inspect_ipa(self.ipa(extra=extra), DEVICE, OPENSSL, "1")

    def test_preflight_requires_explicit_approval_before_reading_secrets(self):
        with patch.dict(os.environ, {}, clear=True):
            with self.assertRaisesRegex(ValueError, "explicit approval"):
                direct.preflight(OPENSSL)

    def test_actual_installed_build_is_checked_separately(self):
        app = {"CFBundleIdentifier": direct.BUNDLE, "CFBundleVersion": "1", "CFBundleShortVersionString": "1.0.0"}
        direct.validate_installed_apps(plistlib.dumps([app]), "1")
        for data in [[], [dict(app, CFBundleVersion="2")], [app, app], {"not": "a list"}]:
            with self.assertRaises(ValueError):
                direct.validate_installed_apps(plistlib.dumps(data), "1")

    def test_installer_uses_ascii_filename_inside_korean_parent(self):
        parent = self.folder / "아이폰 설치 검증"
        parent.mkdir(exist_ok=True)
        ipa = parent / "gasleft-adhoc-1.ipa"
        ipa.write_bytes(b"verified archive fixture")
        digest = hashlib.sha256(ipa.read_bytes()).hexdigest()
        with patch.object(direct.subprocess, "run") as invoke:
            direct.install_archive(ipa, self.folder, DEVICE)
            args, kwargs = invoke.call_args
            self.assertEqual(args[0][-2:], ["-i", ipa.name])
            self.assertEqual(kwargs["cwd"], parent.resolve())
        self.assertEqual(hashlib.sha256(ipa.read_bytes()).hexdigest(), digest)
        korean_name = parent / "설치.ipa"
        korean_name.write_bytes(b"fixture")
        with patch.object(direct.subprocess, "run") as invoke:
            with self.assertRaises(ValueError):
                direct.install_archive(korean_name, self.folder, DEVICE)
            invoke.assert_not_called()

    def test_actual_resolved_xcode_settings_are_checked(self):
        settings = {"PRODUCT_BUNDLE_IDENTIFIER": direct.BUNDLE, "DEVELOPMENT_TEAM": direct.TEAM,
                    "CODE_SIGN_STYLE": "Manual", "PROVISIONING_PROFILE_SPECIFIER": PROFILE_ID,
                    "FLUTTER_BUILD_NUMBER": "1", "CURRENT_PROJECT_VERSION": "1", "FLUTTER_BUILD_NAME": "1.0.0",
                    "TARGETED_DEVICE_FAMILY": "1", "GAD_APPLICATION_IDENTIFIER": direct.TEST_APP_ID}
        direct.validate_settings([{"target": "Runner", "buildSettings": settings}], PROFILE_ID, "1")
        for field, value in [("CODE_SIGN_STYLE", "Automatic"), ("CODE_SIGNING_ALLOWED", "NO"),
                             ("PROVISIONING_PROFILE_SPECIFIER", "other"), ("FLUTTER_BUILD_NUMBER", "2")]:
            with self.subTest(field=field):
                with self.assertRaises(ValueError):
                    direct.validate_settings([{"target": "Runner", "buildSettings": dict(settings, **{field: value})}], PROFILE_ID, "1")

    def test_changed_asset_and_untracked_app_code_are_rejected(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            for directory in ["lib", "assets", "design_assets", "test", "ios/Runner"]:
                (root / directory).mkdir(parents=True)
            for name in ["pubspec.yaml", "pubspec.lock", "assets/icon.png", "lib/main.dart"]:
                (root / name).write_bytes(b"fixture")
            lock = root / "lock.json"
            with patch.object(direct, "ROOT", root), patch.object(direct, "LOCK_PATH", lock):
                lock.write_text(json.dumps(direct.source_files()), encoding="utf-8")
                direct.verify_source()
                (root / "assets/icon.png").write_bytes(b"changed")
                with self.assertRaises(ValueError):
                    direct.verify_source()
                (root / "assets/icon.png").write_bytes(b"fixture")
                (root / "lib/new.dart").write_bytes(b"unexpected")
                with self.assertRaises(ValueError):
                    direct.verify_source()


if __name__ == "__main__":
    unittest.main(verbosity=2)
