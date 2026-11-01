#!/bin/bash
# Builds build/Copylens-<version>.dmg with the app and an Applications shortcut.
set -euo pipefail
cd "$(dirname "$0")"

./build.sh

version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)
dmg="build/Copylens-$version.dmg"
staging=$(mktemp -d)
trap 'rm -rf "$staging"' EXIT

cp -R build/Copylens.app "$staging/"
ln -s /Applications "$staging/Applications"
hdiutil create -volname Copylens -srcfolder "$staging" -format UDZO -ov "$dmg"
echo "Built $dmg"
