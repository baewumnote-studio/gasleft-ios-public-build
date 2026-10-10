"""Apply publisher inputs in CI without storing any Apple signing credentials."""
from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import re
import sys
from urllib.parse import urlparse
from urllib.request import urlopen

ROOT = Path(__file__).resolve().parents[1]
TEST_APP_ID = "ca-app-pub-3940256099942544~1458002511"
TEST_AD_ID = "ca-app-pub-3940256099942544/4411468910"


def publisher_inputs(environ):
    def required(name):
        value = environ.get(name, "").strip()
        if not value or value.startswith("__SET_"):
            raise ValueError(f"Set {name} before starting the signed build.")
        return value

    bundle = required("BUNDLE_ID")
    if not re.fullmatch(r"[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)+", bundle):
        raise ValueError("BUNDLE_ID must be a registered reverse-domain identifier.")
    if bundle.startswith("com.example."):
        raise ValueError("Replace the development BUNDLE_ID with the registered app ID.")
    apple_id = required("APP_STORE_APPLE_ID")
    if not apple_id.isdecimal():
        raise ValueError("APP_STORE_APPLE_ID must be the numeric App Store Connect app ID.")
    team = required("DEVELOPMENT_TEAM")
    if not re.fullmatch(r"[A-Z0-9]{10}", team):
        raise ValueError("DEVELOPMENT_TEAM must be the ten-character Apple Team ID.")
    privacy = required("PRIVACY_POLICY_URL")
    parsed = urlparse(privacy)
    if parsed.scheme != "https" or not parsed.hostname or parsed.username or parsed.password:
        raise ValueError("PRIVACY_POLICY_URL must be a public HTTPS URL without credentials.")
    email = required("SUPPORT_EMAIL")
    if not re.fullmatch(r"[^@\s]+@[^@\s]+\.[^@\s]+", email):
        raise ValueError("SUPPORT_EMAIL must be a working publisher contact address.")
    mode = environ.get("ADMOB_USE_TEST_ADS", "false").strip().lower()
    if mode not in {"true", "false"}:
        raise ValueError("ADMOB_USE_TEST_ADS must be true or false.")
    if mode == "true":
        app_id, ad_id = TEST_APP_ID, TEST_AD_ID
    else:
        app_id = required("GAD_APPLICATION_IDENTIFIER")
        ad_id = required("ADMOB_INTERSTITIAL_IOS")
        if not re.fullmatch(r"ca-app-pub-\d+~\d+", app_id):
            raise ValueError("GAD_APPLICATION_IDENTIFIER must be an AdMob iOS App ID.")
        if not re.fullmatch(r"ca-app-pub-\d+/\d+", ad_id):
            raise ValueError("ADMOB_INTERSTITIAL_IOS must be an AdMob interstitial ID.")
        if any(value.startswith("ca-app-pub-3940256099942544") for value in (app_id, ad_id)):
            raise ValueError("App Store production builds must use publisher ad IDs.")
    return {
        "bundle": bundle, "apple_id": apple_id, "team": team,
        "admob_app_id": app_id,
        "defines": {
            "ADMOB_USE_TEST_ADS": mode,
            "ADMOB_INTERSTITIAL_IOS": ad_id,
            "PRIVACY_POLICY_URL": privacy,
            "SUPPORT_EMAIL": email,
        },
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check-only", action="store_true")
    parser.add_argument("--verify-policy-url", action="store_true")
    args = parser.parse_args()
    try:
        config = publisher_inputs(os.environ)
        if args.verify_policy_url:
            with urlopen(config["defines"]["PRIVACY_POLICY_URL"], timeout=20) as response:
                if response.status != 200 or "gasleft" not in response.read(512_000).decode("utf-8", errors="replace").lower():
                    raise ValueError("The public privacy page must respond successfully and identify GasLeft.")
        if not args.check_only:
            sys.path.insert(0, str(ROOT / "tools"))
            import assemble_flutter_ios as assembler
            assembler.patch_runner_project(ROOT, bundle_id=config["bundle"], development_team=config["team"])
            assembler.patch_xcconfigs(ROOT, config["admob_app_id"])
            output = ROOT / "build/gasleft/release_dart_defines.json"
            output.parent.mkdir(parents=True, exist_ok=True)
            output.write_text(json.dumps(config["defines"], indent=2) + "\n", encoding="utf-8")
        print("PASS: publisher inputs validated; test ads=" + config["defines"]["ADMOB_USE_TEST_ADS"])
        if not args.check_only:
            print("Configured Runner and build/gasleft/release_dart_defines.json. No Apple keys were written.")
    except (ValueError, OSError, RuntimeError) as error:
        print(f"TestFlight preparation failed: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
