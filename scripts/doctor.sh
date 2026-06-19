#!/bin/sh
set -eu

xcode-select -p
xcodebuild -version
swift --version
xcodebuild -list -project Larkdown.xcodeproj
