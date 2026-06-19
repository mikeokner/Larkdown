#!/bin/sh
set -eu

fail() { echo "$*" >&2; exit 2; }
if [ "${1:-}" = --help ] || [ "${1:-}" = -h ]; then
    echo 'Usage: scripts/package-release.sh VERSION [BUILD_NUMBER]'
    echo 'See DEVELOPING.md for signing, notarization, and Sparkle configuration.'
    exit 0
fi
[ $# -ge 1 ] && [ $# -le 2 ] || fail 'Expected VERSION and optional BUILD_NUMBER.'
VERSION=$1
BUILD_NUMBER=${2:-${BUILD_NUMBER:-$(date -u +%Y%m%d%H%M%S)}}
RELEASE_NAME=${RELEASE_NAME:-$VERSION}
SIGNING_MODE=${SIGNING_MODE:-ad-hoc}
NOTARIZE=${NOTARIZE:-0}
OUTPUT_DIR=${OUTPUT_DIR:-dist/release}
SIGNING_IDENTITY=${SIGNING_IDENTITY:-Developer ID Application}
printf '%s\n' "$VERSION" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$' || fail 'VERSION must be x.y.z.'
printf '%s\n' "$RELEASE_NAME" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+(-rc\.[0-9]+)?$' || fail 'RELEASE_NAME must be x.y.z or x.y.z-rc.N.'
[ "${RELEASE_NAME%%-rc.*}" = "$VERSION" ] || fail 'Release label must match VERSION.'
printf '%s\n' "$BUILD_NUMBER" | grep -Eq '^[1-9][0-9]*$' || fail 'BUILD_NUMBER must be a positive integer.'
case "$SIGNING_MODE" in ad-hoc|developer-id) ;; *) fail 'Unknown SIGNING_MODE.' ;; esac
case "$NOTARIZE" in 0|1) ;; *) fail 'NOTARIZE must be 0 or 1.' ;; esac
if [ "$NOTARIZE" = 1 ]; then
    [ "$SIGNING_MODE" = developer-id ] || fail 'Notarization requires Developer ID signing.'
    [ -n "${NOTARY_PROFILE:-}" ] || fail 'NOTARY_PROFILE is required.'
fi
if [ "$SIGNING_MODE" = developer-id ]; then
    [ -n "${DEVELOPMENT_TEAM:-}" ] || fail 'DEVELOPMENT_TEAM is required.'
    [ "$NOTARIZE" = 1 ] || fail 'Public Developer ID packages require NOTARIZE=1.'
    [ -n "${SPARKLE_PUBLIC_ED_KEY:-}" ] && [ -f "${SPARKLE_PRIVATE_KEY_FILE:-}" ] || fail 'Sparkle public key and private-key file are required.'
fi
if [ -n "${SPARKLE_PRIVATE_KEY_FILE:-}" ]; then
    swift scripts/validate-update-key.swift "$SPARKLE_PRIVATE_KEY_FILE"
fi
ARTIFACT_DIR="$OUTPUT_DIR/Larkdown-$RELEASE_NAME"
[ ! -e "$ARTIFACT_DIR" ] || fail "Output already exists: $ARTIFACT_DIR. Use a new release label or OUTPUT_DIR."
if [ "${SKIP_TESTS:-0}" != 1 ]; then scripts/test.sh; fi
PACKAGES_DIR=.build/SourcePackages
SPARKLE_BIN="$PACKAGES_DIR/artifacts/sparkle/Sparkle/bin"
xcodebuild -resolvePackageDependencies -project Larkdown.xcodeproj -scheme Larkdown \
    -clonedSourcePackagesDirPath "$PACKAGES_DIR"
[ -x "$SPARKLE_BIN/sign_update" ] || fail "Sparkle tools not found in $SPARKLE_BIN."
mkdir -p .build "$OUTPUT_DIR"
WORK_DIR=$(mktemp -d "$PWD/.build/release.XXXXXX")
ARCHIVE_PATH="$WORK_DIR/Larkdown.xcarchive"
APP_PATH="$WORK_DIR/Larkdown.app"
ZIP_NAME="Larkdown-$RELEASE_NAME-macos-universal.zip"
mkdir "$ARTIFACT_DIR"
ZIP_PATH="$ARTIFACT_DIR/$ZIP_NAME"
DMG_PATH="$ARTIFACT_DIR/Larkdown-$RELEASE_NAME.dmg"

# Hardened runtime enforces library validation, which rejects the ad-hoc
# signed Sparkle framework, so only Developer ID builds enable it.
if [ "$SIGNING_MODE" = developer-id ]; then
    IDENTITY=$SIGNING_IDENTITY
    HARDENED_RUNTIME=YES
else
    IDENTITY=-
    HARDENED_RUNTIME=NO
