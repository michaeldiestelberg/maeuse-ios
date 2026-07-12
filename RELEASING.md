# Releasing Mäuse

Mäuse follows Apple's two-part versioning model. The Xcode project is the only source of truth:

- `MARKETING_VERSION` is the user-facing `major.minor.patch` version.
- `CURRENT_PROJECT_VERSION` is the monotonically increasing App Store Connect build number.

The current App Store candidate is **1.2.0 (9)**.

## 1. Choose the version change

Run one command from the repository root:

```sh
scripts/bump-version.sh build  # 1.2.0 (9) -> 1.2.0 (10)
scripts/bump-version.sh patch  # 1.2.0 (9) -> 1.2.1 (10)
scripts/bump-version.sh minor  # 1.2.0 (9) -> 1.3.0 (10)
scripts/bump-version.sh major  # 1.2.0 (9) -> 2.0.0 (10)
```

Use `build` for another upload of the same user-facing release. Never reuse a build number already uploaded to App Store Connect.

## 2. Prepare the release record

Before archiving:

1. Add user-facing changes to `CHANGELOG.md`.
2. Update the current version and status in `README.md`.
3. Update the English and German release notes in `AppStore/` when the App Store version changes.
4. Confirm the submission checklist reflects the build being uploaded.

## 3. Verify the source tree

Confirm the resolved values:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -project Maeuse.xcodeproj -scheme Maeuse -configuration Release -showBuildSettings \
  | grep -E 'MARKETING_VERSION|CURRENT_PROJECT_VERSION|PRODUCT_BUNDLE_IDENTIFIER'
```

Run the unit tests and perform the physical-device checks listed in `AppStore/submission-checklist.md`. A release candidate should also be checked in English and German, light and dark appearance, offline mode, backup import/export, and every Voice Mode consent state.

## 4. Archive and upload

Create a Release archive for Any iOS Device, validate the archive, and upload it to App Store Connect. Wait for processing to finish before assigning the build to TestFlight or an App Store version.

Verify all three identifiers before submission:

- App version
- Build number
- Git commit used for the archive

## 5. Publish the source release

After the release commit is on `main`, create an annotated tag and GitHub Release from that exact commit:

```sh
git tag -a v1.2.0 -m "Mäuse 1.2.0"
git push origin v1.2.0
```

Use the matching section from `CHANGELOG.md` as the GitHub Release notes. Mark the GitHub Release as a pre-release while the App Store build is still under review; promote it after the app is publicly available.
