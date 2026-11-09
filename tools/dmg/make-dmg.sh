#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -ne 2 ]; then
    echo "Usage: tools/dmg/make-dmg.sh <path to the .app> <output .dmg>" >&2
    exit 2
fi

here=$(cd "$(dirname "$0")" && pwd)
app=$(cd "$(dirname "$1")" && pwd)/$(basename "$1")
output=$2
plist="$app/Contents/Info.plist"
name=$(/usr/libexec/PlistBuddy -c "Print :CFBundleDisplayName" "$plist" 2>/dev/null ||
    /usr/libexec/PlistBuddy -c "Print :CFBundleName" "$plist")

mkdir -p "$(dirname "$output")"
rm -f "$output"
uvx --quiet --from dmgbuild==1.6.7 dmgbuild -s "$here/settings.py" -D app="$app" -D dir="$here" "$name" "$output"
hdiutil verify -quiet "$output"
echo "Built $output"
