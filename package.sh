#!/bin/bash
#
# package.sh — build MorseRunner and assemble a .app bundle.
#
set -euo pipefail

cd "$(dirname "$0")"

# Prefer the Command Line Tools toolchain when Xcode's license hasn't been
# accepted (common on CI / fresh machines). This avoids silently building with
# a stale or unavailable toolchain, which would ship an outdated binary.
if [ -z "$DEVELOPER_DIR" ] && [ -d /Library/Developer/CommandLineTools ]; then
    # Only redirect if the default `swift` fails (Xcode license prompt, etc.)
    if ! swift --version >/dev/null 2>&1; then
        export DEVELOPER_DIR=/Library/Developer/CommandLineTools
    fi
fi

APP_NAME="MorseRunner"
BUILD_DIR=".build"
BUNDLE="$APP_NAME.app"

echo "==> Building (release)…"
swift build -c release

BIN="$BUILD_DIR/release/$APP_NAME"
if [ ! -f "$BIN" ]; then
  echo "Build binary not found at $BIN"; exit 1
fi

echo "==> Running built-in test suite…"
"$BIN" --run-tests

echo "==> Building (debug for test runner compatibility)…"
swift build

echo "==> Assembling $BUNDLE …"
rm -rf "$BUNDLE"
mkdir -p "$BUNDLE/Contents/MacOS"
mkdir -p "$BUNDLE/Contents/Resources"

cp "$BIN" "$BUNDLE/Contents/MacOS/$APP_NAME"

# Info.plist
cat > "$BUNDLE/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>Morse Runner</string>
    <key>CFBundleDisplayName</key><string>Morse Runner</string>
    <key>CFBundleIdentifier</key><string>com.dxatlas.morserunner</string>
    <key>CFBundleVersion</key><string>1.71</string>
    <key>CFBundleShortVersionString</key><string>1.71</string>
    <key>CFBundleExecutable</key><string>$APP_NAME</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleSignature</key><string>????</string>
    <key>LSMinimumSystemVersion</key><string>11.0</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSMicrophoneUsageDescription</key><string>Morse Runner does not use the microphone.</string>
    <key>NSHumanReadableCopyright</key>
    <string>Copyright (C) 2004-2016 Alex Shovkoplyas, VE3NEA. MPL-2.0.</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
</dict>
</plist>
PLIST

# PkgInfo
printf 'APPL????' > "$BUNDLE/Contents/PkgInfo"

# Resources: data files + icon
cp Sources/MorseRunner/Resources/MASTER.DTA "$BUNDLE/Contents/Resources/"
cp Sources/MorseRunner/Resources/ARRL.LIST "$BUNDLE/Contents/Resources/"
cp Sources/MorseRunner/Resources/MorseRunner.ini "$BUNDLE/Contents/Resources/"

# Build the app icon (.icns) from the generated 1024×1024 Morse-code PNG.
# If the PNG is missing, regenerate it with the Python script.
ICON_SRC="Sources/MorseRunner/Resources/AppIcon-1024.png"
if [ ! -f "$ICON_SRC" ]; then
  (cd Sources/MorseRunner/Resources && python3 make_icon.py) || true
fi
if [ -f "$ICON_SRC" ] && command -v iconutil >/dev/null 2>&1; then
  ICONSET="$BUNDLE/Contents/Resources/AppIcon.iconset"
  rm -rf "$ICONSET"; mkdir -p "$ICONSET"
  # macOS .iconset requires specific filenames/sizes (including @2x Retina variants).
  sips -z 16 16     "$ICON_SRC" --out "$ICONSET/icon_16x16.png"      >/dev/null 2>&1 || true
  sips -z 32 32     "$ICON_SRC" --out "$ICONSET/icon_16x16@2x.png"   >/dev/null 2>&1 || true
  sips -z 32 32     "$ICON_SRC" --out "$ICONSET/icon_32x32.png"      >/dev/null 2>&1 || true
  sips -z 64 64     "$ICON_SRC" --out "$ICONSET/icon_32x32@2x.png"   >/dev/null 2>&1 || true
  sips -z 128 128   "$ICON_SRC" --out "$ICONSET/icon_128x128.png"    >/dev/null 2>&1 || true
  sips -z 256 256   "$ICON_SRC" --out "$ICONSET/icon_128x128@2x.png" >/dev/null 2>&1 || true
  sips -z 256 256   "$ICON_SRC" --out "$ICONSET/icon_256x256.png"    >/dev/null 2>&1 || true
  sips -z 512 512   "$ICON_SRC" --out "$ICONSET/icon_256x256@2x.png" >/dev/null 2>&1 || true
  sips -z 512 512   "$ICON_SRC" --out "$ICONSET/icon_512x512.png"    >/dev/null 2>&1 || true
  cp "$ICON_SRC"         "$ICONSET/icon_512x512@2x.png"
  iconutil -c icns "$ICONSET" -o "$BUNDLE/Contents/Resources/AppIcon.icns" 2>/dev/null || true
  rm -rf "$ICONSET"
fi

echo "==> Done: $BUNDLE"
echo "    Run with: open $BUNDLE"
