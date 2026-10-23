# GitHub releases

Public downloads are signed with a **Developer ID Application** certificate,
use the hardened runtime, and are notarized and stapled before publication.
This workflow does not enable App Sandbox or change the mouse protocol.

## One-time setup

Install a Developer ID Application certificate and its matching private key in
the signing Mac's Keychain. An Apple Distribution or iOS certificate is not a
substitute. Check with `security find-identity -v -p codesigning`.

Use a dedicated **App Store Connect team API key** for notarization. In App Store
Connect, open Users and Access → Integrations → App Store Connect API. If API
access has not been enabled, the account holder must first accept Apple's API-use
agreement and request access. Create a key with the Developer role, download its
`.p8` private key once, and record its key ID and issuer ID.

Keep the key outside the repository in a private directory with permissions
`700`, and set the key file to `600`. Store and validate the credentials in this
Mac's Keychain without printing the private key:

```sh
xcrun notarytool store-credentials burstcontrol-notary \
  --key '/absolute/private/path/AuthKey_KEYID.p8' \
  --key-id 'KEYID' \
  --issuer 'ISSUER-UUID'
xcrun notarytool history --keychain-profile burstcontrol-notary
```

The key ID and issuer ID are identifiers; the `.p8` contents are secret. Do not
commit private keys or paste them into chat, logs, or release notes. A browser
session does not authenticate `notarytool`; the saved API credentials do. This
workflow does not require an Apple account password or app-specific password.

See Apple's [notarization API authentication documentation](https://developer.apple.com/documentation/notaryapi/submitting-software-for-notarization-over-the-web).

## Build and verify

From the intended clean release commit:

```sh
SIGNING_IDENTITY='Developer ID Application: Your Name (TEAMID)' \
NOTARY_PROFILE=burstcontrol-notary ./release-app.sh
```

The script runs offline protocol checks, builds a release bundle for the host
architecture, signs it with hardened runtime and a secure timestamp, submits it
to Apple, requires an Accepted result, staples the ticket, and verifies Gatekeeper
acceptance. It then produces a ZIP and SHA-256 file in `dist/`.

An Apple silicon build is **arm64**, not universal. Label downloads accordingly;
do not claim Intel compatibility without building and testing an Intel artifact.
The script neither replaces the installed app nor publishes to GitHub.

## Publish

Create a GitHub draft targeting the exact release commit. Attach only the final
stapled ZIP and its checksum, then publish after inspecting its notes and assets.
State macOS/architecture requirements, supported hardware, installation steps,
and any hardware tests that were not performed for this build.

Users extract the ZIP, move Burst Control into Applications, and grant Input
Monitoring before reopening. Switching from an ad-hoc build to Developer ID can
require refreshing the existing permission once. Keep the signing identity and
bundle identifier stable in subsequent updates.

Never publish an ad-hoc build as a signed/notarized release. If signing or
notarization is blocked, keep the release as a draft without a downloadable app.
