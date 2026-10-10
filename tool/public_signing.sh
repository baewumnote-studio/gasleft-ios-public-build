#!/usr/bin/env bash
set -euo pipefail
umask 077
python3 -B tool/github_ios.py decode
GASLEFT_KEYCHAIN_PASSWORD=$(openssl rand -hex 24)
printf '::add-mask::%s\n' "$GASLEFT_KEYCHAIN_PASSWORD"
GASLEFT_KEYCHAIN="$RUNNER_TEMP/gasleft-signing.keychain-db"
security create-keychain -p "$GASLEFT_KEYCHAIN_PASSWORD" "$GASLEFT_KEYCHAIN"
security set-keychain-settings -lut 3600 "$GASLEFT_KEYCHAIN"
security unlock-keychain -p "$GASLEFT_KEYCHAIN_PASSWORD" "$GASLEFT_KEYCHAIN"
security import "$RUNNER_TEMP/gasleft-signing.p12" -P "$GASLEFT_P12_PASSWORD" -T /usr/bin/codesign -t cert -f pkcs12 -k "$GASLEFT_KEYCHAIN" >/dev/null
security set-key-partition-list -S apple-tool:,apple: -k "$GASLEFT_KEYCHAIN_PASSWORD" "$GASLEFT_KEYCHAIN" >/dev/null
security list-keychains -d user -s "$GASLEFT_KEYCHAIN" "$HOME/Library/Keychains/login.keychain-db"
security default-keychain -d user -s "$GASLEFT_KEYCHAIN"
if [ "$GASLEFT_MODE" = adhoc ]; then
  python3 -B tool/direct_iphone.py sign
else
  python3 -B tool/github_ios.py sign
fi
