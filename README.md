# Mäuse

Mäuse is a native iOS expense tracker for couples. It is built for the small, everyday money moments that are easy to forget: groceries, coffee, train tickets, dinner, shared household bits, and anything else two people want to settle later.

The name is German slang for money. Literally, it means "mice."

## Project Status

Mäuse is currently in **internal TestFlight testing**.

It is not available on the App Store, there is no public TestFlight link, and the app should be treated as beta software. Core expense tracking works, the native iOS flow is usable, and the current work is focused on polishing distribution, reliability, voice capture, and the realtime expense-entry experience.

This repository is public so the project can be followed and developed in the open, but the app is not a finished public release yet.

## What It Does

- Track expenses locally on an iPhone.
- Split each expense by percentage or by a fixed partner amount.
- Browse expenses by month and see totals at a glance.
- Add and edit expenses manually.
- Export and import JSON backups.
- Enable an experimental realtime voice workspace for adding expenses by speaking.

The default split is 50 percent, which fits the main use case: two people sharing everyday costs.

## Realtime Voice Entry

Voice mode is the most experimental part of the app.

When enabled, the microphone button opens a full-screen voice workspace. A fresh conversation starts for each session. The user can speak naturally, for example:

> Add groceries for 10 euros and coffee for 5.

The app streams microphone audio to OpenAI Realtime, shows the live transcript/understanding, and maintains one or more draft expenses in the workspace. The user can continue speaking to correct, remove, or add more expenses before saving.

Current voice-mode behavior:

- Uses `gpt-realtime-2`.
- Uses realtime input transcription and text-only model output.
- Supports multiple expenses in one voice session.
- Defaults missing date to today.
- Defaults missing split to 50 percent.
- Saves all active draft expenses when the session ends.
- Stores the user's OpenAI API key in iOS Keychain.
- Connects directly from the app to OpenAI. There is no app-owned token server in the current architecture.

Voice mode is optional. The rest of the app works without an OpenAI API key.

## Privacy And Data

Mäuse is local-first.

- Expense data is stored on device with SwiftData.
- There is no user account system.
- There is no app backend.
- There is no analytics or tracking SDK.
- Backup files are user-exported JSON files.
- Voice mode sends microphone audio and session context to OpenAI only when the user enables voice mode and starts a voice session.
- The OpenAI API key is provided by the user and stored in iOS Keychain on that device.

Anyone using voice mode is responsible for their own OpenAI API usage, billing, and project access.

## Distribution

Current distribution state:

- Internal TestFlight only.
- Not listed on the App Store.
- No public beta link.
- No production support commitments.

The current internal build is used to test the native app on real devices before deciding whether to move toward external TestFlight or App Store submission.

## Versioning

Mäuse uses App Store-friendly versioning:

- `MARKETING_VERSION` is the user-visible app version and maps to `CFBundleShortVersionString`.
- `CURRENT_PROJECT_VERSION` is the upload build number and maps to `CFBundleVersion`.
- `Info.plist` uses build-setting substitution for both values, so the Xcode project is the source of truth.

The marketing version follows `Major.Minor.Patch`:

- Patch: bug fixes and small polish, for example `1.0.0` to `1.0.1`.
- Minor: meaningful user-facing improvements, for example `1.0.0` to `1.1.0`.
- Major: large compatibility, product, or architecture changes, for example `1.0.0` to `2.0.0`.

The build number is a monotonically increasing integer. Increment it before every archive uploaded to App Store Connect or TestFlight, even when the marketing version stays the same.

Use the helper script from the repository root:

```sh
scripts/bump-version.sh build
scripts/bump-version.sh patch
scripts/bump-version.sh minor
scripts/bump-version.sh major
```

For a TestFlight rebuild of the same app version, use `build`. For release notes that would say "fixed" or "polished", use `patch`. For a new feature release, use `minor`. Reserve `major` for a larger product milestone.

## Tech Stack

- SwiftUI for the app UI.
- SwiftData for local persistence.
- Observation for view model state.
- AVFoundation for microphone capture.
- URLSession WebSocket for the OpenAI Realtime connection.
- OpenAI Realtime API for voice expense extraction.
- JSON backup import/export for portability.

Voice mode uses direct WebSocket-based OpenAI Realtime sessions.

## Requirements

To build the app locally:

- macOS with Xcode 16 or newer.
- iOS 17 or newer target device/simulator.
- An Apple developer team for running on a physical device.
- Optional: an OpenAI API key with access to `gpt-realtime-2` for voice mode.

## Running Locally

1. Clone the repository.
2. Open `Maeuse.xcodeproj` in Xcode.
3. Select your Apple development team under Signing & Capabilities.
4. Build and run the `Maeuse` scheme on a simulator or device.

Manual expense tracking works immediately. Voice mode needs a user-provided OpenAI API key:

1. Open Settings in the app.
2. Enter an OpenAI API key.
3. Tap Verify & Save Key.
4. Enable voice mode.
5. Use the microphone button from the main expense screen.

## Testing

The repository includes unit tests for the realtime voice workspace, including:

- Realtime session configuration.
- Realtime event parsing.
- Workspace draft replacement.
- Date and split defaults.
- Raw transcript handling.
- Multi-expense save behavior.

Run tests from Xcode with the `Maeuse` scheme, or use `xcodebuild test` with an available iOS simulator.

## Relationship To The PWA

This app is a native iOS version of the Mäuse expense-splitting idea. Backup files are JSON-based so data can remain portable between implementations.

## License

No open-source license has been selected yet. Until a license is added, all rights are reserved by the repository owner.
