"""GasLeft single-device Ad Hoc checks; private identifiers never enter logs."""
from __future__ import annotations

import argparse
import base64
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import plistlib
import re
import subprocess
import sys
import tempfile
import zipfile

from github_ios import ROOT, patch_release_signing, validate_profile
from prepare_testflight import TEST_APP_ID, TEST_AD_ID

BUNDLE = "com.healthmanagementprepare.gasleft"
TEAM = "39762JRYD4"
CERT_SHA256 = "faa9fe5ba226b207869a5070716bfb41aa9b95f250c374a4ddffbcb996c981fc"
UDID_PATTERN = r"(?:[a-fA-F0-9]{40}|[a-fA-F0-9]{8}-[a-fA-F0-9]{16})"
LOCK_PATH = ROOT / "verification/direct/source_lock.json"


def run(command, *, data=None, environ=None, timeout=30):
    result = subprocess.run([str(value) for value in command], input=data,
                            env=environ, capture_output=True, timeout=timeout)
    if result.returncode:
        # CalledProcessError includes command arguments (possibly the UDID).
        executable = Path(str(command[0])).stem
        detail = ""
        if executable == "codesign":
            detail = ": " + redact(result.stderr.decode(errors="replace"))[-2000:]
        raise ValueError(f"{executable} command failed (exit {result.returncode}); private arguments were not printed{detail}")
    return result.stdout


def redact(text):
    return re.sub(UDID_PATTERN, "[registered iPhone]", text)


def read_device(tools, destination):
    devices = run([tools / "idevice_id.exe", "-l"]).decode().splitlines()
    devices = [value.strip() for value in devices if re.fullmatch(UDID_PATTERN, value.strip())]
    if len(devices) != 1:
        raise ValueError("Connect one iPhone, unlock it and complete Trust on the phone.")
    udid = devices[0]
    values = {}
    for key in ["ProductType", "ProductVersion", "UniqueDeviceID"]:
        values[key] = run([tools / "ideviceinfo.exe", "-u", udid, "-k", key]).decode().strip()
    if values["UniqueDeviceID"].upper() != udid.upper():
        raise ValueError("The live Apple device identifier does not match the connection service.")
    if not re.fullmatch(r"iPhone\d+,\d+", values["ProductType"]) or not re.fullmatch(r"\d+(?:\.\d+){1,2}", values["ProductVersion"]):
        raise ValueError("The Apple service did not return valid iPhone model/OS information.")
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_text(json.dumps({
        "udid": udid, "productType": values["ProductType"], "iosVersion": values["ProductVersion"],
        "readAtUtc": datetime.now(timezone.utc).isoformat(), "readFromLiveAppleService": True,
        "purpose": "GasLeft single-device Ad Hoc installation",
    }, indent=2) + "\n", encoding="utf-8")
    print(f"PASS: live {values['ProductType']}, iOS {values['ProductVersion']}; identifier saved privately.")


def validate_adhoc_profile(profile, udid, now=None):
    if not isinstance(udid, str) or not re.fullmatch(UDID_PATTERN, udid):
        raise ValueError("A live, valid iPhone identifier is required.")
    if profile.get("Entitlements", {}).get("get-task-allow") is not False:
        raise ValueError("The Ad Hoc profile must disable debugging.")
    devices = profile.get("ProvisionedDevices")
    if not isinstance(devices, list) or len(devices) != 1 or not isinstance(devices[0], str) or devices[0].upper() != udid.upper():
        raise ValueError("The Ad Hoc profile must include only the recorded iPhone.")
    groups = profile.get("Entitlements", {}).get("com.apple.security.application-groups", [])
    if groups:
        raise ValueError("GasLeft has no App Group or sharing extension.")
    plain = dict(profile)
    plain.pop("ProvisionedDevices")
    identifier, identities = validate_profile(plain, BUNDLE, TEAM, now=now)
    matching = [value for value in profile["DeveloperCertificates"] if hashlib.sha256(value).hexdigest() == CERT_SHA256]
    if len(matching) != 1:
        raise ValueError("Use the existing distribution certificate confirmed for this Apple team.")
    return identifier, identities


def decode_profile(data, openssl):
    # Verify the CMS content signature. Apple signer chain trust is not asserted
    # by -noverify; the profile must also originate from the authenticated account.
    decoded = run([openssl, "cms", "-verify", "-noverify", "-inform", "DER"], data=data)
    return plistlib.loads(decoded)


