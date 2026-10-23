#!/bin/zsh
set -eu
cd "${0:A:h}"
configuration=${CONFIGURATION:-release}
swift build -c "$configuration"
./build-icon.sh
bundle="dist/Burst Control.app"
mkdir -p "$bundle/Contents/MacOS" "$bundle/Contents/Resources"
cp ".build/$configuration/BurstControl" "$bundle/Contents/MacOS/BurstControl"
cp dist/AppIcon.icns "$bundle/Contents/Resources/AppIcon.icns"
cat > "$bundle/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>BurstControl</string>
<key>CFBundleIdentifier</key><string>local.burstcontrol.app</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundleName</key><string>Burst Control</string>
<key>CFBundleDisplayName</key><string>Burst Control</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.1.0</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign --force --sign - "$bundle"
echo "Built: $bundle"
