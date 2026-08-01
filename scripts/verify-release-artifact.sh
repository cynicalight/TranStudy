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

assert_plist_value() {
  local key=$1
  local expected=$2
  local actual
  actual=$(/usr/libexec/PlistBuddy -c "Print :$key" "$info_plist")
  if [[ "$actual" != "$expected" ]]; then
    echo "$key must be '$expected', found '$actual'" >&2
    exit 65
  fi
}

assert_plist_value CFBundleIdentifier "$RELEASE_SIGNING_BUNDLE_IDENTIFIER"
assert_plist_value LSMinimumSystemVersion 14.0
assert_plist_value SUFeedURL \
  https://github.com/cynicalight/TranStudy/releases/latest/download/appcast.xml
assert_plist_value SUPublicEDKey e0FYHC/ETQiiTfpRq8QHxRleYusmX6weOrlLmY7Xpow=
assert_plist_value SUEnableAutomaticChecks false
assert_plist_value SUScheduledCheckInterval 604800
assert_plist_value SUAutomaticallyUpdate false
assert_plist_value SUAllowsAutomaticUpdates false
assert_plist_value SUVerifyUpdateBeforeExtraction true
assert_plist_value SURequireSignedFeed true
assert_plist_value SUSignedFeedFailureExpirationInterval 0
assert_plist_value SUEnableSystemProfiling false

if [[ ! -d "$app_path/Contents/Frameworks/Sparkle.framework" ]]; then
  echo "Sparkle.framework is not embedded in the app" >&2
  exit 65
fi

signature_details=$(codesign --display --verbose=4 "$app_path" 2>&1)
if grep -F "Signature=adhoc" <<<"$signature_details" >/dev/null; then
  echo "release app must not use an ad-hoc signature" >&2
  exit 65
fi
if ! grep -F "Authority=$RELEASE_SIGNING_IDENTITY_NAME" \
  <<<"$signature_details" >/dev/null
then
  echo "release app uses the wrong signing authority" >&2
  exit 65
fi
if ! grep -E 'flags=.*runtime' <<<"$signature_details" >/dev/null; then
  echo "release app must enable Hardened Runtime" >&2
  exit 65
fi

normalized_entitlements=$(
  codesign --display --entitlements :- "$app_path" 2>&1 |
    tr -d '[:space:]'
)
if ! grep -F \
  '<key>com.apple.security.cs.disable-library-validation</key><true/>' \
  <<<"$normalized_entitlements" >/dev/null
then
  echo \
    "self-signed release must disable library validation so Sparkle can load" \
    >&2
  exit 65
fi

certificate_sha1=$(tr '[:upper:]' '[:lower:]' <<<"$RELEASE_SIGNING_CERTIFICATE_SHA1")
identity_requirement="identifier \"$RELEASE_SIGNING_BUNDLE_IDENTIFIER\" and certificate leaf = H\"$certificate_sha1\""
expected_requirement="designated => $identity_requirement"
actual_requirement=$(codesign -d -r- "$app_path" 2>&1)
if ! grep -F "$expected_requirement" <<<"$actual_requirement" >/dev/null; then
  echo "release app has an unexpected designated requirement" >&2
  echo "expected: $expected_requirement" >&2
  echo "actual: $actual_requirement" >&2
  exit 65
fi

codesign --verify --deep --strict --verbose=2 "$app_path"
codesign --verify --strict --verbose=2 -R="$identity_requirement" "$app_path"
echo "Release configuration is valid."
