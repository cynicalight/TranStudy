# Releasing TranStudy

TranStudy is distributed directly as a macOS 14+ application. Release builds use the stable bundle identifier `com.cynicalight.TranStudy`, Apple hardened runtime, a Developer ID Application signature, Apple notarization, and a stapled ticket. Sparkle 2.9.4 checks the HTTPS appcast at most once per week only when the user enables automatic checks. Automatic downloads and installations are disabled at the framework configuration level, so every update requires an explicit user decision.

## One-time preparation

Install a valid `Developer ID Application` certificate for team `8HC6J9LU7U` in the login keychain. Store notarization credentials with `xcrun notarytool store-credentials <profile>`. The Sparkle private EdDSA key is stored only in the login keychain; its public key is `e0FYHC/ETQiiTfpRq8QHxRleYusmX6weOrlLmY7Xpow=`. Back up the private key to protected offline storage with Sparkle’s `generate_keys -x` command, then remove the exported file from the working machine after confirming the backup.

The private Sparkle key, Apple credentials, certificate exports, and notarization profiles must never be committed, uploaded as release assets, or stored on the web server that hosts GitHub Releases.

## Build and notarize

Start from a clean, reviewed commit. Copy `docs/release-notes-template.md`, fill in the user-visible changes, and run:

```sh
VERSION=1.0.0 \
BUILD_NUMBER=1 \
DEVELOPER_ID_APPLICATION='Developer ID Application: Name (TEAMID)' \
NOTARY_KEYCHAIN_PROFILE='TranStudy-Notary' \
RELEASE_NOTES_FILE='/absolute/path/to/release-notes.md' \
scripts/release.sh
```

The script refuses to overwrite an existing release directory. It archives with the requested marketing version and monotonically increasing build number, verifies the embedded update policy and Sparkle framework, checks the app signature, creates and signs a drag-to-Applications DMG, submits it with `notarytool`, staples and validates the ticket, asks Gatekeeper to assess the DMG, and creates a signed `appcast.xml`. It does not create or upload a GitHub Release.

## Release acceptance

Before upload, mount the DMG on a clean macOS 14-or-newer test account or Mac, drag TranStudy to Applications, and confirm Gatekeeper launches it without bypass instructions. Complete Safari, Chrome, TextEdit, and Preview selectable-PDF checks using a physical mouse: selection release shows only the indicator; clicking the indicator opens translation; adding the result persists it; the saved item enters review; a review rating advances; and an enabled reminder appears only when a card is due.

Install the prior notarized release, point it at a staging appcast containing the new notarized build, and confirm a valid signed update is offered. Confirm an altered archive and an altered signed appcast are rejected. Confirm automatic checking can be enabled and disabled, no check runs more frequently than weekly, and discovering an update never downloads or installs it without confirmation.

After acceptance, create GitHub Release `v<VERSION>` and upload the generated DMG plus `appcast.xml`. Do not publish the release until both assets are present, because the stable feed URL resolves to the latest release asset. Preserve the `.xcarchive`, dSYMs, notarization submission result, release notes, DMG checksum, and acceptance record outside the public release assets.
