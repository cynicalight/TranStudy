# TranStudy

TranStudy is a native macOS app for contextual translation and spaced-repetition learning.

## Requirements

- macOS 14 or later
- Xcode 26 or later
- XcodeGen 2.45 or later when regenerating the Xcode project

## Build and test

Regenerate the checked-in Xcode project after changing `project.yml`:

```sh
xcodegen generate
```

Build the app from the command line:

```sh
xcodebuild build \
  -project TranStudy.xcodeproj \
  -scheme TranStudy \
  -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO
```

Run the full test suite:

```sh
xcodebuild test \
  -project TranStudy.xcodeproj \
  -scheme TranStudy \
  -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO
```
