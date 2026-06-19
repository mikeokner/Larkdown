#!/bin/sh
set -eu

# UI tests need an unlocked desktop session, so they run only on request.
# Test builds live outside the checkout: if it is in Documents, Desktop, or
# Downloads, each ad hoc signed rebuild would make macOS ask for folder access.
usage="usage: scripts/test.sh [--ui-tests]"
skip_ui_tests=1
for arg in "$@"; do
    case "$arg" in
        --ui-tests) skip_ui_tests=0 ;;
        *) echo "$usage" >&2; exit 64 ;;
    esac
done
if [ "$skip_ui_tests" = 1 ]; then
    set -- -skip-testing:LarkdownUITests
else
    set --
fi

DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-${TMPDIR:-/tmp}/Larkdown-tests/DerivedData}"

swift test --package-path Packages/LarkdownCore

xcodebuild \
    -project Larkdown.xcodeproj \
    -scheme Larkdown \
    -configuration Debug \
    -parallel-testing-enabled NO \
    -destination 'platform=macOS' \
    -derivedDataPath "$DERIVED_DATA_PATH" \
    -test-timeouts-enabled YES \
    -default-test-execution-time-allowance 60 \
    -maximum-test-execution-time-allowance 120 \
    "$@" \
    test
