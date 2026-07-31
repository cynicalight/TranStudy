# Releasing TranStudy

TranStudy is distributed as a macOS 14+ DMG through GitHub Releases. Every public release must use the stable bundle identifier `com.cynicalight.TranStudy`, a Developer ID Application certificate from the same Apple Developer team, and Apple notarization. This keeps the app's designated requirement stable across updates so macOS can retain privacy permissions. Sparkle 2.9.4 checks the HTTPS appcast at most once per week only when the user enables automatic checks. Automatic downloads and installations are disabled at the framework configuration level, so every update requires an explicit user decision.

## One-time preparation

Join the Apple Developer Program, install the project's Developer ID Application certificate in the login keychain, and create a notarization keychain profile:

```sh
xcrun notarytool store-credentials "TranStudy-notary" \
  --apple-id "APPLE_ID" \
  --team-id "8HC6J9LU7U"
```

Export the exact certificate name, team identifier, and profile name before running either release script:

```sh
export DEVELOPER_ID_APPLICATION='Developer ID Application: NAME (8HC6J9LU7U)'
export DEVELOPMENT_TEAM='8HC6J9LU7U'
export NOTARY_KEYCHAIN_PROFILE='TranStudy-notary'
```

The Sparkle private EdDSA key is stored only in the login keychain; its public key is `e0FYHC/ETQiiTfpRq8QHxRleYusmX6weOrlLmY7Xpow=`. Back up the private key to protected offline storage with Sparkle’s `generate_keys -x` command, then remove the exported file from the working machine after confirming the backup.

The private Sparkle key must never be committed, uploaded as a release asset, or stored on the web server that hosts GitHub Releases.

## Build the DMG

Start from a clean, reviewed commit. Copy `docs/release-notes-template.md`, fill in the user-visible changes, and run:

```sh
VERSION=1.0.0 \
BUILD_NUMBER=1 \
RELEASE_NOTES_FILE='/absolute/path/to/release-notes.md' \
DEVELOPER_ID_APPLICATION="$DEVELOPER_ID_APPLICATION" \
DEVELOPMENT_TEAM="$DEVELOPMENT_TEAM" \
NOTARY_KEYCHAIN_PROFILE="$NOTARY_KEYCHAIN_PROFILE" \
scripts/release.sh
```

The script refuses to overwrite an existing release directory. It archives with the requested marketing version and monotonically increasing build number, verifies the embedded update policy and Sparkle framework, signs the app and DMG with Developer ID, submits the DMG to Apple for notarization, staples and validates the ticket, checks Gatekeeper acceptance, creates a SHA-256 checksum, and creates an `appcast.xml` whose update enclosure is signed with Sparkle’s EdDSA key. It rejects ad-hoc signatures, build-specific CDHash designated requirements, a mismatched Team ID, missing Hardened Runtime, and Library Validation exceptions. The script does not create or upload a GitHub Release.

## Build and publish automatically

For a complete release, start from a clean default branch and run:

```sh
scripts/publish-release.sh 1.0.0
```

Release notes are optional. When omitted, the publisher generates notes from Git commits since the previous tag. To provide edited notes instead, pass an additional file without template placeholders:

```sh
scripts/publish-release.sh 1.0.0 /absolute/path/to/release-notes.md
```

In both cases, the publisher records Developer ID signing and Apple notarization in the published notes.

The publisher checks GitHub authentication, the branch and upstream state, existing tags, releases, and output directories before changing the project. It updates `MARKETING_VERSION` in `project.yml`, increments `CURRENT_PROJECT_VERSION` when the marketing version changes, regenerates the Xcode project, commits the version change when needed, builds and verifies the DMG, pushes the default branch, and publishes the DMG, checksum, and signed appcast as the latest GitHub Release. It displays the complete release plan and requires confirmation before making version or publishing changes. `--yes` skips this confirmation for an explicitly authorized non-interactive run.

The automatic publisher creates a normal release rather than a prerelease because the application feed uses GitHub’s `/releases/latest/download/appcast.xml` URL. If any step after the version commit fails, inspect the local commit and release artifacts before retrying; the script never force-pushes or overwrites an existing tag, release, or output directory.

## Release acceptance

Before upload, verify the generated checksum with `(cd build/releases/<VERSION> && shasum -a 256 -c TranStudy-<VERSION>.dmg.sha256)`. Verify the notarization ticket with `xcrun stapler validate build/releases/<VERSION>/TranStudy-<VERSION>.dmg` and Gatekeeper acceptance with `spctl --assess --type open --context context:primary-signature --verbose=2 build/releases/<VERSION>/TranStudy-<VERSION>.dmg`. Mount the DMG on a clean macOS 14-or-newer test account or Mac, drag TranStudy to Applications, and confirm a normal double-click launches it without an Open Anyway workflow.

Complete Safari, Chrome, TextEdit, and Preview selectable-PDF checks using a physical mouse: selection release shows only the indicator; clicking the indicator opens translation; adding the result persists it; the saved item enters review; a review rating advances; and an enabled reminder appears only when a card is due.

Install the prior GitHub DMG release, point it at a staging appcast containing the new build, and confirm a valid signed update is offered. Confirm an altered DMG and an altered signed appcast are rejected. Confirm automatic checking can be enabled and disabled, no check runs more frequently than weekly, and discovering an update never downloads or installs it without confirmation.

After acceptance, create the GitHub Release and upload all public assets together:

```sh
gh release create "v<VERSION>" \
  "build/releases/<VERSION>/TranStudy-<VERSION>.dmg" \
  "build/releases/<VERSION>/TranStudy-<VERSION>.dmg.sha256" \
  "build/releases/<VERSION>/appcast.xml" \
  --title "TranStudy <VERSION>" \
  --notes-file "build/releases/<VERSION>/TranStudy-<VERSION>.md"
```

Do not publish the release until the DMG and `appcast.xml` are both present, because the stable feed URL resolves to the latest release asset. Preserve the `.xcarchive`, dSYMs, release notes, checksum, notarization record, and acceptance record. Never fall back to an ad-hoc or Apple Development signature for a public release: it changes the app identity macOS uses for privacy permissions.
