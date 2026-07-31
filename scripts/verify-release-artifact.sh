#!/bin/bash

set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "usage: $0 /path/to/TranStudy.app" >&2
  exit 64
fi

app_path=$1
info_plist="$app_path/Contents/Info.plist"
expected_development_team=8HC6J9LU7U

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

assert_plist_value CFBundleIdentifier com.cynicalight.TranStudy
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
if ! grep -F "Authority=Developer ID Application:" <<<"$signature_details" >/dev/null; then
  echo "release app must be signed with a Developer ID Application certificate" >&2
  exit 65
fi
if ! grep -F "TeamIdentifier=$expected_development_team" <<<"$signature_details" >/dev/null
then
  echo "release app must be signed by Team ID $expected_development_team" >&2
  exit 65
fi
if ! grep -E 'flags=.*runtime' <<<"$signature_details" >/dev/null; then
  echo "release app must enable Hardened Runtime" >&2
  exit 65
fi
if codesign --display --entitlements :- "$app_path" 2>&1 |
  grep -F "com.apple.security.cs.disable-library-validation" >/dev/null
then
  echo "release app must not disable library validation" >&2
  exit 65
fi
designated_requirement=$(codesign -d -r- "$app_path" 2>&1)
if grep -F "cdhash" <<<"$designated_requirement" >/dev/null; then
  echo "release app has a build-specific designated requirement" >&2
  exit 65
fi

codesign --verify --deep --strict --verbose=2 "$app_path"
echo "Release configuration is valid."