def check_p12(data, password, profile, openssl):
    with tempfile.TemporaryDirectory(dir=os.environ.get("RUNNER_TEMP")) as folder:
        path = Path(folder) / "existing.p12"
        path.write_bytes(data)
        path.chmod(0o600)
        environment = dict(os.environ, GASLEFT_P12_PASSWORD=password)
        base = [openssl, "pkcs12", "-in", path, "-passin", "env:GASLEFT_P12_PASSWORD"]
        legacy = []
        try:
            certificate = run(base + ["-clcerts", "-nokeys"], environ=environment)
        except ValueError:
            legacy = ["-legacy"]
            certificate = run(base + legacy + ["-clcerts", "-nokeys"], environ=environment)
        der = run([openssl, "x509", "-outform", "DER"], data=certificate)
        if hashlib.sha256(der).hexdigest() != CERT_SHA256 or der not in profile["DeveloperCertificates"]:
            raise ValueError("The P12 certificate differs from the existing certificate or GasLeft profile.")
        run([openssl, "x509", "-checkend", "86400", "-noout"], data=certificate)
        private = run(base + legacy + ["-nocerts", "-nodes"], environ=environment)
        private_public = run([openssl, "pkey", "-pubout", "-outform", "DER"], data=private)
        certificate_public = run([openssl, "x509", "-pubkey", "-noout"], data=certificate)
        certificate_public = run([openssl, "pkey", "-pubin", "-outform", "DER"], data=certificate_public)
        if private_public != certificate_public:
            raise ValueError("The P12 private key does not match its certificate.")


def source_files():
    paths = []
    for directory in ["lib", "assets", "design_assets", "test", "ios/Runner"]:
        paths += [path for path in (ROOT / directory).rglob("*") if path.is_file() and path.name not in {"GeneratedPluginRegistrant.h", "GeneratedPluginRegistrant.m"}]
    paths += [ROOT / "pubspec.yaml", ROOT / "pubspec.lock"]
    return {path.relative_to(ROOT).as_posix(): hashlib.sha256(path.read_bytes()).hexdigest() for path in sorted(paths)}


def verify_source():
    baseline = json.loads(LOCK_PATH.read_text(encoding="utf-8"))
    if baseline != source_files():
        raise ValueError("Approved GasLeft app source, tests, fonts or artwork changed; review the baseline before building.")


def preflight(openssl):
    if os.environ.get("GASLEFT_DIRECT_INSTALL_APPROVED") != "true":
        raise ValueError("App registration and private GitHub signing transfer need explicit approval first.")
    if os.environ.get("ADMOB_USE_TEST_ADS") != "true":
        raise ValueError("Direct iPhone testing must use the approved Google test ads.")
    number = os.environ.get("GASLEFT_BUILD_NUMBER", "")
    if not re.fullmatch(r"[1-9][0-9]{0,8}", number):
        raise ValueError("Choose a positive build number.")
    verify_source()
    udid = os.environ["GASLEFT_ADHOC_DEVICE_UDID"]
    profile_data = base64.b64decode("".join(os.environ["GASLEFT_ADHOC_PROFILE_BASE64"].split()), validate=True)
    profile = decode_profile(profile_data, openssl)
    validate_adhoc_profile(profile, udid)
    p12 = base64.b64decode("".join(os.environ["GASLEFT_P12_BASE64"].split()), validate=True)
    check_p12(p12, os.environ["GASLEFT_P12_PASSWORD"], profile, openssl)
    print("PASS: source preserved; CMS signature, exact device/team/app, expiry and existing P12/private key verified.")


def configure():
    from urllib.parse import urlparse
    privacy = os.environ["GASLEFT_PRIVACY_URL"]
    parsed = urlparse(privacy)
    if parsed.scheme != "https" or not parsed.hostname or parsed.username or parsed.password:
        raise ValueError("Use the published GasLeft HTTPS privacy page.")
    from urllib.request import Request, urlopen
    request = Request(privacy, headers={"User-Agent": "GasLeft-privacy-verification/1.0"})
    with urlopen(request, timeout=20) as response:
        final = urlparse(response.geturl())
        if (response.status != 200 or final.scheme != "https" or final.hostname != parsed.hostname
                or "gasleft privacy policy" not in response.read(512000).decode(errors="replace").lower()):
            raise ValueError("The published privacy page does not identify GasLeft.")
    sys.path.insert(0, str(ROOT / "tools"))
    import assemble_flutter_ios as assembler
    assembler.patch_runner_project(ROOT, bundle_id=BUNDLE, development_team=TEAM)
    assembler.patch_xcconfigs(ROOT, TEST_APP_ID)
    folder = ROOT / "build/gasleft"
    folder.mkdir(parents=True, exist_ok=True)
    (folder / "release_dart_defines.json").write_text(json.dumps({
        "ADMOB_USE_TEST_ADS": "true", "ADMOB_INTERSTITIAL_IOS": TEST_AD_ID,
        "PRIVACY_POLICY_URL": privacy, "SUPPORT_EMAIL": "healthmanagementprepare@gmail.com",
    }, indent=2), encoding="utf-8")


