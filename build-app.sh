#!/bin/sh
set -eu
cd -- "$(dirname -- "$0")"
app_bundle="${1:-$PWD/build/Touch Bar.app}"
mkdir -p "$app_bundle/Contents/MacOS" "$app_bundle/Contents/Resources" build/icons
xcrun clang -Os -Wall -Wextra -Werror -fobjc-arc -framework Cocoa render-icons.m -o build/render-icons
build/render-icons build/icons
iconutil -c icns build/icons/AppIcon.iconset -o "$app_bundle/Contents/Resources/AppIcon.icns"
cp build/icons/MenuIcon.png build/icons/MenuIcon@2x.png "$app_bundle/Contents/Resources/"
xcrun clang -Os -Wall -Wextra -Werror -fobjc-arc -mmacosx-version-min=13.0 -framework Cocoa TouchBarApp.m -o "$app_bundle/Contents/MacOS/TouchBarApp"
cp Info.plist "$app_bundle/Contents/Info.plist"
cp LICENSE "$app_bundle/Contents/Resources/LICENSE"
codesign --force --sign - "$app_bundle"
codesign --verify --strict "$app_bundle"
printf 'Готово: %s\n' "$app_bundle"
