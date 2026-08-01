#!/bin/bash

set -euo pipefail

repo_root=$(cd "$(dirname "$0")/.." && pwd)
source "$repo_root/config/GitHubReleaseSigning.sh"

if [[ $# -ne 1 ]]; then
  echo "usage: $0 /path/to/TranStudy.app" >&2
  exit 64
fi

app_path=$1
info_plist="$app_path/Contents/Info.plist"

if [[ ! -f "$info_plist" ]]; then
  echo "missing app Info.plist: $info_plist" >&2
  exit 66
fi

actual_bundle_identifier=$(
  /usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$info_plist"
)
if [[ "$actual_bundle_identifier" != "$RELEASE_SIGNING_BUNDLE_IDENTIFIER" ]]; then
  echo \
    "release bundle identifier must remain $RELEASE_SIGNING_BUNDLE_IDENTIFIER" \
    >&2
  exit 65
fi

identity_pattern="$RELEASE_SIGNING_CERTIFICATE_SHA1 \"$RELEASE_SIGNING_IDENTITY_NAME\""
if ! security find-identity -v -p basic | grep -F "$identity_pattern" >/dev/null; then
  echo \
    "release signing identity is unavailable: $RELEASE_SIGNING_IDENTITY_NAME ($RELEASE_SIGNING_CERTIFICATE_SHA1)" \
    >&2
  exit 69
fi

certificate_sha1=$(
  tr '[:upper:]' '[:lower:]' <<<"$RELEASE_SIGNING_CERTIFICATE_SHA1"
)
identity_requirement="identifier \"$RELEASE_SIGNING_BUNDLE_IDENTIFIER\" and certificate leaf = H\"$certificate_sha1\""
designated_requirement="designated => $identity_requirement"

codesign \
  --force \
  --options runtime \
  --entitlements "$repo_root/config/GitHubRelease.entitlements" \
  --generate-entitlement-der \
  --requirements "=$designated_requirement" \
  --sign "$RELEASE_SIGNING_CERTIFICATE_SHA1" \
  "$app_path"

echo "Signed release app with $RELEASE_SIGNING_IDENTITY_NAME."
