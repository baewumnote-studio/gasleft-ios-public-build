#!/usr/bin/env bash
set -euo pipefail
git clone --depth 1 --branch 3.47.5 https://github.com/flutter/flutter.git "$RUNNER_TEMP/gasleft-flutter"
test "$(git -C "$RUNNER_TEMP/gasleft-flutter" rev-parse HEAD)" = 6a19cca56475dbfba1478ee68d7bd0c2ef891da1
printf '%s\n' "$RUNNER_TEMP/gasleft-flutter/bin" >> "$GITHUB_PATH"
"$RUNNER_TEMP/gasleft-flutter/bin/flutter" --version
if [ "$RUNNER_OS" = macOS ]; then
  xcodebuild -version > "$RUNNER_TEMP/gasleft-xcode-version.txt"
  test "$(sed -n '1p' "$RUNNER_TEMP/gasleft-xcode-version.txt")" = 'Xcode 26.6'
fi
