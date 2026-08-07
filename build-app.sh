#!/bin/bash
set -euo pipefail

APP_NAME="Miyoi"
BUNDLE="$APP_NAME.app"
MACOS_DIR="$BUNDLE/Contents/MacOS"
RESOURCES_DIR="$BUNDLE/Contents/Resources"
PLIST="$BUNDLE/Contents/Info.plist"

echo "[-] Building release binary..."
swift build -c release --product miyoi

echo "[-] Creating app bundle..."
rm -rf "$BUNDLE"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

cp .build/release/miyoi "$MACOS_DIR/$APP_NAME"

cat > "$PLIST" << 'PLISTEOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDevelopmentRegion</key>
	<string>en</string>
	<key>CFBundleExecutable</key>
	<string>Miyoi</string>
	<key>CFBundleIdentifier</key>
	<string>eu.ellerotta.miyoi</string>
	<key>CFBundleInfoDictionaryVersion</key>
	<string>6.0</string>
	<key>CFBundleName</key>
	<string>Miyoi</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleShortVersionString</key>
	<string>1.0</string>
	<key>CFBundleVersion</key>
	<string>1000</string>
	<key>LSMinimumSystemVersion</key>
	<string>15.0</string>
	<key>NSHighResolutionCapable</key>
	<true/>
	<key>NSPrincipalClass</key>
	<string>NSApplication</string>
</dict>
</plist>
PLISTEOF

echo "[!] $BUNDLE built successfully!"
echo "Path: $(realpath "$BUNDLE")"
