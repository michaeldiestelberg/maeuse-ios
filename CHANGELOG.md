# Changelog

This file records user-facing changes to Mäuse. App Store and GitHub release notes should be based on the matching version section.

## 1.3.1 (45) — 2026-09-21

Internal TestFlight candidate with the pre-release review fixes; follows build 44.

- Backup import rejects unsupported amounts, invalid split values, and invalid dates before changing the ledger. Invalid split values already stored can be displayed and corrected without crashing.
- Backup replacement uses an isolated transaction so a failed save leaves the live ledger intact.
- Manually removed voice drafts stay removed when an older result arrives. Closing a session also rejects delayed callbacks from that connection.
- Failed, incomplete, and malformed voice responses show an error and preserve existing drafts. Only successfully completed structured results update the workspace.
- Explicitly invalid voice dates require correction before saving; omitted dates still default to today.
- Audio interruptions and device changes stop the listening indicator and offer **Resume listening**, preserving drafts and request history.

## 1.3.1 — 2026-09-15

Internal TestFlight candidate (build 44; follows build 42).

- The expense editor, calendar, and monthly overview adapt to shorter windows. Save and Cancel stay visible while the editor content scrolls.
- JSON backup export uses the current system sharing API, with the same portable backup format and iOS 17 support. Restoring a backup saves the replacement together and rolls back if saving fails.
- Voice Mode closes without blocking the interface on audio-session shutdown, and closing during connection setup cancels the pending connection.
- Fixed editing amounts above €1,000 in English and German, preserving the amount and partner share.

- Every spoken request now has a processing animation: three cheese crumbs orbit inside the mouse until its result appears, moving to the rim when you speak again while work is pending.
- Removed the empty first-expense placeholder. New drafts slide into place; corrections briefly highlight only the changed fields.
- Processing feedback preserves pending requests across overlapping speech and response completion. Reduce Motion shows stationary crumbs, and VoiceOver retains activity labels.

- Simplified Voice Mode: Save uses a static label, the request history opens directly into its entries, and the footer shows only the total.
- “What I understood” now keeps a chronological session history of requests and corrections with more natural phrasing. The expanded section uses a subtle timeline; the collapsed section remains title-only. Removing or correcting a draft no longer erases earlier requests.
- Microphone animation now uses a decibel-based display range, making quiet and normal speech visibly stronger than the idle wave. Metering uses the same converted mono audio sent for expense capture.
- The listening mouse now has a gentle wave even in silence, with stronger movement from microphone input. Idle motion stops when the app is inactive and is disabled with Reduce Motion.

- Voice Mode opens with orbiting cheese crumbs that transform into the mouse when microphone capture starts; the mouse's audio bars respond to speech.
- Removed the visible connection/listening labels and repeated dictation hint. VoiceOver keeps the status labels, and Reduce Motion uses a short crossfade.
- Voice Mode now uses GPT-Realtime-2.1 for audio understanding and expense capture, without a separately billed transcription model.
- Voice drafts now stay in a compact vertical list, with a smaller listening header, a static Save button, and a total.
- One expandable “What I understood” / “So habe ich dich verstanden” section replaces the repetitive chat bubbles.
- Voice corrections update and briefly highlight the same card without reordering the list; clarification questions appear separately when information is missing.

## 1.3.0 — 2026-08-01

Released on the App Store (build 32).
- Lock Screen and Control Center controls now start manual or voice expense capture directly, with custom mouse-themed add and microphone icons that match the app's brand.
- Matching Home Screen and Lock Screen widgets provide one-tap access to manual entry or Voice Mode: a small Home Screen widget and two circular Lock Screen widgets.
- Lock Screen widgets now sit on a translucent background so the mouse add and microphone icons stay clearly legible over any wallpaper.
- The expense editor now places deletion in a separate, clearly destructive action below the split control, with native confirmation before an expense is removed.
- When Voice Mode is ready, the mic button is the primary action on the main screen and the plus button is secondary.
- Secondary plus icon uses a crisp white glyph in dark mode for readable contrast.
- Voice Mode adds haptic feedback when listening starts, when new expenses are captured, and a subtler cue when drafts are updated. Haptics can be turned off in Settings.
- Typing a note in the expense editor no longer pushes the sheet off screen: the close and save buttons and the amount stay in place while the keyboard is open, and the number pad returns as soon as you finish typing.

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
