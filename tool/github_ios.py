"""Validate GitHub build inputs and prepare local runner signing settings."""
from __future__ import annotations

import argparse
import base64
from datetime import datetime, timezone
import hashlib
import os
from pathlib import Path
import plistlib
import re
import subprocess
import sys
import uuid

from prepare_testflight import ROOT, publisher_inputs

APPLE_NOT_BEFORE = datetime(2026, 10, 9, 5, tzinfo=timezone.utc)


def validate_inputs(environ, now=None):
    target = environ.get("GASLEFT_TARGET", "simulator")
    upload = environ.get("GASLEFT_UPLOAD", "false").lower()
    if target not in {"simulator", "testflight"} or upload not in {"true", "false"}:
        raise ValueError("Choose simulator/testflight and a true/false upload value.")
    if target == "simulator":
        if upload == "true":
            raise ValueError("A simulator build cannot be uploaded to TestFlight.")
        return
    if (now or datetime.now(timezone.utc)) < APPLE_NOT_BEFORE:
        raise ValueError("Apple work is deferred until 2026-10-09 14:00 KST.")
    if environ.get("GASLEFT_APPLE_ACCOUNT_READY", "").lower() != "true":
        raise ValueError("Set GASLEFT_APPLE_ACCOUNT_READY=true only after Apple access is restored and GasLeft is registered.")
    publisher_inputs(environ)
    if not re.fullmatch(r"[1-9][0-9]{0,8}", environ.get("GASLEFT_BUILD_NUMBER", "")):
        raise ValueError("Use a positive, unused Apple build number (up to nine digits).")
    required = ["GASLEFT_P12_BASE64", "GASLEFT_P12_PASSWORD", "GASLEFT_PROFILE_BASE64"]
    if upload == "true":
        required += ["GASLEFT_ASC_KEY_ID", "GASLEFT_ASC_ISSUER_ID", "GASLEFT_ASC_PRIVATE_KEY"]
    for name in required:
        if not environ.get(name, "").strip():
            raise ValueError(f"Set the repository secret {name}.")
    for name in ["GASLEFT_P12_BASE64", "GASLEFT_PROFILE_BASE64"]:
        try:
            base64.b64decode("".join(environ[name].split()), validate=True)
        except ValueError as error:
            raise ValueError(f"{name} must contain Base64-encoded signing data.") from error
    if upload == "true":
        if not re.fullmatch(r"[A-Z0-9]{10}", environ["GASLEFT_ASC_KEY_ID"]):
            raise ValueError("The App Store Connect API key ID must have ten characters.")
        try:
            uuid.UUID(environ["GASLEFT_ASC_ISSUER_ID"])
        except ValueError as error:
            raise ValueError("The App Store Connect issuer ID must be a UUID.") from error
        if "-----BEGIN PRIVATE KEY-----" not in environ["GASLEFT_ASC_PRIVATE_KEY"]:
            raise ValueError("GASLEFT_ASC_PRIVATE_KEY must contain the existing .p8 key text.")


def validate_profile(profile, bundle, team, now=None):
    entitlements = profile.get("Entitlements", {})
    if profile.get("TeamIdentifier") != [team]:
        raise ValueError("The signing profile belongs to a different Apple team.")
    if entitlements.get("application-identifier") != f"{team}.{bundle}":
        raise ValueError("The signing profile must match the exact GasLeft Bundle ID.")
    if entitlements.get("com.apple.developer.team-identifier") != team:
        raise ValueError("The profile entitlement team does not match.")
    expiration = profile.get("ExpirationDate")
    if not isinstance(expiration, datetime):
        raise ValueError("The signing profile has no expiration date.")
    if expiration.tzinfo is None:
        expiration = expiration.replace(tzinfo=timezone.utc)
    if expiration <= (now or datetime.now(timezone.utc)):
        raise ValueError("The signing profile has expired.")
    if "ProvisionedDevices" in profile or profile.get("ProvisionsAllDevices") or entitlements.get("get-task-allow"):
        raise ValueError("Use an App Store distribution profile for TestFlight.")
    profile_uuid = str(uuid.UUID(profile["UUID"]))
    certificates = profile.get("DeveloperCertificates", [])
    if not certificates or any(not isinstance(value, bytes) for value in certificates):
        raise ValueError("The profile has no valid distribution certificate data.")
    return profile_uuid, {hashlib.sha1(value).hexdigest().upper() for value in certificates}


def patch_release_signing(text, bundle, profile_uuid, identity):
    if not re.fullmatch(r"[A-F0-9]{40}", identity):
        raise ValueError("Use a SHA-1 signing identity from the imported keychain.")
    profile_uuid = str(uuid.UUID(profile_uuid))
    pattern = r"[A-F0-9]{24} /\* Release \*/ = \{(?:(?!\n\t\t\};).)*\n\t\t\};"
    count = 0

    def patch(match):
        nonlocal count
        block = match.group()
        if not re.search(rf"PRODUCT_BUNDLE_IDENTIFIER = {re.escape(bundle)};", block):
            return block
        count += 1
        for name in ["CODE_SIGN_STYLE", "CODE_SIGN_IDENTITY", '"CODE_SIGN_IDENTITY[sdk=iphoneos*]"', "PROVISIONING_PROFILE_SPECIFIER"]:
            block = re.sub(rf"(?m)^\s*{re.escape(name)} = [^;]*;\n", "\n", block)
        settings = (
            '\n\t\t\t\tCODE_SIGN_STYLE = Manual;'
            f'\n\t\t\t\tCODE_SIGN_IDENTITY = "{identity}";'
            f'\n\t\t\t\t"CODE_SIGN_IDENTITY[sdk=iphoneos*]" = "{identity}";'
            f'\n\t\t\t\tPROVISIONING_PROFILE_SPECIFIER = "{profile_uuid}";'
        )
        return block.replace("buildSettings = {", "buildSettings = {" + settings, 1)

    result = re.sub(pattern, patch, text, flags=re.S)
    if count != 1:
        raise ValueError("Expected exactly one GasLeft Runner Release configuration.")
    return result


