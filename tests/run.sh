#!/bin/sh
set -eu
cd -- "$(dirname -- "$0")/.."
mkdir -p build/tests
xcrun clang -Os -Wall -Wextra -Werror -fobjc-arc -framework Cocoa -framework ApplicationServices tests/test-app.m KeyboardLock.m -o build/tests/test-app
build/tests/test-app
xcrun clang -Os -Wall -Wextra -Werror -fobjc-arc -framework Cocoa -framework ApplicationServices tests/test-colors.m KeyboardLock.m -o build/tests/test-colors
build/tests/test-colors
xcrun clang -Os -Wall -Wextra -Werror -fobjc-arc -framework Cocoa -framework ApplicationServices tests/test-keyboard.m KeyboardLock.m -o build/tests/test-keyboard
build/tests/test-keyboard
plutil -lint Info.plist
sh -n build.sh build-app.sh package.sh tests/run.sh
