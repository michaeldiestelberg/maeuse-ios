# Releasing Mäuse

Mäuse follows Apple's two-part versioning model:

- `MARKETING_VERSION` is the user-facing version shown in the App Store, using `major.minor.patch` format (for example, `1.2.0`).
- `CURRENT_PROJECT_VERSION` is the internal build number. It must increase for every App Store Connect upload, even when the marketing version stays the same.

The Xcode project uses Apple Generic Versioning for build numbers. Set the user-facing version in Xcode under **Mäuse target > General > Identity > Version**. Then increment the build number from the repository root before every upload:

```sh
xcrun agvtool next-version -all
```

Before uploading, confirm the resolved values:

```sh
xcodebuild -project Maeuse.xcodeproj -scheme Maeuse -configuration Release -showBuildSettings \
  | grep -E 'MARKETING_VERSION|CURRENT_PROJECT_VERSION'
```

Create a Release archive, validate it, and upload it through Xcode Organizer. Never reuse a build number that has already been uploaded to App Store Connect.
