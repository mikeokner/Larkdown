#!/bin/sh
set -eu

xcodebuild \
	-project Larkdown.xcodeproj \
	-scheme Larkdown \
	-configuration "${CONFIGURATION:-Debug}" \
	-destination 'platform=macOS' \
	-derivedDataPath .build/DerivedData \
	build
