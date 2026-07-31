#!/bin/bash

set -euo pipefail

repo_root=$(cd "$(dirname "$0")/.." && pwd)
cd "$repo_root"

required_variable() {
  local name=$1
  if [[ -z "${!name:-}" ]]; then
    echo "missing required environment variable: $name" >&2
    exit 64
  fi
}

required_variable VERSION
required_variable BUILD_NUMBER
required_variable RELEASE_NOTES_FILE
required_variable DEVELOPER_ID_APPLICATION
required_variable DEVELOPMENT_TEAM
required_variable NOTARY_KEYCHAIN_PROFILE

expected_development_team=8HC6J9LU7U
if [[ "$DEVELOPMENT_TEAM" != "$expected_development_team" ]]; then
  echo "DEVELOPMENT_TEAM must remain $expected_development_team" >&2
  exit 65
fi

if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "VERSION must use semantic version form, for example 1.0.0" >&2
  exit 64
fi

if [[ ! "$BUILD_NUMBER" =~ ^[1-9][0-9]*$ ]]; then
  echo "BUILD_NUMBER must be a positive integer" >&2
  exit 64
fi

if [[ ! -f "$RELEASE_NOTES_FILE" ]]; then
  echo "release notes file does not exist: $RELEASE_NOTES_FILE" >&2
  exit 66
fi

if [[ -n "$(git status --porcelain)" ]]; then
  echo "release builds require a clean Git worktree" >&2
  exit 65
fi

release_root="$repo_root/build/releases/$VERSION"
archive_path="$release_root/TranStudy.xcarchive"
app_path="$archive_path/Products/Applications/TranStudy.app"
dmg_name="TranStudy-$VERSION.dmg"
dmg_path="$release_root/$dmg_name"
package_cache="$repo_root/.build/SourcePackages"
sparkle_tools="$package_cache/artifacts/sparkle/Sparkle/bin"

if [[ -e "$release_root" ]]; then
  echo "release output already exists: $release_root" >&2
  exit 73
fi

mkdir -p "$release_root"
staging_root=$(mktemp -d "${TMPDIR%/}/transtudy-release.XXXXXX")
cleanup() {
  rm -rf "$staging_root"
}
trap cleanup EXIT

xcodegen generate

xcodebuild -resolvePackageDependencies \
  -project TranStudy.xcodeproj \
  -scheme TranStudy \
  -clonedSourcePackagesDirPath "$package_cache"

xcodebuild archive \
  -project TranStudy.xcodeproj \
  -scheme TranStudy \
  -configuration Release \
  -archivePath "$archive_path" \
  -clonedSourcePackagesDirPath "$package_cache" \
  MARKETING_VERSION="$VERSION" \
  CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
  DEVELOPMENT_TEAM="$DEVELOPMENT_TEAM" \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY="$DEVELOPER_ID_APPLICATION" \
  CODE_SIGNING_REQUIRED=YES \
  CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO \
  OTHER_CODE_SIGN_FLAGS=--timestamp

"$repo_root/scripts/verify-release-artifact.sh" "$app_path"

mkdir -p "$staging_root/dmg"
ditto "$app_path" "$staging_root/dmg/TranStudy.app"
ln -s /Applications "$staging_root/dmg/Applications"

hdiutil create \
  -volname "TranStudy $VERSION" \
  -srcfolder "$staging_root/dmg" \
  -ov \
  -format UDZO \
  "$dmg_path"

codesign \
  --force \
  --timestamp \
  --sign "$DEVELOPER_ID_APPLICATION" \
  "$dmg_path"

xcrun notarytool submit \
  "$dmg_path" \
  --keychain-profile "$NOTARY_KEYCHAIN_PROFILE" \
  --wait
xcrun stapler staple "$dmg_path"
xcrun stapler validate "$dmg_path"
spctl \
  --assess \
  --type open \
  --context context:primary-signature \
  --verbose=2 \
  "$dmg_path"

(cd "$release_root" && shasum -a 256 "$dmg_name" > "$dmg_name.sha256")

if [[ ! -x "$sparkle_tools/generate_appcast" ]]; then
  echo "Sparkle generate_appcast tool is unavailable at $sparkle_tools" >&2
  exit 69
fi

release_notes_path="$release_root/TranStudy-$VERSION.md"
cp "$RELEASE_NOTES_FILE" "$release_notes_path"

"$sparkle_tools/generate_appcast" \
  --download-url-prefix \
  "https://github.com/cynicalight/TranStudy/releases/download/v$VERSION/" \
  --link https://github.com/cynicalight/TranStudy \
  --embed-release-notes \
  --maximum-versions 1 \
  --maximum-deltas 0 \
  -o "$release_root/appcast.xml" \
  "$release_root"

if ! grep -F "sparkle:edSignature=" "$release_root/appcast.xml" >/dev/null; then
  echo "generated appcast is missing an EdDSA signature" >&2
  exit 65
fi

echo "Release artifacts are ready in $release_root"
echo "This build is Developer ID signed, notarized, and stapled."
echo "Upload $dmg_name, $dmg_name.sha256, and appcast.xml to GitHub release v$VERSION only after manual acceptance."
