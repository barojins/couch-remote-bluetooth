#!/bin/bash
set -euo pipefail
project_root="$(cd "$(dirname "$0")/.." && pwd)"
: "${APPLE_TEAM_ID:?Set APPLE_TEAM_ID to your paid Apple Developer team ID}"
: "${BUNDLE_PREFIX:?Set BUNDLE_PREFIX to your unique reverse-DNS prefix}"
archive="$project_root/build/release/CouchRemotePhone.xcarchive"
xcodebuild -project "$project_root/CouchRemote.xcodeproj" -scheme CouchRemotePhone \
  -configuration Release -destination 'generic/platform=iOS' -archivePath "$archive" \
  DEVELOPMENT_TEAM="$APPLE_TEAM_ID" COUCH_REMOTE_BUNDLE_PREFIX="$BUNDLE_PREFIX" \
  CURRENT_PROJECT_VERSION="${BUILD_NUMBER:-1}" -allowProvisioningUpdates archive
printf '\nArchive ready: %s\nOpen this archive in Xcode Organizer, then Distribute App → App Store Connect.\n' "$archive"
