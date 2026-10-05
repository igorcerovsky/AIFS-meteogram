#!/usr/bin/env bash
set -e

# Script to build and package MeteogramApp.ipa without requiring a paid Apple Developer Account

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "🔨 Building MeteogramApp for iOS (Release)..."
rm -rf build/Release-iphoneos build/Payload build/MeteogramApp.ipa

xcodebuild -project MeteogramApp.xcodeproj \
    -scheme MeteogramApp \
    -configuration Release \
    -destination 'generic/platform=iOS' \
    CODE_SIGN_IDENTITY="" \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGNING_ALLOWED=NO \
    build CONFIGURATION_BUILD_DIR="./build/Release-iphoneos" \
    -quiet

echo "📦 Packaging into MeteogramApp.ipa..."
mkdir -p build/Payload
cp -R build/Release-iphoneos/MeteogramApp.app build/Payload/
(cd build && zip -r -q MeteogramApp.ipa Payload)
rm -rf build/Payload

echo "✅ MeteogramApp.ipa successfully created at:"
echo "   $SCRIPT_DIR/build/MeteogramApp.ipa"
echo ""
echo "📲 You can now AirDrop this file to your iPhone and install it in SideStore / AltStore!"