def sign(openssl):
    temporary = Path(os.environ["RUNNER_TEMP"])
    profile_data = base64.b64decode("".join(os.environ["GASLEFT_ADHOC_PROFILE_BASE64"].split()), validate=True)
    profile = decode_profile(profile_data, openssl)
    profile_id, allowed = validate_adhoc_profile(profile, os.environ["GASLEFT_ADHOC_DEVICE_UDID"])
    keychain = temporary / "gasleft-signing.keychain-db"
    found = run(["security", "find-identity", "-v", "-p", "codesigning", keychain]).decode()
    expected_identity = next(hashlib.sha1(value).hexdigest().upper() for value in profile["DeveloperCertificates"] if hashlib.sha256(value).hexdigest() == CERT_SHA256)
    if expected_identity not in allowed or expected_identity not in set(re.findall(r"\b[A-Fa-f0-9]{40}\b", found.upper())):
        raise ValueError("The imported keychain has no valid matching distribution private key.")
    project = ROOT / "ios/Runner.xcodeproj/project.pbxproj"
    project.write_text(patch_release_signing(project.read_text(encoding="utf-8"), BUNDLE, profile_id, expected_identity), encoding="utf-8")
    for directory in [Path.home() / "Library/MobileDevice/Provisioning Profiles", Path.home() / "Library/Developer/Xcode/UserData/Provisioning Profiles"]:
        directory.mkdir(parents=True, exist_ok=True)
        (directory / f"{profile_id}.mobileprovision").write_bytes(profile_data)
    (temporary / "gasleft-profile-id.txt").write_text(profile_id, encoding="ascii")
    (ROOT / "build/gasleft/ExportOptions.plist").write_bytes(plistlib.dumps({
        "method": "release-testing", "destination": "export", "signingStyle": "manual",
        "teamID": TEAM, "signingCertificate": expected_identity,
        "provisioningProfiles": {BUNDLE: profile_id},
        "manageAppVersionAndBuildNumber": False, "uploadSymbols": False,
    }))
    print("PASS: existing identity and exact Ad Hoc profile selected for Runner Release.")


def inspect_ipa(path, udid, openssl, number):
    with zipfile.ZipFile(path) as archive:
        names = archive.namelist()
        infos = [name for name in names if name.startswith("Payload/") and name.endswith(".app/Info.plist") and name.count("/") == 2]
        if len(infos) != 1 or any(".appex/Info.plist" in name for name in names):
            raise ValueError("Expected one GasLeft app and no sharing extension.")
        info = plistlib.loads(archive.read(infos[0]))
        if (info.get("CFBundleIdentifier") != BUNDLE or info.get("CFBundleShortVersionString") != "1.0.0"
                or info.get("CFBundleVersion") != str(number) or info.get("MinimumOSVersion") != "15.0"
                or info.get("UIDeviceFamily") != [1] or info.get("GADApplicationIdentifier") != TEST_APP_ID):
            raise ValueError("Exported GasLeft identity/version/iPhone settings/test ads do not match.")
        validate_adhoc_profile(decode_profile(archive.read(infos[0].removesuffix("Info.plist") + "embedded.mobileprovision"), openssl), udid)
        if any(PurePosixPath(name).is_absolute() or ".." in PurePosixPath(name).parts or "\\" in name for name in names):
            raise ValueError("Unsafe archive path.")
        return infos[0].split("/")[1]


