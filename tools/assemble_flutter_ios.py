#!/usr/bin/env python3
"""Create a Flutter iOS scaffold and apply the chat-authored GasLeft source.

This script intentionally performs assembly, not product design. It can be run
by Codex on a macOS/Flutter environment so the remaining work is compile/test
compatibility rather than manually interpreting handoff documents.
"""
from __future__ import annotations

import argparse
import json
import plistlib
import re
import shutil
import subprocess
import sys
from pathlib import Path
from urllib.parse import urlparse

SOURCE_ROOT = Path(__file__).resolve().parents[1]
IOS_CONFIG = SOURCE_ROOT / "ios_config"

GOOGLE_SAMPLE_ADMOB_APP_ID = "ca-app-pub-3940256099942544~1458002511"
GOOGLE_SAMPLE_IOS_INTERSTITIAL_ID = "ca-app-pub-3940256099942544/4411468910"


def validate_reverse_dns(value: str, label: str) -> str:
    value = value.strip()
    if not re.fullmatch(r"[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)+", value):
        raise RuntimeError(f"Invalid {label}: {value!r}")
    return value


def validate_admob_app_id(value: str) -> str:
    value = value.strip()
    if not re.fullmatch(r"ca-app-pub-\d+~\d+", value):
        raise RuntimeError("AdMob iOS App ID must look like ca-app-pub-...~...")
    return value


def validate_ad_unit_id(value: str) -> str:
    value = value.strip()
    if not re.fullmatch(r"ca-app-pub-\d+/\d+", value):
        raise RuntimeError("AdMob interstitial ad unit ID must look like ca-app-pub-.../...")
    return value


def validate_production_admob_app_id(value: str) -> str:
    value = validate_admob_app_id(value)
    if value == GOOGLE_SAMPLE_ADMOB_APP_ID:
        raise RuntimeError("Google's sample AdMob App ID cannot be used for a release-ready build.")
    return value


def validate_production_ad_unit_id(value: str) -> str:
    value = validate_ad_unit_id(value)
    if value == GOOGLE_SAMPLE_IOS_INTERSTITIAL_ID:
        raise RuntimeError(
            "Google's sample iOS interstitial ad unit ID cannot be used for a release-ready build."
        )
    return value


def validate_https_url(value: str) -> str:
    value = value.strip()
    parsed = urlparse(value)
    if parsed.scheme.lower() != "https" or not parsed.netloc:
        raise RuntimeError("Privacy Policy URL must be an https URL.")
    return value


def validate_support_email(value: str) -> str:
    value = value.strip()
    if not re.fullmatch(r"[^@\s]+@[^@\s]+\.[^@\s]+", value):
        raise RuntimeError("Support email looks invalid.")
    return value


def verify_swiftpm_contract() -> None:
    """Flutter 3.44+ uses SwiftPM by default; GasLeft must not disable it."""
    pubspec = (SOURCE_ROOT / "pubspec.yaml").read_text(encoding="utf-8")
    if re.search(r"(?m)^\s*enable-swift-package-manager\s*:\s*false\s*$", pubspec):
        raise RuntimeError(
            "GasLeft must not disable Flutter Swift Package Manager support. "
            "Flutter 3.44+ uses SwiftPM by default and falls back to CocoaPods "
            "for plugins that still require it."
        )


def run(cmd: list[str], cwd: Path | None = None) -> None:
    print("+", " ".join(cmd))
    subprocess.run(cmd, cwd=cwd, check=True)


