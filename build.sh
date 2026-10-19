#!/usr/bin/env bash
set -euo pipefail

cd -- "$(dirname -- "${BASH_SOURCE[0]}")"
ROOT="$PWD"
APP_NAME="QuickTodo"
APP_PATH="$ROOT/$APP_NAME.app"
BUILD_DIR="$(mktemp -d "$ROOT/.quicktodo-build.XXXXXX")"
trap 'rm -rf -- "$BUILD_DIR"' EXIT

STAGED_APP="$BUILD_DIR/$APP_NAME.app"
mkdir -p "$STAGED_APP/Contents/MacOS" "$STAGED_APP/Contents/Resources"

SOURCES=("$ROOT/main.swift" "$ROOT"/Sources/*.swift)

# Use --universal when creating a release for both Apple Silicon and Intel Macs.
if [[ "${1:-}" == "--universal" ]]; then
    SDK="$(xcrun --sdk macosx --show-sdk-path)"
    for arch in arm64 x86_64; do
        xcrun swiftc -O -sdk "$SDK" -target "${arch}-apple-macosx14.0" \
            "${SOURCES[@]}" -o "$BUILD_DIR/$APP_NAME-$arch"
    done
    lipo -create "$BUILD_DIR/$APP_NAME-arm64" "$BUILD_DIR/$APP_NAME-x86_64" \
        -output "$STAGED_APP/Contents/MacOS/$APP_NAME"
elif [[ $# -ne 0 ]]; then
    echo "Usage: ./build.sh [--universal]" >&2
    exit 2
else
    SDK="$(xcrun --sdk macosx --show-sdk-path)"
    arch="$(uname -m)"
    xcrun swiftc -O -sdk "$SDK" -target "${arch}-apple-macosx14.0" \
        "${SOURCES[@]}" -o "$STAGED_APP/Contents/MacOS/$APP_NAME"
fi

if [[ -f "$ROOT/icon.png" ]]; then
    ICONSET="$BUILD_DIR/AppIcon.iconset"
    mkdir -p "$ICONSET"
    for size in 16 32 128 256 512; do
        sips -z "$size" "$size" "$ROOT/icon.png" \
            --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
        double_size=$((size * 2))
        sips -z "$double_size" "$double_size" "$ROOT/icon.png" \
            --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
    done
    iconutil -c icns "$ICONSET" -o "$STAGED_APP/Contents/Resources/AppIcon.icns"
fi

cat > "$STAGED_APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>QuickTodo</string>
    <key>CFBundleIdentifier</key><string>local.quicktodo</string>
    <key>CFBundleExecutable</key><string>QuickTodo</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.0.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>LSUIElement</key><true/>
</dict>
</plist>
PLIST

# Ad-hoc signing is for local testing. Public distribution needs Developer ID
# signing and notarization to avoid Gatekeeper warnings.
codesign --force --sign - "$STAGED_APP"
codesign --verify --strict "$STAGED_APP"

# Keep the previous app intact until the replacement has compiled and signed.
PREVIOUS_APP="$BUILD_DIR/previous.app"
if [[ -e "$APP_PATH" ]]; then
    mv -- "$APP_PATH" "$PREVIOUS_APP"
fi
if ! mv -- "$STAGED_APP" "$APP_PATH"; then
    if [[ -e "$PREVIOUS_APP" ]]; then
        mv -- "$PREVIOUS_APP" "$APP_PATH"
    fi
    exit 1
fi

ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$ROOT/$APP_NAME-macOS.zip"
printf 'Built %s and %s\n' "$APP_PATH" "$ROOT/$APP_NAME-macOS.zip"
