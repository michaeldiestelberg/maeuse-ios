# Agent notes — Mäuse

## TestFlight distribution (Xcode Cloud)

Internal TestFlight builds are produced by **Xcode Cloud**, not by archiving over SSH on the Mac Mini.

- Workflow: **Maeuse | Default** (App Store Connect → Mäuse → Xcode Cloud)
- Trigger: commit and **push to `main`** (the branch the workflow watches)
- After a successful run, the build is uploaded to App Store Connect and **automatically distributed** to the internal TestFlight testing group via the workflow’s **TestFlight Internal Testing** post-action

When the user asks for a new TestFlight build:

1. Land the feature work on `main` (commit).
2. Bump `CURRENT_PROJECT_VERSION` with `scripts/bump-version.sh build` (or `patch` / `minor` / `major` when the marketing version should change). Update `CHANGELOG.md` / `README.md` for user-facing changes.
3. Push to `origin/main`.
4. Confirm the GitHub commit status **Maeuse | Default** moves from queued → in progress → success, and that the new build appears in TestFlight for internal testers.

Do **not** rely on local `xcodebuild archive` over SSH for routine TestFlight uploads (keychain/codesign is unreliable in headless SSH). Prefer Xcode Cloud.

### Build numbers

Xcode Cloud maintains its own **Next Build Number** in App Store Connect (Xcode Cloud → Settings → Build Number). Keep the repo’s `CURRENT_PROJECT_VERSION` aligned with (or ahead of) builds already on App Store Connect so local and Cloud numbering stay consistent. If Cloud stamps a build number that App Store Connect rejects or that is too low, raise **Next Build Number** in App Store Connect, bump the project to match, and push again.

See [RELEASING.md](RELEASING.md) for versioning commands and release-record checklist items.