def copy_overlay(target: Path) -> None:
    for directory in ("lib", "test", "assets"):
        destination = target / directory
        if destination.exists():
            shutil.rmtree(destination)
        shutil.copytree(SOURCE_ROOT / directory, destination)
    for filename in ("pubspec.yaml", "analysis_options.yaml"):
        shutil.copy2(SOURCE_ROOT / filename, target / filename)

    handoff = target / "handoff_docs"
    if handoff.exists():
        shutil.rmtree(handoff)
    handoff.mkdir()
    for name in (
        "START_HERE_CODEX_KO.txt",
        "CODEX_ONE_SHOT_KO.txt",
        "FINAL_PRECOMPILE_STATUS.md",
        "FINAL_IMPLEMENTATION_AUTHORITY.md",
        "README_CHAT_READY_KO.txt",
        "CHAT_SOURCE_STATUS.json",
        "CODEX_ASSEMBLY_ONLY_PROMPT_KO.txt",
        "REMAINING_PUBLISHER_INPUTS.md",
        "QA_STATIC_REPORT.md",
        "IMPLEMENTATION_COVERAGE_MATRIX.md",
        "PACKAGE_VERSIONS_CHECKED_20261007.md",
        "ASSEMBLY_RUNBOOK_KO.md",
        "RELEASE_SOURCE_AUDIT.md",
        "FINAL_CHANGELOG.md",
    ):
        path = SOURCE_ROOT / name
        if path.exists():
            shutil.copy2(path, handoff / name)



def install_final_app_icon(target: Path) -> None:
    installer = SOURCE_ROOT / "tools/install_ios_app_icon.py"
    run([sys.executable, "-B", str(installer), str(target)])


def skad_ids_from_fragment() -> list[str]:
    text = (IOS_CONFIG / "Info.plist.ADDITIONS.xml").read_text(encoding="utf-8")
    ids = re.findall(r"<string>([a-z0-9]+\.skadnetwork)</string>", text)
    if not ids:
        raise RuntimeError("No SKAdNetwork IDs found in Info.plist additions.")
    # Preserve official ordering but drop accidental duplicates.
    return list(dict.fromkeys(ids))


def patch_info_plist(target: Path) -> None:
    path = target / "ios" / "Runner" / "Info.plist"
    with path.open("rb") as f:
        data = plistlib.load(f)
    data["GADApplicationIdentifier"] = "$(GAD_APPLICATION_IDENTIFIER)"
    # The reviewed GasLeft source and linked SDK set use no non-exempt
    # encryption. This avoids repeating App Store export-compliance questions.
    data["ITSAppUsesNonExemptEncryption"] = False
    data["SKAdNetworkItems"] = [
        {"SKAdNetworkIdentifier": identifier}
        for identifier in skad_ids_from_fragment()
    ]
    # GasLeft has a customized AppDelegate, so do not rely on Flutter's
    # automatic UIScene migration. Xcode 27 requires the scene lifecycle.
    data["UIApplicationSceneManifest"] = {
        "UIApplicationSupportsMultipleScenes": False,
        "UISceneConfigurations": {
            "UIWindowSceneSessionRoleApplication": [
                {
                    "UISceneClassName": "UIWindowScene",
                    "UISceneDelegateClassName": "FlutterSceneDelegate",
                    "UISceneConfigurationName": "flutter",
                    "UISceneStoryboardFile": "Main",
                }
            ]
        },
    }
    # MVP deliberately does not request ATT/IDFA.
    data.pop("NSUserTrackingUsageDescription", None)
    with path.open("wb") as f:
        plistlib.dump(data, f, sort_keys=False)


def set_xcconfig_value(path: Path, key: str, value: str) -> None:
    text = path.read_text(encoding="utf-8")
    pattern = re.compile(rf"(?m)^\s*{re.escape(key)}\s*=.*$")
    line = f"{key}={value}"
    if pattern.search(text):
        text = pattern.sub(line, text)
    else:
        if not text.endswith("\n"):
            text += "\n"
        text += line + "\n"
    path.write_text(text, encoding="utf-8")


def patch_xcconfigs(target: Path, admob_app_id: str | None) -> None:
    flutter_dir = target / "ios" / "Flutter"
    test_app_id = GOOGLE_SAMPLE_ADMOB_APP_ID
    if admob_app_id is not None:
        admob_app_id = validate_admob_app_id(admob_app_id)
    set_xcconfig_value(flutter_dir / "Debug.xcconfig", "GAD_APPLICATION_IDENTIFIER", test_app_id)
    set_xcconfig_value(flutter_dir / "Profile.xcconfig", "GAD_APPLICATION_IDENTIFIER", test_app_id)
    release_value = admob_app_id or "__PUBLISHER_ADMOB_IOS_APP_ID__"
    set_xcconfig_value(flutter_dir / "Release.xcconfig", "GAD_APPLICATION_IDENTIFIER", release_value)


