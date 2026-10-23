#!/bin/sh
# Builds a signed, notarized, stapled Filkollen.dmg ready to publish.
#
# Needs, once:
#   - A "Developer ID Application" certificate in your login keychain.
#   - A notarytool profile:  xcrun notarytool store-credentials filkollen-notary \
#                              --apple-id you@example.com --team-id ABCDE12345
# Then:
#   TEAM_ID=ABCDE12345 scripts/release.sh
#
# Optional: NOTARY_PROFILE (default filkollen-notary), SPARKLE_BIN (folder with
# Sparkle's sign_update, to print the appcast signature), SKIP_NOTARIZE=1 for a
# local dry run.
set -eu
cd "$(dirname "$0")/.."

TEAM_ID="${TEAM_ID:?set TEAM_ID to your Apple Developer team ID}"
NOTARY_PROFILE="${NOTARY_PROFILE:-filkollen-notary}"
OUT="build/release"
ARCHIVE="$OUT/Filkollen.xcarchive"

version=$(sed -n 's/^ *MARKETING_VERSION: "\{0,1\}\([0-9.]*\)"\{0,1\}$/\1/p' project.yml)
[ -n "$version" ] || { echo "Couldn't read MARKETING_VERSION from project.yml" >&2; exit 1; }
DMG="$OUT/Filkollen-$version.dmg"

if [ -n "$(git status --porcelain)" ]; then
  echo "Working tree isn't clean; commit first so the release matches a commit." >&2
  exit 1
fi

rm -rf "$OUT" && mkdir -p "$OUT"
xcodegen generate

echo "→ Testing"
xcodebuild -project Filkollen.xcodeproj -scheme Filkollen -destination 'platform=macOS' \
  -derivedDataPath build/release-dd test -quiet

echo "→ Archiving $version"
xcodebuild -project Filkollen.xcodeproj -scheme Filkollen -configuration Release \
  -archivePath "$ARCHIVE" -derivedDataPath build/release-dd \
  DEVELOPMENT_TEAM="$TEAM_ID" CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="Developer ID Application" \
  OTHER_CODE_SIGN_FLAGS="--timestamp" archive -quiet

cat > "$OUT/ExportOptions.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>method</key><string>developer-id</string>
  <key>teamID</key><string>$TEAM_ID</string>
  <key>signingStyle</key><string>manual</string>
  <key>signingCertificate</key><string>Developer ID Application</string>
</dict></plist>
PLIST

echo "→ Exporting"
xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportPath "$OUT" -exportOptionsPlist "$OUT/ExportOptions.plist" -quiet
APP="$OUT/Filkollen.app"
codesign --verify --deep --strict --verbose=2 "$APP"

notarize() {
  if [ "${SKIP_NOTARIZE:-0}" = 1 ]; then echo "  (skipping notarization)"; return; fi
  xcrun notarytool submit "$1" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$2"
}

echo "→ Notarizing the app"
ditto -c -k --keepParent "$APP" "$OUT/Filkollen.zip"
notarize "$OUT/Filkollen.zip" "$APP"

echo "→ Building $DMG"
staging="$OUT/dmg"
mkdir -p "$staging"
cp -R "$APP" "$staging/"
ln -s /Applications "$staging/Applications"
hdiutil create -volname "Filkollen $version" -srcfolder "$staging" -ov -format UDZO "$DMG" >/dev/null
codesign --sign "Developer ID Application" --timestamp "$DMG"
notarize "$DMG" "$DMG"

[ "${SKIP_NOTARIZE:-0}" = 1 ] || spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG"

echo "→ Done: $DMG"
shasum -a 256 "$DMG"
if [ -n "${SPARKLE_BIN:-}" ] && [ -x "$SPARKLE_BIN/sign_update" ]; then
  echo "→ Sparkle appcast signature:"
  "$SPARKLE_BIN/sign_update" "$DMG"
fi
