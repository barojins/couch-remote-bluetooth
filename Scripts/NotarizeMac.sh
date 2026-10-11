#!/bin/bash
set -euo pipefail
project_root="$(cd "$(dirname "$0")/.." && pwd)"
: "${DEVELOPER_ID_APPLICATION:?Set to your Developer ID Application signing identity}"
: "${NOTARY_PROFILE:?Set to an existing notarytool Keychain credential profile}"
# Never convert an unsigned development package into a purported signed release.
SIGNING_IDENTITY="$DEVELOPER_ID_APPLICATION" bash "$project_root/Scripts/PackageMac.sh"
dmg="$project_root/dist/CouchRemote-macOS13-universal.dmg"
xcrun notarytool submit "$dmg" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$dmg"
xcrun stapler validate "$dmg"
printf '\nNotarized disk image: %s\n' "$dmg"