def patch_app_delegate(target: Path) -> None:
    source = IOS_CONFIG / "AppDelegate.NOTIFICATION_PATCH.swift"
    destination = target / "ios" / "Runner" / "AppDelegate.swift"
    shutil.copy2(source, destination)


def patch_podfile(target: Path) -> None:
    path = target / "ios" / "Podfile"
    if not path.exists():
        # Flutter 3.44+ uses Swift Package Manager by default. Do not create a
        # Podfile just to satisfy this assembler. If Flutter later falls back to
        # CocoaPods for a plugin, main() calls this function again after pub get.
        print("i ios/Podfile not present; keeping Flutter's SwiftPM-first integration")
        return
    text = path.read_text(encoding="utf-8")
    platform_line = "platform :ios, '15.0'"
    if re.search(r"(?m)^\s*#?\s*platform\s+:ios,\s*'[^']+'", text):
        text = re.sub(
            r"(?m)^\s*#?\s*platform\s+:ios,\s*'[^']+'\s*$",
            platform_line,
            text,
            count=1,
        )
    else:
        text = platform_line + "\n\n" + text

    deployment_line = "config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '15.0'"
    if deployment_line not in text:
        needle = "flutter_additional_ios_build_settings(target)"
        if needle not in text:
            raise RuntimeError(
                "Generated Podfile shape was not recognized. Add the iOS 15.0 "
                "deployment target loop manually without replacing existing post_install logic."
            )
        insertion = (
            needle
            + "\n    target.build_configurations.each do |config|\n"
            + "      config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '15.0'\n"
            + "    end"
        )
        text = text.replace(needle, insertion, 1)
    path.write_text(text, encoding="utf-8")


def patch_runner_project(
    target: Path,
    *,
    bundle_id: str | None = None,
    development_team: str | None = None,
) -> None:
    path = target / "ios" / "Runner.xcodeproj" / "project.pbxproj"
    if not path.exists():
        return
    text = path.read_text(encoding="utf-8")
    text = re.sub(
        r"IPHONEOS_DEPLOYMENT_TARGET\s*=\s*[0-9.]+;",
        "IPHONEOS_DEPLOYMENT_TARGET = 15.0;",
        text,
    )
    # GasLeft is an iPhone-only MVP. Flutter/Xcode scaffolds commonly default
    # to supporting both iPhone and iPad, which would expand the App Store
    # screenshot/review surface. Force the Runner family to iPhone.
    if re.search(r"TARGETED_DEVICE_FAMILY\s*=", text):
        text = re.sub(
            r'TARGETED_DEVICE_FAMILY\s*=\s*[^;]+;',
            'TARGETED_DEVICE_FAMILY = 1;',
            text,
        )
    else:
        text = re.sub(
            r'(?m)^(\s*)(IPHONEOS_DEPLOYMENT_TARGET\s*=\s*15\.0;)',
            r'\1\2\n\1TARGETED_DEVICE_FAMILY = 1;',
            text,
        )

    if bundle_id is not None:
        bundle_id = validate_reverse_dns(bundle_id, "iOS bundle identifier")

        def _bundle(match: re.Match[str]) -> str:
            old = match.group(1).strip().strip('"')
            suffix = ".RunnerTests" if old.endswith(".RunnerTests") else ""
            return f"PRODUCT_BUNDLE_IDENTIFIER = {bundle_id}{suffix};"

        text, count = re.subn(
            r"PRODUCT_BUNDLE_IDENTIFIER\s*=\s*([^;]+);",
            _bundle,
            text,
        )
        if count == 0:
            raise RuntimeError("Runner project has no PRODUCT_BUNDLE_IDENTIFIER setting.")

    if development_team is not None:
        development_team = development_team.strip()
        if not re.fullmatch(r"[A-Z0-9]{10}", development_team):
            raise RuntimeError(
                "Apple Development Team must be the 10-character Team ID, "
                f"got {development_team!r}."
            )
        if re.search(r"DEVELOPMENT_TEAM\s*=", text):
            text = re.sub(
                r"DEVELOPMENT_TEAM\s*=\s*[^;]*;",
                f"DEVELOPMENT_TEAM = {development_team};",
                text,
            )
        else:
            # Target configuration blocks always contain PRODUCT_BUNDLE_IDENTIFIER.
            # Add the same Team ID immediately before those settings, including
            # RunnerTests, so signing is deterministic without touching product logic.
            text = re.sub(
                r"(?m)^(\s*)(PRODUCT_BUNDLE_IDENTIFIER\s*=)",
                rf"\1DEVELOPMENT_TEAM = {development_team};\n\1\2",
                text,
            )

    if development_team is not None:
        if re.search(r"CODE_SIGN_STYLE\s*=", text):
            text = re.sub(
                r"CODE_SIGN_STYLE\s*=\s*[^;]*;",
                "CODE_SIGN_STYLE = Automatic;",
                text,
            )
        else:
            text = re.sub(
                r"(?m)^(\s*)(DEVELOPMENT_TEAM\s*=)",
                r"\1CODE_SIGN_STYLE = Automatic;\n\1\2",
                text,
            )

    path.write_text(text, encoding="utf-8")


