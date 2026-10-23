# App Review notes — 1.5.0 approval draft

The text below is proposed for the Notes field. The existing private review contact is retained in App Store Connect. Insert the confirmed dedicated review key only in App Store Connect; never commit a key to this repository.

The OpenAI consent paragraph matches 1.5 product copy. On **build 64** it is true for new consent and false for 1.4 upgraders (their version-1 acceptance is still treated as current). Take `cursor/consent-version-2-5f1a` so those users see this sheet once before you paste these notes.

---

Mäuse is a shared-expense tracker for iPhone. The core app requires no login and works offline. Expenses are stored on-device with SwiftData. There is no developer-operated backend, advertising, app analytics, or in-app purchase.

VERSION 1.5.0

This update adds an optional on-device Voice Mode (Apple speech recognition and Apple Foundation Models) alongside the existing OpenAI · Cloud mode. Users choose a mode before enabling Voice Mode. Apple mode processes one expense at a time entirely on the iPhone. OpenAI mode keeps continuous capture with GPT-Realtime-2.1. Users review and explicitly save voice drafts in both modes. “What I understood” (OpenAI) is a history of interpreted requests and corrections, not a verbatim transcript.

VOICE MODE AND PRIVACY

Voice Mode is optional and offers two modes.

OpenAI · Cloud sends microphone audio, spoken expense details, and voice-draft context directly to OpenAI. Before it is used for the first time, users must accept a disclosure covering that data sharing, OpenAI's default retention (up to 30 days for abuse monitoring; not used for training unless the API account owner opts in), and estimated API charges. Turning Voice Mode off stops all capture and transmission. Deleting the saved API key withdraws consent, and the disclosure is shown again before OpenAI mode is used next.

Apple · On device processes speech and expenses entirely on the iPhone and shares nothing with a third party. It needs only the system microphone and speech recognition permissions. There is no in-app disclosure because no data leaves the device. A missing on-device speech model can be downloaded in Settings or on first capture; afterwards capture works offline. Apple mode never falls back to OpenAI.

The user supplies a compatible OpenAI API key, stored in iOS Keychain, only for OpenAI mode. Mäuse does not sell API access, receive revenue from OpenAI, or link to a purchase of API credits. Manual expense entry remains available without a key, microphone access, Apple Intelligence, or internet connection.

LOCAL DIAGNOSIS

Settings → Voice Mode shows a collapsible “Local diagnosis” section only while Apple mode is selected and Voice Mode is on. It is technical metadata (app/OS/model variant, timing, error category) for the last Apple turn. It contains no audio, transcript, or amounts, is never written to disk, and is shared only if the user chooses Share.

REVIEW CREDENTIAL

[TEMPORARY_REVIEW_API_KEY — retain the existing dedicated credential once the account holder confirms it remains active and supports GPT-Realtime-2.1]

The review credential will remain active throughout App Review. It is for testing the optional OpenAI voice feature; no Mäuse account or app login is required. Apple mode can be tested without this key on an Apple Intelligence–capable iPhone running iOS 26 or later.

STEPS TO TEST OPENAI VOICE MODE (any supported iPhone)

1. Launch Mäuse and tap Get Started.
2. If asked how you would like to dictate, choose OpenAI · Cloud (it is recommended and listed first).
3. Open Settings using the top-right control.
4. Under Voice Mode, enter the review key and tap Verify & Save Key.
5. Enable Voice Mode, accept the disclosure, and allow microphone access when prompted.
6. Close Settings and tap the microphone button to open Voice Mode. Start listening using the microphone control if the session has not started.
7. Say: “Add groceries for 10 euros and coffee for 5 euros, split both in half.”
8. Review the two expense drafts. Say: “Change the coffee to 4 euros.”
9. Expand What I understood to review the request history, then tap Save.

STEPS TO TEST APPLE VOICE MODE (iOS 26+, Apple Intelligence enabled)

1. In Settings → Voice Mode, tap Change and choose Apple · On device. No disclosure is shown. Allow microphone and speech recognition if prompted.
2. If Settings offers Download speech model, tap it and wait until it reports ready.
3. Close Settings and tap the microphone. Say one expense, for example: “Coffee for 4.50 euros.”
4. Check the draft (the microphone pauses). Tap Save expense. The screen should show that it was saved and listen for the next one.
5. Say two priced purchases at once, for example: “Coffee 4.50 and flowers 12.” The app should ask for them one after the other rather than guessing.
6. Tap Done to close. Saved expenses are already in the list.

If Apple Intelligence is not available on the review device, OpenAI mode and manual entry are sufficient; Apple mode will explain what is missing and will not switch to OpenAI.

BACKUP TESTING

Settings → Backup & Restore exports local expenses as JSON. Import replaces the local ledger only after a replacement confirmation. Invalid backup data is rejected before replacement.

BUSINESS MODEL

The app is free, with no subscriptions, paid unlocks, advertising, or referral payments. OpenAI may bill the user's API project for optional OpenAI Voice Mode usage. Apple Voice Mode has no API charge.

PRIVACY POLICY
https://xn--muse-loa.app/privacy.html

SUPPORT
https://xn--muse-loa.app/support.html