fi
xcodebuild -project Larkdown.xcodeproj -scheme Larkdown -configuration Release \
    -destination 'generic/platform=macOS' -archivePath "$ARCHIVE_PATH" \
    -clonedSourcePackagesDirPath "$PACKAGES_DIR" \
    MARKETING_VERSION="$VERSION" CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
    'ARCHS=arm64 x86_64' ONLY_ACTIVE_ARCH=NO ENABLE_HARDENED_RUNTIME="$HARDENED_RUNTIME" \
    SPARKLE_PUBLIC_ED_KEY="${SPARKLE_PUBLIC_ED_KEY:-}" \
    CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="$IDENTITY" \
    DEVELOPMENT_TEAM="${DEVELOPMENT_TEAM:-}" archive

if [ "$SIGNING_MODE" = developer-id ]; then
    # Export signs nested Sparkle services with Developer ID as well as the app.
    cat > "$WORK_DIR/ExportOptions.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0"><dict>
<key>method</key><string>developer-id</string>
<key>teamID</key><string>$DEVELOPMENT_TEAM</string>
<key>signingStyle</key><string>manual</string>
<key>signingCertificate</key><string>Developer ID Application</string>
</dict></plist>
PLIST
    xcodebuild -exportArchive -archivePath "$ARCHIVE_PATH" -exportPath "$WORK_DIR/export" -exportOptionsPlist "$WORK_DIR/ExportOptions.plist"
    ditto "$WORK_DIR/export/Larkdown.app" "$APP_PATH"
else
    ditto "$ARCHIVE_PATH/Products/Applications/Larkdown.app" "$APP_PATH"
fi
scripts/check-distribution.sh "$APP_PATH"
if [ -n "${SPARKLE_PRIVATE_KEY_FILE:-}" ]; then
    EMBEDDED_KEY=$(/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' "$APP_PATH/Contents/Info.plist")
    [ "$EMBEDDED_KEY" = "$SPARKLE_PUBLIC_ED_KEY" ] || fail 'Archived updater key does not match the signing key.'
fi
lipo "$APP_PATH/Contents/MacOS/Larkdown" -verify_arch arm64
lipo "$APP_PATH/Contents/MacOS/Larkdown" -verify_arch x86_64
codesign --verify --deep --strict "$APP_PATH"
if [ "$NOTARIZE" = 1 ]; then
    ditto -c -k --keepParent "$APP_PATH" "$WORK_DIR/notarization.zip"
    xcrun notarytool submit "$WORK_DIR/notarization.zip" --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple "$APP_PATH"
    xcrun stapler validate "$APP_PATH"
    spctl --assess --type execute --verbose "$APP_PATH"
fi
ditto -c -k --keepParent "$APP_PATH" "$ZIP_PATH"
mkdir "$WORK_DIR/dmg-root"
ditto "$APP_PATH" "$WORK_DIR/dmg-root/Larkdown.app"
ln -s /Applications "$WORK_DIR/dmg-root/Applications"
hdiutil create -volname "Larkdown $RELEASE_NAME" -srcfolder "$WORK_DIR/dmg-root" -format UDZO "$DMG_PATH"
if [ "$NOTARIZE" = 1 ]; then
    codesign --sign "$SIGNING_IDENTITY" --timestamp "$DMG_PATH"
    xcrun notarytool submit "$DMG_PATH" --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple "$DMG_PATH"
    xcrun stapler validate "$DMG_PATH"
fi
if [ -n "${SPARKLE_PRIVATE_KEY_FILE:-}" ]; then
    SIGNATURE=$("$SPARKLE_BIN/sign_update" --ed-key-file "$SPARKLE_PRIVATE_KEY_FILE" "$ZIP_PATH")
    cat > "$ARTIFACT_DIR/appcast.xml" <<XML
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"><channel>
<title>Larkdown updates</title><link>https://github.com/mikeokner/Larkdown</link>
<description>Stable Larkdown releases</description><language>en</language><item>
<title>Larkdown $RELEASE_NAME</title>
<sparkle:version>$BUILD_NUMBER</sparkle:version><sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
<sparkle:minimumSystemVersion>13.0</sparkle:minimumSystemVersion>
<enclosure url="https://github.com/mikeokner/Larkdown/releases/download/v$RELEASE_NAME/$ZIP_NAME" $SIGNATURE type="application/octet-stream" />
</item></channel></rss>
XML
    "$SPARKLE_BIN/sign_update" --ed-key-file "$SPARKLE_PRIVATE_KEY_FILE" "$ARTIFACT_DIR/appcast.xml"
    "$SPARKLE_BIN/sign_update" --verify --ed-key-file "$SPARKLE_PRIVATE_KEY_FILE" "$ARTIFACT_DIR/appcast.xml"
fi
if [ -d "$ARCHIVE_PATH/dSYMs/Larkdown.app.dSYM" ]; then
    ditto -c -k --keepParent "$ARCHIVE_PATH/dSYMs/Larkdown.app.dSYM" "$ARTIFACT_DIR/Larkdown-$RELEASE_NAME-macos-universal-dsym.zip"
fi
(cd "$ARTIFACT_DIR" && find . -maxdepth 1 -type f ! -name SHA256SUMS.txt -exec shasum -a 256 {} \; > SHA256SUMS.txt)
echo "Artifacts: $ARTIFACT_DIR"
echo "Archive and staging files: $WORK_DIR"
