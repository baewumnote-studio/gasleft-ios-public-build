# GasLeft iOS build source

This separate build repository uses a fresh Git history. The original GasLeft repository remains private. The app calculates an estimated propane/LPG cylinder contents mass from an external scale reading and the cylinder's actual tare. It does not sense gas, diagnose leaks, predict days remaining, or certify safety.

The Camp Utility UI, calculation, local data model and advertising frequency are preserved. App artwork is copied without changes from the supplied final package. No custom font is bundled. This repository does not grant an open-source license for the app or artwork. Dependency notices are preserved separately.

## Manual build sequence

1. Run **GasLeft iOS build** with `target=unsigned`. Linux checks all existing tests; a standard hosted Mac compiles the Release app without signing. No signing credentials are read.
2. After that exact commit succeeds, the owner sets `GASLEFT_UNSIGNED_VERIFIED_SHA` to its commit SHA.
3. Configure the protected `gasleft-signing` Environment: the owner as required reviewer, `main` as the only deployment branch. Permit the owner to approve their own manual run; no pull-request event exists.
4. Choose `adhoc` for the registered iPhone or `testflight` for direct App Store Connect upload. Both signing preflights must pass on Linux before a Mac starts. Test ads are mandatory for Ad Hoc and default on for TestFlight. Production builds require the GasLeft-specific real AdMob IDs and `test_ads=false`.

The workflow is manual only. No signed IPA, provisioning profile, key or xcarchive is uploaded as a public Actions artifact. A signed IPA and original archive are sent to a **private** release in `baewumnote-studio/gasleft` using a fine-grained, expiring token limited to that repository with **Contents: read and write**. The workflow checks that destination is still private. Store the token only as `GASLEFT_PRIVATE_ARTIFACT_TOKEN` in the protected Environment. Never use a broad account token. A missing token prevents the signed Mac job from starting.

TestFlight upload does not submit App Store review, change availability, release the app or send tester invitations. Review submission requires the owner's final approval and device QA.

## Protected Environment inputs

Secrets: `GASLEFT_P12_BASE64`, `GASLEFT_P12_PASSWORD`, `GASLEFT_ADHOC_PROFILE_BASE64`, `GASLEFT_ADHOC_DEVICE_UDID`, `GASLEFT_PROFILE_BASE64` (App Store profile), `GASLEFT_ASC_KEY_ID`, `GASLEFT_ASC_ISSUER_ID`, `GASLEFT_ASC_PRIVATE_KEY`, `GASLEFT_PRIVATE_ARTIFACT_TOKEN`.

Variables: `GASLEFT_UNSIGNED_VERIFIED_SHA` (repository), `GASLEFT_SIGNING_APPROVED=true`, `GASLEFT_APPLE_ACCOUNT_READY=true`, `APP_STORE_APPLE_ID` (actual numeric GasLeft record), `GAD_APPLICATION_IDENTIFIER`, `ADMOB_INTERSTITIAL_IOS`. Google sample identifiers are never accepted with `test_ads=false`.

Use the existing approved certificate and each GasLeft-specific profile. Never commit device identifiers or credentials. The pinned Flutter and Xcode versions match the earlier verified GasLeft native archive; the workflow checks both versions.

## Windows USB installation

Download the IPA, verification report and original archive from the private release. Verify the IPA hash, certificate, profile, exact connected device, version and build with `tool/direct_iphone.py install --check-only` before installation. Installer 1.1.1 receives only an ASCII IPA filename with its parent as the working directory, including when the parent path contains Korean characters. Unlock, Trust, passcode entry and any required Developer Mode are completed by the user on the iPhone. Installation, app launch and feature QA are separate results.
