#!/bin/bash
# Builds build/Copylens.app.
set -euo pipefail
cd "$(dirname "$0")"

./fetch-onnxruntime.sh
cargo build --release --manifest-path core/Cargo.toml
swift build -c release -Xlinker -L"$PWD/core/target/release"

app=build/Copylens.app
rm -rf "$app"
mkdir -p "$app/Contents/MacOS"
cp .build/release/Copylens "$app/Contents/MacOS/"
cp Resources/Info.plist "$app/Contents/"
mkdir -p "$app/Contents/Resources"
cp Resources/AppIcon.icns "$app/Contents/Resources/"
mkdir -p "$app/Contents/Frameworks"
cp core/vendor/onnxruntime/libonnxruntime.dylib "$app/Contents/Frameworks/"

# A real certificate keeps the Screen Recording grant across rebuilds;
# an ad-hoc signature changes every build, so macOS would ask again each time.
identity=$(security find-identity -v -p codesigning | awk '/^ *1\)/ {print $2}')
codesign --force --sign "${identity:--}" "$app/Contents/Frameworks/libonnxruntime.dylib"
codesign --force --sign "${identity:--}" "$app"
echo "Built $app"
