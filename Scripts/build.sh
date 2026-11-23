#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export MACOSX_DEPLOYMENT_TARGET=13.0
make -C Vendor/m1ddc
swift build -c release
app="$PWD/build/CRG9 Control.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources" bin
cp .build/release/CRG9Control "$app/Contents/MacOS/CRG9Control"
cp .build/release/crg9-control "$app/Contents/MacOS/crg9-control"
cp Vendor/m1ddc/m1ddc "$app/Contents/Resources/m1ddc"
cp Vendor/m1ddc/LICENSE "$app/Contents/Resources/LICENSE-m1ddc.txt"
cp Packaging/Info.plist "$app/Contents/Info.plist"
swift Scripts/Icon.swift "$PWD/build"
cp build/AppIcon.icns "$app/Contents/Resources/AppIcon.icns"
codesign --force --sign - "$app/Contents/Resources/m1ddc"
codesign --force --sign - "$app/Contents/MacOS/crg9-control"
codesign --force --sign - "$app"
codesign --verify --deep --strict "$app"
printf 'Built %s\n' "$app"