def patch_runner_deployment_target(target: Path) -> None:
    # Backwards-compatible helper retained for tests/older scripts.
    patch_runner_project(target)


def write_release_dart_defines(
    target: Path,
    *,
    ad_unit_id: str | None,
    privacy_url: str | None,
    support_email: str | None,
) -> Path | None:
    values = (ad_unit_id, privacy_url, support_email)
    if not any(value is not None for value in values):
        return None
    if not all(value is not None for value in values):
        raise RuntimeError(
            "--ad-unit-id, --privacy-url, and --support-email must be supplied together."
        )

    config = {
        "ADMOB_INTERSTITIAL_IOS": validate_production_ad_unit_id(ad_unit_id or ""),
        "PRIVACY_POLICY_URL": validate_https_url(privacy_url or ""),
        "SUPPORT_EMAIL": validate_support_email(support_email or ""),
    }
    config_dir = target / "publisher_config"
    config_dir.mkdir(parents=True, exist_ok=True)
    path = config_dir / "release_dart_defines.json"
    path.write_text(json.dumps(config, indent=2) + "\n", encoding="utf-8")
    (config_dir / "BUILD_RELEASE_COMMANDS.txt").write_text(
        "Release compile smoke test (no signing):\n"
        "flutter build ios --release --no-codesign "
        "--dart-define-from-file=publisher_config/release_dart_defines.json\n\n"
        "Signed App Store archive when signing/provisioning is ready:\n"
        "flutter build ipa --release "
        "--dart-define-from-file=publisher_config/release_dart_defines.json\n",
        encoding="utf-8",
    )
    return path


