#!/bin/bash
set -euo pipefail

APP_NAME="Miyoi"
BUNDLE="$APP_NAME.app"
MACOS_DIR="$BUNDLE/Contents/MacOS"
RESOURCES_DIR="$BUNDLE/Contents/Resources"
PLIST="$BUNDLE/Contents/Info.plist"

VERSION="${MIYOI_VERSION:-1.0.0}"
BUILD="${MIYOI_BUILD:-1000}"
ARCHS="${MIYOI_ARCHS:-}"

needs_swiftui_macro_plugin() {
	local plugins
	plugins="$(dirname "$(xcrun --find swift-frontend)")/../lib/swift/host/plugins"
	[[ ! -f "$plugins/libSwiftUIMacros.dylib" ]]
}

newest_macro_free_sdk() {
	local sdk_dir sdk
	sdk_dir="$(dirname "$(xcrun --show-sdk-path)")"
	while read -r sdk; do
		if ! grep -rqs "StateMacro" \
			"$sdk/System/Library/Frameworks/SwiftUICore.framework/Modules/SwiftUICore.swiftmodule"; then
			echo "$sdk"
			return 0
		fi
	done < <(find "$sdk_dir" -maxdepth 1 -type d -name 'MacOSX*.sdk' | sort -Vr)
	return 1
}

if [[ -z "${SDKROOT:-}" ]] && needs_swiftui_macro_plugin; then
	if ! SDKROOT="$(newest_macro_free_sdk)"; then
		echo "[x] No usable SDK found: SwiftUI macros need the SwiftUIMacros plugin from full Xcode." >&2
		exit 1
	fi
	export SDKROOT
	echo "[-] Using SDK $(basename "$SDKROOT") (toolchain has no SwiftUIMacros plugin)"
fi

BUILD_FLAGS=(-c release)
for arch in $ARCHS; do
	BUILD_FLAGS+=(--arch "$arch")
done

echo "[-] Building release binary ($VERSION build $BUILD${ARCHS:+, $ARCHS})..."
swift build "${BUILD_FLAGS[@]}" --product miyoi
BIN_DIR="$(swift build "${BUILD_FLAGS[@]}" --show-bin-path)"

echo "[-] Creating app bundle..."
rm -rf "$BUNDLE"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

cp "$BIN_DIR/miyoi" "$MACOS_DIR/$APP_NAME"
cp -R "$BIN_DIR/miyoi_miyoi.bundle" "$RESOURCES_DIR/"

cat > "$PLIST" << PLISTEOF
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
	<string>$VERSION</string>
	<key>CFBundleVersion</key>
	<string>$BUILD</string>
	<key>LSMinimumSystemVersion</key>
	<string>15.0</string>
	<key>NSHighResolutionCapable</key>
	<true/>
	<key>NSPrincipalClass</key>
	<string>NSApplication</string>
</dict>
</plist>
PLISTEOF

echo "[-] Signing ad-hoc..."
codesign --force --sign - "$BUNDLE"

echo "[!] $BUNDLE built successfully!"
echo "Path: $(realpath "$BUNDLE")"
