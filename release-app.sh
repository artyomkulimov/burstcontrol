#!/bin/zsh
# Build and notarize a native-architecture release. Does not install or publish it.
set -euo pipefail
cd "${0:A:h}"
: "${SIGNING_IDENTITY:?Set SIGNING_IDENTITY to your Developer ID Application identity}"
: "${NOTARY_PROFILE:?Set NOTARY_PROFILE to a notarytool Keychain profile}"
if [[ "$SIGNING_IDENTITY" != 'Developer ID Application:'* ]]; then
    print -u2 'A Developer ID Application identity is required for public downloads.'
    exit 1
fi
# Check credentials before spending time building. No secrets go in this script.
xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null
./test.sh
CONFIGURATION=release ./build-app.sh
bundle='dist/Burst Control.app'
codesign -dv "$bundle" 2>&1 | /usr/bin/grep -F 'Authority=Developer ID Application:' >/dev/null
version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$bundle/Contents/Info.plist")
architecture=$(uname -m)
archive="dist/Burst-Control-${version}-macOS-${architecture}.zip"
# A submission archive and final stapled archive are different files.
submission=$(mktemp -d "${TMPDIR:-/tmp}/burst-notary.XXXXXX")
trap 'rm -rf "$submission"' EXIT
ditto -c -k --keepParent "$bundle" "$submission/submission.zip"
xcrun notarytool submit "$submission/submission.zip" --keychain-profile "$NOTARY_PROFILE" --wait --output-format plist > "$submission/result.plist"
if [[ "$(/usr/libexec/PlistBuddy -c 'Print :status' "$submission/result.plist")" != Accepted ]]; then
    print -u2 'Notarization was not accepted. See submission details:'
    cat "$submission/result.plist"
    exit 1
fi
xcrun stapler staple "$bundle"
xcrun stapler validate "$bundle"
codesign --verify --strict --verbose=2 "$bundle"
spctl --assess --type execute --verbose=2 "$bundle"
# ditto updates existing ZIPs, so always build a fresh final archive.
ditto -c -k --keepParent "$bundle" "$submission/release.zip"
mv "$submission/release.zip" "$archive"
(cd dist && shasum -a 256 "${archive:t}" > "${archive:t}.sha256")
print "Release ready: $archive"
