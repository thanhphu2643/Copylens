#!/bin/bash
# Downloads the official ONNX Runtime into core/vendor, once.
set -euo pipefail
cd "$(dirname "$0")"

version=1.31.1
sha256=2e1344a1926ee50eb25b38153cb6992c3567515aef0e677a1a520a1798896d6f
target=core/vendor/onnxruntime
[ -f "$target/.version-$version" ] && exit 0

archive=$(mktemp)
trap 'rm -f "$archive"' EXIT
curl -fsSL -o "$archive" "https://github.com/microsoft/onnxruntime/releases/download/v$version/onnxruntime-osx-arm64-$version.tgz"
echo "$sha256  $archive" | shasum -a 256 -c - >/dev/null

rm -rf "$target"
mkdir -p "$target"
tar -xzf "$archive" -C "$target" --strip-components=1
cp -L "$target/lib/libonnxruntime.$version.dylib" "$target/libonnxruntime.dylib"
touch "$target/.version-$version"
