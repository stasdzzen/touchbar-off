#!/bin/sh
set -eu
cd -- "$(dirname -- "$0")"
./build-app.sh
./test.sh
app_bundle="$PWD/build/Touch Bar.app"
version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Info.plist)
archs=$(lipo -archs "$app_bundle/Contents/MacOS/TouchBarApp")
mkdir -p dist
archive="$PWD/dist/Touch-Bar-$version-$archs.zip"
ditto -c -k --sequesterRsrc --keepParent "$app_bundle" "$archive"
shasum -a 256 "$archive" | sed "s|$PWD/dist/||" > "$archive.sha256"
printf 'Архив: %s\n' "$archive"