def verify_assembled_project(
    target: Path,
    *,
    bundle_id: str | None,
    development_team: str | None,
    admob_app_id: str | None,
    release_ready: bool,
) -> None:
    verify_swiftpm_contract()

    plist = plistlib.loads((target / "ios/Runner/Info.plist").read_bytes())
    if plist.get("GADApplicationIdentifier") != "$(GAD_APPLICATION_IDENTIFIER)":
        raise RuntimeError("Info.plist GADApplicationIdentifier build setting is missing.")
    scene = plist.get("UIApplicationSceneManifest", {})
    if scene.get("UIApplicationSupportsMultipleScenes") is not False:
        raise RuntimeError("GasLeft must keep iOS multiple-scene support disabled.")
    if "NSUserTrackingUsageDescription" in plist:
        raise RuntimeError("ATT tracking usage description must not be present in MVP.")

    project = (target / "ios/Runner.xcodeproj/project.pbxproj").read_text(encoding="utf-8")
    device_families = {
        value.strip().strip('"')
        for value in re.findall(r"TARGETED_DEVICE_FAMILY\s*=\s*([^;]+);", project)
    }
    if device_families != {"1"}:
        raise RuntimeError(
            f"Runner must be iPhone-only in every configuration, got {sorted(device_families)}."
        )

    deployment_targets = set(
        re.findall(r"IPHONEOS_DEPLOYMENT_TARGET\s*=\s*([0-9.]+);", project)
    )
    if deployment_targets != {"15.0"}:
        raise RuntimeError(
            f"Every Runner deployment target must be iOS 15.0, got {sorted(deployment_targets)}."
        )

    if bundle_id is not None:
        bundle_values = [
            value.strip().strip('"')
            for value in re.findall(r"PRODUCT_BUNDLE_IDENTIFIER\s*=\s*([^;]+);", project)
        ]
        expected = {bundle_id, f"{bundle_id}.RunnerTests"}
        if not expected.issubset(set(bundle_values)):
            raise RuntimeError(
                f"Bundle IDs were not applied consistently. Expected at least {sorted(expected)}, "
                f"got {bundle_values}."
            )
        unexpected = [
            value for value in bundle_values
            if value not in expected
        ]
        if unexpected:
            raise RuntimeError(f"Unexpected bundle identifiers remain: {unexpected}")

    if development_team is not None:
        teams = set(re.findall(r"DEVELOPMENT_TEAM\s*=\s*([^;]+);", project))
        if teams != {development_team}:
            raise RuntimeError(
                f"Apple Development Team is inconsistent across configurations: {sorted(teams)}."
            )
        signing_styles = set(re.findall(r"CODE_SIGN_STYLE\s*=\s*([^;]+);", project))
        if signing_styles != {"Automatic"}:
            raise RuntimeError(
                f"Automatic signing is not consistent across configurations: {sorted(signing_styles)}."
            )

    release_xcconfig = (target / "ios/Flutter/Release.xcconfig").read_text(encoding="utf-8")
    if release_ready:
        if "__PUBLISHER_ADMOB_IOS_APP_ID__" in release_xcconfig:
            raise RuntimeError("Release AdMob App ID placeholder remains.")
        if admob_app_id is None or f"GAD_APPLICATION_IDENTIFIER={admob_app_id}" not in release_xcconfig:
            raise RuntimeError("Production AdMob App ID is not applied to Release.xcconfig.")
        release_defines = target / "publisher_config/release_dart_defines.json"
        if not release_defines.exists():
            raise RuntimeError("Release Dart defines file is missing.")
        parsed = json.loads(release_defines.read_text(encoding="utf-8"))
        validate_production_ad_unit_id(parsed["ADMOB_INTERSTITIAL_IOS"])
        validate_https_url(parsed["PRIVACY_POLICY_URL"])
        validate_support_email(parsed["SUPPORT_EMAIL"])


