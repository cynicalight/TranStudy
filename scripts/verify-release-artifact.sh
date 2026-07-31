#!/bin/bash

set -euo pipefail

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
if ! grep -F "Signature=adhoc" <<<"$signature_details" >/dev/null; then
  echo "app is not ad-hoc signed" >&2
  exit 65
fi

if grep -E 'flags=.*runtime' <<<"$signature_details" >/dev/null; then
  normalized_entitlements=$(
    codesign --display --entitlements :- "$app_path" 2>&1 |
      tr -d '[:space:]'
  )
  if ! grep -F \
    '<key>com.apple.security.cs.disable-library-validation</key><true/>' \
    <<<"$normalized_entitlements" >/dev/null
  then
    echo \
      "ad-hoc hardened runtime must disable library validation so Sparkle can load without a Team ID" \
      >&2
    exit 65
  fi
fi

echo "Release configuration is valid."