def validate_settings(entries, profile_id, number):
    matches = [item["buildSettings"] for item in entries if item.get("target") == "Runner" or item.get("buildSettings", {}).get("TARGET_NAME") == "Runner"]
    if not matches or any(value != matches[0] for value in matches[1:]):
        raise ValueError("Runner is missing or has conflicting resolved Release settings.")
    expected = {"PRODUCT_BUNDLE_IDENTIFIER": BUNDLE, "DEVELOPMENT_TEAM": TEAM, "CODE_SIGN_STYLE": "Manual",
                "PROVISIONING_PROFILE_SPECIFIER": profile_id, "FLUTTER_BUILD_NUMBER": str(number),
                "CURRENT_PROJECT_VERSION": str(number), "FLUTTER_BUILD_NAME": "1.0.0", "TARGETED_DEVICE_FAMILY": "1",
                "GAD_APPLICATION_IDENTIFIER": TEST_APP_ID}
    if any(str(matches[0].get(key)) != value for key, value in expected.items()) or matches[0].get("CODE_SIGNING_ALLOWED") == "NO":
        raise ValueError("Resolved Release settings differ from the approved app/profile/build/test-ad configuration.")


def check_settings(number):
    temporary = Path(os.environ["RUNNER_TEMP"])
    profile_id = (temporary / "gasleft-profile-id.txt").read_text(encoding="ascii")
    entries = json.loads(run(["xcodebuild", "-workspace", ROOT / "ios/Runner.xcworkspace", "-scheme", "Runner",
                             "-configuration", "Release", "-sdk", "iphoneos", "-showBuildSettings", "-json"], timeout=60))
    validate_settings(entries, profile_id, number)
    print("PASS: actual Runner Release settings match the approved profile, app, version and test ads.")


def verify_mac(path, openssl, number):
    app_name = inspect_ipa(path, os.environ["GASLEFT_ADHOC_DEVICE_UDID"], openssl, number)
    print("PASS: exported IPA identity and signed device profile verified.", flush=True)
    with tempfile.TemporaryDirectory(dir=os.environ.get("RUNNER_TEMP")) as folder:
        temporary = Path(folder)
        run(["ditto", "-x", "-k", path, temporary])
        app = temporary / "Payload" / app_name
        run(["codesign", "--verify", "--deep", "--strict", app], timeout=60)
        print("PASS: exported app's complete code signature verified.", flush=True)
        prefix = temporary / "signer"
        # codesign's prefix is an optional long-option argument and must be
        # attached with '='; a separate path is interpreted as another app.
        run(["codesign", "-d", f"--extract-certificates={prefix}", app])
        if hashlib.sha256(Path(str(prefix) + "0").read_bytes()).hexdigest() != CERT_SHA256:
            raise ValueError("The exported app was signed by a different certificate.")
    archive_root = ROOT / "build/ios/archive"
    archived_apps = list(archive_root.glob("*.xcarchive/Products/Applications/*.app"))
    if len(archived_apps) != 1:
        raise ValueError("Keep exactly one original GasLeft xcarchive.")
    archived_info = plistlib.loads((archived_apps[0] / "Info.plist").read_bytes())
    if archived_info.get("CFBundleIdentifier") != BUNDLE or archived_info.get("CFBundleVersion") != str(number):
        raise ValueError("The original archive identity/build number differs from the IPA.")
    report = {"ipaSha256": hashlib.sha256(path.read_bytes()).hexdigest(), "certificateSha256": CERT_SHA256,
              "bundleId": BUNDLE, "version": "1.0.0", "buildNumber": str(number), "codesignVerifiedOnMac": True,
              "originalArchivePreserved": True, "singleRecordedDeviceMatched": True, "testAds": True}
    (ROOT / "build/gasleft/ipa-verification.json").write_text(json.dumps(report, indent=2), encoding="utf-8")
    print("PASS: signed exported IPA and original xcarchive verified; private verification report written.")


def validate_installed_apps(data, number):
    apps = plistlib.loads(data)
    if not isinstance(apps, list):
        raise ValueError("The Apple service did not return an installed-app list.")
    matching = [app for app in apps if isinstance(app, dict) and app.get("CFBundleIdentifier") == BUNDLE]
    if len(matching) != 1 or matching[0].get("CFBundleVersion") != str(number) or matching[0].get("CFBundleShortVersionString") != "1.0.0":
        raise ValueError("The connected iPhone does not report the expected installed GasLeft build.")


