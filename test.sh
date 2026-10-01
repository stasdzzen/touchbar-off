#!/bin/sh
set -eu
cd -- "$(dirname -- "$0")"
mkdir -p build
xcrun clang -Os -Wall -Wextra -Werror -fobjc-arc -framework Cocoa test-app.m -o build/test-app
build/test-app
plutil -lint Info.plist
sh -n build.sh build-app.sh package.sh test.sh