def runner_secret_files():
    temp = Path(os.environ["RUNNER_TEMP"])
    return temp / "gasleft-signing.p12", temp / "gasleft-profile.mobileprovision"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=["preflight", "decode", "sign", "key", "cleanup"])
    args = parser.parse_args()
    try:
        if args.action == "preflight":
            validate_inputs(os.environ)
            print("PASS: GitHub build inputs validated; no Apple request was made.")
        elif args.action == "decode":
            for path, name in zip(runner_secret_files(), ["GASLEFT_P12_BASE64", "GASLEFT_PROFILE_BASE64"]):
                path.write_bytes(base64.b64decode("".join(os.environ[name].split()), validate=True))
                path.chmod(0o600)
        elif args.action == "sign":
            _, source = runner_secret_files()
            decoded = subprocess.run(["security", "cms", "-D", "-i", str(source)], capture_output=True, check=True).stdout
            profile_uuid, allowed = validate_profile(plistlib.loads(decoded), os.environ["BUNDLE_ID"], os.environ["DEVELOPMENT_TEAM"])
            keychain = Path(os.environ["RUNNER_TEMP"]) / "gasleft-signing.keychain-db"
            result = subprocess.run(["security", "find-identity", "-v", "-p", "codesigning", str(keychain)], capture_output=True, text=True, check=True)
            identities = set(re.findall(r"\b[A-Fa-f0-9]{40}\b", result.stdout.upper())) & allowed
            if not identities:
                raise ValueError("The imported private key has no valid certificate matching the GasLeft profile.")
            identity = sorted(identities)[0]
            project = ROOT / "ios/Runner.xcodeproj/project.pbxproj"
            project.write_text(patch_release_signing(project.read_text(encoding="utf-8"), os.environ["BUNDLE_ID"], profile_uuid, identity), encoding="utf-8")
            export = {
                "method": "app-store-connect", "destination": "export", "signingStyle": "manual",
                "teamID": os.environ["DEVELOPMENT_TEAM"], "signingCertificate": identity,
                "provisioningProfiles": {os.environ["BUNDLE_ID"]: profile_uuid},
                "manageAppVersionAndBuildNumber": False, "uploadSymbols": True,
            }
            target = ROOT / "build/gasleft/ExportOptions.plist"
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(plistlib.dumps(export))
            for directory in [Path.home() / "Library/MobileDevice/Provisioning Profiles", Path.home() / "Library/Developer/Xcode/UserData/Provisioning Profiles"]:
                directory.mkdir(parents=True, exist_ok=True)
                (directory / f"{profile_uuid}.mobileprovision").write_bytes(source.read_bytes())
            (Path(os.environ["RUNNER_TEMP"]) / "gasleft-profile-id.txt").write_text(profile_uuid, encoding="ascii")
            print("PASS: exact app/team/profile/certificate matched; Runner Release configured.")
        elif args.action == "key":
            key_id = os.environ["GASLEFT_ASC_KEY_ID"]
            if not re.fullmatch(r"[A-Z0-9]{10}", key_id):
                raise ValueError("Invalid App Store Connect key ID.")
            target = Path.home() / ".appstoreconnect/private_keys" / f"AuthKey_{key_id}.p8"
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text(os.environ["GASLEFT_ASC_PRIVATE_KEY"], encoding="utf-8")
            target.chmod(0o600)
            (Path(os.environ["RUNNER_TEMP"]) / "gasleft-asc-key-id.txt").write_text(key_id, encoding="ascii")
        elif args.action == "cleanup":
            for path in runner_secret_files():
                path.unlink(missing_ok=True)
            profile_id_path = Path(os.environ["RUNNER_TEMP"]) / "gasleft-profile-id.txt"
            if profile_id_path.exists():
                profile_id = str(uuid.UUID(profile_id_path.read_text(encoding="ascii")))
                for directory in [Path.home() / "Library/MobileDevice/Provisioning Profiles", Path.home() / "Library/Developer/Xcode/UserData/Provisioning Profiles"]:
                    (directory / f"{profile_id}.mobileprovision").unlink(missing_ok=True)
                profile_id_path.unlink()
            key_id_path = Path(os.environ["RUNNER_TEMP"]) / "gasleft-asc-key-id.txt"
            if key_id_path.exists():
                key_id = key_id_path.read_text(encoding="ascii")
                if not re.fullmatch(r"[A-Z0-9]{10}", key_id):
                    raise ValueError("Invalid cleanup key ID.")
                (Path.home() / ".appstoreconnect/private_keys" / f"AuthKey_{key_id}.p8").unlink(missing_ok=True)
                key_id_path.unlink()
    except (ValueError, KeyError, OSError, subprocess.CalledProcessError, plistlib.InvalidFileException) as error:
        if isinstance(error, subprocess.CalledProcessError):
            print("GitHub iOS preparation failed: Apple signing command failed.", file=sys.stderr)
        else:
            print(f"GitHub iOS preparation failed: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
