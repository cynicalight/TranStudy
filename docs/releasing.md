# Releasing TranStudy

TranStudy is distributed as a macOS 14+ DMG through GitHub Releases. Because the project does not currently have a paid Apple Developer Program membership, release builds are ad-hoc signed and are not notarized by Apple. The stable bundle identifier remains `com.cynicalight.TranStudy`. Sparkle 2.9.4 checks the HTTPS appcast at most once per week only when the user enables automatic checks. Automatic downloads and installations are disabled at the framework configuration level, so every update requires an explicit user decision.

## One-time preparation

The Sparkle private EdDSA key is stored only in the login keychain; its public key is `e0FYHC/ETQiiTfpRq8QHxRleYusmX6weOrlLmY7Xpow=`. Back up the private key to protected offline storage with Sparkle’s `generate_keys -x` command, then remove the exported file from the working machine after confirming the backup.

The private Sparkle key must never be committed, uploaded as a release asset, or stored on the web server that hosts GitHub Releases.

## Build the DMG

Start from a clean, reviewed commit. Copy `docs/release-notes-template.md`, fill in the user-visible changes, and run:

```sh
VERSION=1.0.0 \
BUILD_NUMBER=1 \
RELEASE_NOTES_FILE='/absolute/path/to/release-notes.md' \
scripts/release.sh
```

The script refuses to overwrite an existing release directory. It archives with the requested marketing version and monotonically increasing build number, verifies the embedded update policy and Sparkle framework, applies an ad-hoc code signature, creates a drag-to-Applications DMG and SHA-256 checksum, and creates an `appcast.xml` whose update enclosure is signed with Sparkle’s EdDSA key. It does not create or upload a GitHub Release.

## Build and publish automatically

For a complete release, prepare final release notes without the template placeholders, start from a clean default branch, and run:

```sh
scripts/publish-release.sh 1.0.0 /absolute/path/to/release-notes.md
```

The publisher checks GitHub authentication, the branch and upstream state, existing tags, releases, and output directories before changing the project. It updates `MARKETING_VERSION` in `project.yml`, increments `CURRENT_PROJECT_VERSION` when the marketing version changes, regenerates the Xcode project, commits the version change when needed, builds and verifies the DMG, pushes the default branch, and publishes the DMG, checksum, and signed appcast as the latest GitHub Release. It displays the complete release plan and requires confirmation before making version or publishing changes. `--yes` skips this confirmation for an explicitly authorized non-interactive run.

The automatic publisher creates a normal release rather than a prerelease because the application feed uses GitHub’s `/releases/latest/download/appcast.xml` URL. If any step after the version commit fails, inspect the local commit and release artifacts before retrying; the script never force-pushes or overwrites an existing tag, release, or output directory.

## Release acceptance

Before upload, verify the generated checksum with `(cd build/releases/<VERSION> && shasum -a 256 -c TranStudy-<VERSION>.dmg.sha256)`. Mount the DMG on a clean macOS 14-or-newer test account or Mac and drag TranStudy to Applications. Because the app is not notarized, a normal double-click may be blocked. In Finder, Control-click TranStudy, choose Open, then confirm Open. If macOS still blocks it, open System Settings → Privacy & Security and choose Open Anyway. Do not tell users that this release is Apple-verified or notarized.

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

Do not publish the release until the DMG and `appcast.xml` are both present, because the stable feed URL resolves to the latest release asset. Preserve the `.xcarchive`, dSYMs, release notes, checksum, and acceptance record. If the project later obtains a Developer ID certificate, restore Developer ID signing and notarization before describing the app as trusted by Gatekeeper.
