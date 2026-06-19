#!/bin/sh
set -eu

PROJECT="Larkdown.xcodeproj"
SCHEME="Larkdown"
APP_NAME="Larkdown"
CONFIGURATION="${CONFIGURATION:-Release}"
VERSION="${1:-${VERSION:-0.1.0}}"
BUILD_NUMBER="${BUILD_NUMBER:-$(date +%Y%m%d%H%M)}"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-.build/LocalInstallDerivedData}"
INSTALL_DIR="${INSTALL_DIR:-$HOME/Applications}"
DEST_APP="$INSTALL_DIR/$APP_NAME.app"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

echo "Building $APP_NAME $VERSION ($BUILD_NUMBER) for local install..."
xcodebuild \
	-project "$PROJECT" \
	-scheme "$SCHEME" \
	-configuration "$CONFIGURATION" \
	-destination 'platform=macOS' \
	-derivedDataPath "$DERIVED_DATA_PATH" \
	MARKETING_VERSION="$VERSION" \
	CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
	CODE_SIGN_STYLE=Manual \
	CODE_SIGN_IDENTITY="-" \
	build

BUILT_APP="$DERIVED_DATA_PATH/Build/Products/$CONFIGURATION/$APP_NAME.app"

if [ ! -d "$BUILT_APP" ]; then
	echo "Expected app bundle not found: $BUILT_APP" >&2
	exit 1
fi

mkdir -p "$INSTALL_DIR"
rm -rf "$DEST_APP"
ditto "$BUILT_APP" "$DEST_APP"

codesign --verify --deep --strict "$DEST_APP"
"$LSREGISTER" -f "$DEST_APP"

echo "Installed $DEST_APP"
echo "Use Finder > Get Info > Open with to make it the default app for Markdown files."
