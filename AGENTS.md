# AGENTS.md

## Cursor Cloud specific instructions

### Platform requirement (read first)

Mäuse is an **iOS 17+ app** written in SwiftUI + SwiftData and built with **Xcode 26 on macOS**
(see `README.md` → *Development*). It **cannot be built, run, or tested on the Linux Cloud Agent
VM.** There is no workaround on Linux:

- The app and test targets import Apple-only frameworks (`SwiftUI`, `SwiftData`, `AVFoundation`,
  `Security`, `UniformTypeIdentifiers`) that do not exist in open-source Swift for Linux.
- Sources are tightly coupled, so no meaningful subset compiles in isolation. For example the
  "Foundation-only" files (`Maeuse/Services/RealtimeEventParser.swift`,
  `Maeuse/Models/VoiceWorkspace.swift`) reference `SplitMode`, which is declared in
  `Maeuse/Models/Expense.swift` (a `SwiftData` file). Installing a Swift Linux toolchain therefore
  does not enable building or running the unit tests.
- Building/running requires the iOS SDK + iOS Simulator, which are macOS-only.

Do **not** spend time trying to install a Swift toolchain, xcodebuild, or a simulator on the Linux
VM — none of it will let you build or run this project. GUI/simulator testing is not possible here.

### There are no installable dependencies

The project is intentionally dependency-light: no package manager, no lockfile, no third-party
SDKs (`README.md` → *Technology*). Nothing needs to be installed to develop it beyond Xcode itself,
so the startup update script is a no-op.

### Build / test / run (macOS only)

Use the commands already documented rather than duplicating them here:

- Open + run: open `Maeuse.xcodeproj`, select the `Maeuse` scheme, run on an iPhone simulator
  (`README.md` → *Development*).
- Command-line tests: the `xcodebuild test` invocation in `README.md` (`-scheme Maeuse`,
  `-destination 'platform=iOS Simulator,name=iPhone 17 Pro'`).
- Version bump / release: `scripts/bump-version.sh` and `RELEASING.md`. Note `bump-version.sh`
  uses `/usr/libexec/PlistBuddy` and `scripts/frame-app-store-screenshots.swift` imports `AppKit`;
  both are macOS-only.

### Voice Mode

Manual expense tracking works with no configuration. Voice Mode is optional and needs a
user-supplied OpenAI API key (with `gpt-realtime-2` access) entered in-app and stored in the iOS
Keychain — it is not driven by an environment variable in this repo.
