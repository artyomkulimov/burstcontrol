# GitHub releases

Public downloads are signed with a **Developer ID Application** certificate,
use the hardened runtime, and are notarized and stapled before publication.
This workflow does not enable App Sandbox or change the mouse protocol.

## One-time setup

Install a Developer ID Application certificate and its matching private key in
the signing Mac's Keychain. An Apple Distribution or iOS certificate is not a
substitute. Check with `security find-identity -v -p codesigning`.

Store notarization credentials interactively in Keychain:

```sh
xcrun notarytool store-credentials burstcontrol-notary
```

Follow the prompts for the Apple account, team ID, and app-specific password.
Do not put credentials, exported private keys, or certificates in this repository.
Apple also supports App Store Connect API keys for notarization.

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