def verify_no_forbidden_permissions(target: Path) -> None:
    info = (target / "ios" / "Runner" / "Info.plist").read_bytes()
    data = plistlib.loads(info)
    forbidden = {
        "NSCameraUsageDescription",
        "NSMicrophoneUsageDescription",
        "NSLocationWhenInUseUsageDescription",
        "NSLocationAlwaysAndWhenInUseUsageDescription",
        "NSBluetoothAlwaysUsageDescription",
        "NSPhotoLibraryUsageDescription",
        "NSContactsUsageDescription",
        "NSUserTrackingUsageDescription",
    }
    found = sorted(forbidden.intersection(data.keys()))
    if found:
        raise RuntimeError(f"Forbidden/unneeded iOS privacy keys found: {found}")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("target", type=Path, help="New Flutter project directory")
    parser.add_argument("--org", required=True, help="Reverse-DNS org, e.g. com.example")
    parser.add_argument("--admob-app-id", help="Production iOS AdMob App ID (ca-app-pub-...~...)")
    parser.add_argument("--ad-unit-id", help="Production iOS interstitial ad unit ID")
    parser.add_argument("--privacy-url", help="Hosted https Privacy Policy URL")
    parser.add_argument("--support-email", help="Publisher support email")
    parser.add_argument(
        "--release-ready",
        action="store_true",
        help="Require every publisher-owned value and reject release placeholders.",
    )
    parser.add_argument(
        "--bundle-id",
        help="Exact iOS bundle identifier. If omitted, Flutter's --org-derived ID is kept.",
    )
    parser.add_argument(
        "--development-team",
        help="Optional 10-character Apple Developer Team ID for Runner signing.",
    )
    parser.add_argument("--skip-pub-get", action="store_true")
    parser.add_argument(
        "--verify",
        action="store_true",
        help="After assembly, run dart format, flutter analyze/test, and iOS simulator build.",
    )
    parser.add_argument(
        "--verify-release",
        action="store_true",
        help="Also compile an unsigned Release iOS build using generated release Dart defines.",
    )
    args = parser.parse_args()

    verify_swiftpm_contract()
    args.org = validate_reverse_dns(args.org, "Flutter --org value")
    if args.admob_app_id is not None:
        args.admob_app_id = validate_admob_app_id(args.admob_app_id)
    if args.bundle_id is not None:
        args.bundle_id = validate_reverse_dns(args.bundle_id, "iOS bundle identifier")

    if args.release_ready or args.verify_release:
        required = {
            "--bundle-id": args.bundle_id,
            "--development-team": args.development_team,
            "--admob-app-id": args.admob_app_id,
            "--ad-unit-id": args.ad_unit_id,
            "--privacy-url": args.privacy_url,
            "--support-email": args.support_email,
        }
        missing = [name for name, value in required.items() if not value]
        if missing:
            print(
                "ERROR: release-ready assembly is missing " + ", ".join(missing),
                file=sys.stderr,
            )
            return 2
        # Release-ready paths must never accept Google's demo identifiers.
        args.admob_app_id = validate_production_admob_app_id(args.admob_app_id or "")
        args.ad_unit_id = validate_production_ad_unit_id(args.ad_unit_id or "")

    flutter = shutil.which("flutter")
    if flutter is None:
        print("ERROR: flutter is not on PATH", file=sys.stderr)
        return 2
    if args.target.exists() and any(args.target.iterdir()):
        print("ERROR: target directory must be absent or empty", file=sys.stderr)
        return 2

    args.target.parent.mkdir(parents=True, exist_ok=True)
    run([
        flutter,
        "create",
        "--platforms=ios",
        "--org",
        args.org,
        "--project-name",
        "gasleft",
        str(args.target),
    ])
    copy_overlay(args.target)
    install_final_app_icon(args.target)
    patch_info_plist(args.target)
    patch_xcconfigs(args.target, args.admob_app_id)
    patch_app_delegate(args.target)
    patch_podfile(args.target)
    patch_runner_project(
        args.target,
        bundle_id=args.bundle_id,
        development_team=args.development_team,
    )
    release_defines = write_release_dart_defines(
        args.target,
        ad_unit_id=args.ad_unit_id,
        privacy_url=args.privacy_url,
        support_email=args.support_email,
    )
    verify_no_forbidden_permissions(args.target)

    if not args.skip_pub_get:
        run([flutter, "pub", "get"], cwd=args.target)
        # Flutter 3.44+ is SwiftPM-first, but it can fall back to CocoaPods if
        # a plugin requires it. Patch a Podfile that appears during pub get.
        patch_podfile(args.target)

    verify_assembled_project(
        args.target,
        bundle_id=args.bundle_id,
        development_team=args.development_team,
        admob_app_id=args.admob_app_id,
        release_ready=args.release_ready or args.verify_release,
    )

    ran_verification = False
    if args.verify:
        dart = shutil.which("dart")
        if dart is None:
            print("ERROR: dart is not on PATH", file=sys.stderr)
            return 2
        run([dart, "format", "."], cwd=args.target)
        run([flutter, "analyze"], cwd=args.target)
        run([flutter, "test"], cwd=args.target)
        run([flutter, "build", "ios", "--simulator", "--debug"], cwd=args.target)
        ran_verification = True

    if args.verify_release:
        if release_defines is None:
            raise RuntimeError("Release Dart defines were not generated.")
        run(
            [
                flutter,
                "build",
                "ios",
                "--release",
                "--no-codesign",
                "--dart-define-from-file=publisher_config/release_dart_defines.json",
            ],
            cwd=args.target,
        )
        ran_verification = True

    if ran_verification:
        print("Assembly and requested verification commands completed successfully.")
    else:
        print("Assembly complete.")
        print(
            "Next: dart format . && flutter analyze && flutter test && "
            "flutter build ios --simulator --debug"
        )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
