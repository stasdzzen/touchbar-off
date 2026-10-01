#!/bin/sh
set -eu
cd -- "$(dirname -- "$0")/.."
mkdir -p build/tests
xcrun clang -Os -Wall -Wextra -Werror -fobjc-arc -framework Cocoa tests/test-app.m -o build/tests/test-app
build/tests/test-app
xcrun clang -Os -Wall -Wextra -Werror -fobjc-arc -framework Cocoa tests/test-colors.m -o build/tests/test-colors
build/tests/test-colors
plutil -lint Info.plist
sh -n build.sh build-app.sh package.sh tests/run.sh
