#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

log=build/check.log
mkdir -p build

xcodegen generate --quiet
xcrun swift-format format --in-place --parallel --recursive Daybar
xcrun swift-format lint --strict --parallel --recursive Daybar
swiftlint lint --strict --quiet

if ! xcodebuild -project Daybar.xcodeproj -scheme Daybar -configuration Debug -derivedDataPath build/check \
    CODE_SIGNING_ALLOWED=NO clean build >"$log" 2>&1; then
    sed -nE '/(error|warning):/p' "$log" | sort -u
    tail -n 20 "$log"
    exit 1
fi

swiftlint analyze --strict --quiet --compiler-log-path "$log"
echo "All checks passed."
