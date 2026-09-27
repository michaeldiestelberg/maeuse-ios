# App Review notes — 1.4.0 approval draft

The text below is proposed for the Notes field. The existing private review contact is retained in App Store Connect. Insert the confirmed dedicated review key only in App Store Connect; never commit a key to this repository.

---

Mäuse is a shared-expense tracker for iPhone. The core app requires no login and works offline. Expenses are stored on-device with SwiftData. There is no developer-operated backend, advertising, app analytics, or in-app purchase.

VERSION 1.4.0

This update introduces GPT-Realtime-2.1 voice capture without a separate transcription service, a redesigned draft-review interface, and layout and reliability improvements for iOS 27. Users review and explicitly save voice drafts. “What I understood” is a history of interpreted requests and corrections, not a verbatim transcript.

VOICE MODE AND PRIVACY

Voice Mode is optional. Before enabling it, users must accept a disclosure explaining that microphone audio, spoken expense details, and voice-draft context are sent directly to OpenAI. The disclosure covers default retention and possible OpenAI API charges. Turning Voice Mode off revokes consent; enabling it again presents the disclosure again. Users can independently remove their saved API key.

The user supplies a compatible OpenAI API key, stored in iOS Keychain. Mäuse does not sell API access, receive revenue from OpenAI, or link to a purchase of API credits. Manual expense entry remains available without a key, microphone access, or internet connection.

REVIEW CREDENTIAL

[TEMPORARY_REVIEW_API_KEY — retain the existing dedicated credential once the account holder confirms it remains active and supports GPT-Realtime-2.1]

The review credential will remain active throughout App Review. It is for testing the optional voice feature; no Mäuse account or app login is required.

STEPS TO TEST VOICE MODE

1. Launch Mäuse and tap Get Started.
2. Open Settings using the top-right control.
3. Under Voice Mode, enter the review key and tap Verify & Save Key.
4. Enable Voice Mode, accept the disclosure, and allow microphone access when prompted.
5. Close Settings and tap the microphone button to open Voice Mode. Start listening using the microphone control if the session has not started.
6. Say: “Add groceries for 10 euros and coffee for 5 euros, split both in half.”
7. Review the two expense drafts. Say: “Change the coffee to 4 euros.”
8. Expand What I understood to review the request history, then tap Save.

BACKUP TESTING

Settings → Backup & Restore exports local expenses as JSON. Import replaces the local ledger only after a replacement confirmation. Invalid backup data is rejected before replacement.

BUSINESS MODEL

The app is free, with no subscriptions, paid unlocks, advertising, or referral payments. OpenAI may bill the user's API project for optional Voice Mode usage.

PRIVACY POLICY
https://xn--muse-loa.app/privacy.html

SUPPORT
https://xn--muse-loa.app/support.html
