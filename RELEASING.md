# Releasing Mäuse

Mäuse follows Apple's two-part versioning model. The Xcode project is the source of truth for marketing version; App Store Connect also tracks Xcode Cloud’s **Next Build Number**:

- `MARKETING_VERSION` is the user-facing `major.minor.patch` version.
- `CURRENT_PROJECT_VERSION` is the App Store Connect build number. Keep it aligned with (or ahead of) builds already on App Store Connect, and with Xcode Cloud → Settings → Build Number → **Next Build Number**.

App Store live: **1.2.0 (9)**. Internal TestFlight: see `README.md` for the current `1.3.0` build. Version `1.2.1` shipped only to TestFlight and is superseded by `1.3.0`.

## 1. Choose the version change

Run one command from the repository root:

```sh
scripts/bump-version.sh build  # 1.3.0 (23) -> 1.3.0 (24)
scripts/bump-version.sh patch  # 1.3.0 (23) -> 1.3.1 (24)
scripts/bump-version.sh minor  # 1.3.0 (23) -> 1.4.0 (24)
scripts/bump-version.sh major  # 1.3.0 (23) -> 2.0.0 (24)
```

Use `build` for another upload of the same user-facing release. Never reuse a build number already uploaded to App Store Connect.

## 2. Prepare the release record

Before shipping a build:

1. Add user-facing changes to `CHANGELOG.md`.
2. Update the current version and status in `README.md`.
3. Update `AppStore/release-notes.md` (English and German user-facing notes) when the App Store version changes; mirror the long form on the marketing site changelog.
4. Confirm the submission checklist reflects the build being uploaded.

## 3. Verify the source tree

Confirm the resolved values:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -project Maeuse.xcodeproj -scheme Maeuse -configuration Release -showBuildSettings \
  | grep -E 'MARKETING_VERSION|CURRENT_PROJECT_VERSION|PRODUCT_BUNDLE_IDENTIFIER'
```

Run the unit tests and perform the physical-device checks listed in `AppStore/submission-checklist.md`. A release candidate should also be checked in English and German, light and dark appearance, offline mode, backup import/export, and every Voice Mode consent state.

## 4. Build and distribute (Xcode Cloud)

Routine Internal TestFlight builds use **Xcode Cloud** workflow **Maeuse | Default**:

1. Commit the version bump and release-record updates on `main`.
2. Push to `origin/main`. That starts the workflow.
3. Wait for the GitHub commit status **Maeuse | Default** to succeed.
4. Confirm the build appears in TestFlight. The workflow’s **TestFlight Internal Testing** post-action distributes it to the internal testing group automatically.

Xcode Cloud assigns the App Store Connect build number from its **Next Build Number** setting. If that counter drifts below builds already on App Store Connect, raise it in App Store Connect → Xcode Cloud → Settings → Build Number, bump `CURRENT_PROJECT_VERSION` to match, and push again.

For App Store submission, pick a processed build in App Store Connect (from Cloud or a local Organizer upload), attach it to the version, and submit. Local Organizer archive/upload remains optional when Cloud is unavailable; prefer Cloud for day-to-day TestFlight.

Verify before treating a build as the release candidate:

- App version
- Build number
- Git commit that triggered the Cloud build (or that produced the archive)

## 5. Publish the source release

After the release commit is on `main`, create an annotated tag and GitHub Release from that exact commit:

```sh
git tag -a v1.2.0 -m "Mäuse 1.2.0"
git push origin v1.2.0
```

Use the matching section from `CHANGELOG.md` as the GitHub Release notes. Mark the GitHub Release as a pre-release while the App Store build is still under review; promote it after the app is publicly available.

See [AGENTS.md](AGENTS.md) for agent-oriented TestFlight / Xcode Cloud notes.
