# Changelog

This file records user-facing changes to Mäuse. App Store and GitHub release notes should be based on the matching version section.

## 1.2.1 — 2026-07-20

- Lock Screen and Control Center controls now start manual or voice expense capture directly, with clear, optically centered add and microphone icons.
- When Voice Mode is ready, the mic button is the primary action on the main screen and the plus button is secondary.
- Secondary plus icon uses a crisp white glyph in dark mode for readable contrast.
- Voice Mode adds haptic feedback when listening starts, when new expenses are captured, and a subtler cue when drafts are updated. Haptics can be turned off in Settings.

## 1.2.0 — 2026-07-12

Mäuse 1.2.0 is the first App Store-ready release: a focused, local-first way for two people to record and settle everyday expenses.

### Highlights

- Add, edit, delete, and browse expenses by month.
- Split each expense by percentage or an exact partner amount.
- See monthly totals and partner shares at a glance.
- Export and restore portable JSON backups.
- Use the complete interface in English or German.
- Choose light, dark, or system appearance.

### Voice Mode

- Optionally dictate several expenses in one session.
- Review, correct, remove, and add drafts before saving.
- Keep the OpenAI API key in iOS Keychain.
- Manage microphone access, consent, Voice Mode, and the saved key independently.
- Continue using manual expense tracking without an API key or network connection.

### App Store preparation

- Added the final app icon, brand assets, privacy manifest, localized metadata, and screenshot set.
- Added clear in-app privacy explanations and consent withdrawal controls.
- Prepared and submitted version 1.2.0 build 9 for App Review.

## 1.0.0 — 2026-05-14

- Established the native SwiftUI and SwiftData application baseline.
- Added manual shared-expense tracking, monthly navigation, split calculations, settings, and the first internal TestFlight build.