def install(path, device_file, tools, number, report_path, check_only):
    device = json.loads(device_file.read_text(encoding="utf-8-sig"))
    if device.get("readFromLiveAppleService") is not True:
        raise ValueError("Read the identifier from the live Apple service first.")
    udid = device["udid"]
    inspect_ipa(path, udid, tools / "openssl.exe", number)
    report = json.loads(report_path.read_text(encoding="utf-8"))
    if (report.get("ipaSha256") != hashlib.sha256(path.read_bytes()).hexdigest()
            or report.get("certificateSha256") != CERT_SHA256 or report.get("bundleId") != BUNDLE
            or report.get("codesignVerifiedOnMac") is not True or report.get("originalArchivePreserved") is not True):
        raise ValueError("The downloaded IPA must match the successful private Mac verification artifact.")
    if check_only:
        print("PASS: downloaded IPA, actual certificate, device/profile and private build report match.")
        return
    help_text = run([tools / "ideviceinstaller.exe", "--help"]).decode(errors="replace")
    if "-i" not in help_text or "install" not in help_text.lower():
        raise ValueError("Installer command syntax is not the previously inspected -i interface.")
    live = run([tools / "idevice_id.exe", "-l"]).decode().splitlines()
    if len(live) != 1 or live[0].strip().upper() != udid.upper():
        raise ValueError("Connect only the recorded, unlocked iPhone before installation.")
    run([tools / "ideviceinfo.exe", "-u", udid, "-k", "ProductType"])
    result = install_archive(path, tools, udid)
    output = redact((result.stdout + result.stderr).decode(errors="replace"))
    log = ROOT / ".local/iphone-install.log"
    log.write_text(output, encoding="utf-8")
    print(output[-2000:])
    if result.returncode or not re.search(r"Complete|Success", output, re.I):
        raise ValueError("Installation did not report completion; the existing app was not removed.")
    installed = run([tools / "ideviceinstaller.exe", "-u", udid, "-l", "-o", "list_user", "-o", "xml"], timeout=60)
    validate_installed_apps(installed, number)
    (ROOT / ".local/installation-result.json").write_text(json.dumps({
        "bundleId": BUNDLE, "version": "1.0.0", "buildNumber": str(number),
        "installedAtUtc": datetime.now(timezone.utc).isoformat(), "deviceServiceConfirmedInstalledBuild": True,
        "appLaunchConfirmed": False, "functionalTestsConfirmed": False,
    }, indent=2) + "\n", encoding="utf-8")
    print("Installation completed. App launch and functional tests still require confirmation on the iPhone.")


def install_archive(path, tools, udid):
    # libzip in installer 1.1.1 cannot open a Korean absolute IPA path.
    # Keep the validated file in its existing parent and pass its ASCII name.
    path = path.resolve(strict=True)
    if not path.name.isascii():
        raise ValueError("Use an ASCII IPA filename in the existing verified parent directory.")
    return subprocess.run([str((tools / "ideviceinstaller.exe").resolve()), "-u", udid, "-i", path.name],
                          cwd=path.parent, capture_output=True, timeout=120)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=["read-device", "lock-source", "check-source", "preflight", "configure", "sign", "settings", "verify-mac", "install"])
    parser.add_argument("--tools", type=Path)
    parser.add_argument("--device-file", type=Path, default=ROOT / ".local/iphone-device.json")
    parser.add_argument("--ipa", type=Path)
    parser.add_argument("--report", type=Path)
    parser.add_argument("--build-number", default="1")
    parser.add_argument("--openssl", default="openssl")
    parser.add_argument("--check-only", action="store_true")
    args = parser.parse_args()
    try:
        if args.action == "read-device":
            read_device(args.tools, args.device_file)
        elif args.action == "lock-source":
            LOCK_PATH.parent.mkdir(parents=True, exist_ok=True)
            LOCK_PATH.write_text(json.dumps(source_files(), indent=2) + "\n", encoding="utf-8")
            print("PASS: existing app source/assets/tests/native Runner baseline recorded.")
        elif args.action == "check-source":
            verify_source()
            print("PASS: existing GasLeft app source and assets preserved.")
        elif args.action == "preflight":
            preflight(args.openssl)
        elif args.action == "configure":
            configure()
        elif args.action == "sign":
            sign(args.openssl)
        elif args.action == "settings":
            check_settings(args.build_number)
        elif args.action == "verify-mac":
            verify_mac(args.ipa, args.openssl, args.build_number)
        elif args.action == "install":
            install(args.ipa, args.device_file, args.tools, args.build_number, args.report, args.check_only)
    except (ValueError, KeyError, OSError, TypeError, plistlib.InvalidFileException, zipfile.BadZipFile, subprocess.TimeoutExpired) as error:
        # Our ValueErrors contain safe explanations; raw subprocess commands
        # and OpenSSL outputs (which could contain keys) remain unprinted.
        detail = redact(str(error)) if isinstance(error, ValueError) else type(error).__name__
        print("GasLeft direct-install preparation failed: " + detail, file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
