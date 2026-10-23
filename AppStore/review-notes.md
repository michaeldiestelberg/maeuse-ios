# App Review notes — 1.5.0 approval draft

The text below the line is the Notes field. Keep the existing private review contact in App Store Connect. Insert the dedicated review key only there; never commit a key.

---

Mäuse is a shared-expense tracker for iPhone. No login. Offline. Expenses stay on-device (SwiftData). No developer backend, ads, analytics, or IAP.

VERSION 1.5.0

Optional Voice Mode: Apple · On device (on-device speech and Foundation Models; one expense at a time) or OpenAI · Cloud (GPT-Realtime-2.1; continuous capture). Users choose a mode first, review drafts, and save explicitly. OpenAI “What I understood” is request history, not a transcript. Layouts use a wide iPhone Duo inner screen (month totals beside the list).

VOICE MODE AND PRIVACY

OpenAI · Cloud sends microphone audio, spoken expense details, and voice-draft context to OpenAI. First use requires a disclosure covering that sharing, OpenAI’s default retention (up to 30 days for abuse monitoring; not used for training unless the API account owner opts in), and estimated API charges. Turning Voice Mode off stops capture. Deleting the API key withdraws consent; the disclosure is shown again before OpenAI is used next.

Apple · On device stays on the iPhone and shares nothing with a third party. System microphone and speech-recognition permissions only. No in-app disclosure. A missing speech model can download in Settings or on first capture; then it works offline. Never falls back to OpenAI.

The OpenAI key is the user’s, in iOS Keychain. Mäuse does not sell API access. Manual entry works without a key, microphone, Apple Intelligence, or internet.

LOCAL DIAGNOSIS

Settings → Voice Mode shows collapsible “Local diagnosis” only while Apple mode is on and Voice Mode is enabled. Last-turn technical metadata only (no audio, transcript, or amounts). In memory; shared only if the user taps Share.

REVIEW CREDENTIAL

[TEMPORARY_REVIEW_API_KEY]

Active throughout App Review. For optional OpenAI Voice Mode only; no app login. Apple mode needs no key (iOS 26+, Apple Intelligence).

STEPS TO TEST OPENAI VOICE MODE (any supported iPhone)

1. Launch Mäuse and tap Get Started.
2. If asked how to dictate, choose OpenAI · Cloud (recommended, listed first).
3. Open Settings (top-right).
4. Under Voice Mode, enter the review key and tap Verify & Save Key.
5. Enable Voice Mode, accept the disclosure, allow the microphone.
6. Close Settings and tap the microphone. Start listening if needed.
7. Say: “Add groceries for 10 euros and coffee for 5 euros, split both in half.”
8. Review the two drafts. Say: “Change the coffee to 4 euros.”
9. Expand What I understood, then tap Save.

STEPS TO TEST APPLE VOICE MODE (iOS 26+, Apple Intelligence)

1. Settings → Voice Mode → Change → Apple · On device. No disclosure. Allow microphone and speech recognition if asked.
2. If offered, download the speech model and wait until ready.
3. Close Settings, tap the microphone. Say: “Coffee for 4.50 euros.”
4. Check the draft (mic pauses). Tap Save expense. It should confirm and listen for the next one.
5. Say two priced purchases at once, e.g. “Coffee 4.50 and flowers 12.” The app should ask for them one after the other.
6. Tap Done. Saved expenses are in the list.

If Apple Intelligence is unavailable, OpenAI mode and manual entry suffice; Apple mode explains what is missing and does not switch to OpenAI.

BACKUP TESTING

Settings → Backup & Restore exports JSON. Import replaces the ledger only after confirmation. Invalid data is rejected.

BUSINESS MODEL

Free. No subscriptions, unlocks, ads, or referrals. OpenAI may bill the user’s API project for OpenAI Voice Mode. Apple Voice Mode has no API charge.

PRIVACY POLICY
https://xn--muse-loa.app/privacy.html

SUPPORT
https://xn--muse-loa.app/support.html
