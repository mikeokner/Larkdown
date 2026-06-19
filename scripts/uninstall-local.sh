#!/bin/sh
set -eu

APP_NAME="Larkdown"
INSTALL_DIR="${INSTALL_DIR:-$HOME/Applications}"
APP_PATH="$INSTALL_DIR/$APP_NAME.app"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

case "$APP_PATH" in
	*/Larkdown.app)
		;;
	*)
		echo "Refusing to uninstall unexpected app path: $APP_PATH" >&2
		exit 2
		;;
esac

if [ ! -d "$APP_PATH" ]; then
	echo "$APP_PATH is not installed."
	exit 0
fi

"$LSREGISTER" -u "$APP_PATH" 2>/dev/null || true
rm -rf "$APP_PATH"

echo "Removed $APP_PATH"
