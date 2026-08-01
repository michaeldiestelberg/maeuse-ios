# App Review Notes — Copy Template

Replace the bracketed credential placeholders in App Store Connect. Do not commit a real key here.

---

Mäuse is a local-first shared-expense tracker for iPhone. The core app requires no login and works without a network connection. Expense records are stored on-device with SwiftData. There is no developer-operated backend, advertising SDK, app analytics SDK, or in-app purchase.

VOICE MODE

Voice Mode is optional and is the only feature that transmits user content off-device. It sends live microphone audio and spoken expense details directly to OpenAI's Realtime API to create temporary expense drafts. Before Voice Mode can be enabled, the app presents a dedicated disclosure describing the recipient, data types, default retention, and possible OpenAI API charges, and requires explicit consent. Consent is tied to the Voice Mode switch in Settings: turning Voice Mode off revokes the stored consent, and turning it back on presents the disclosure again.

Voice Mode uses an API key supplied by the user and stored in iOS Keychain. Mäuse does not receive revenue from OpenAI API usage and contains no link or call to action to purchase API credits.

REVIEW CREDENTIAL

Use this temporary OpenAI project key only for App Review:

[TEMPORARY_REVIEW_API_KEY]

The key belongs to a dedicated review project with a low usage limit and will remain active throughout review.

STEPS TO TEST VOICE MODE

1. Launch Mäuse and complete the welcome screen.
2. Open Settings using the top-right control.
3. Under Voice Mode, enter the temporary key above.
4. Tap “Verify & Save Key.”
5. Enable Voice Mode.
6. Review the disclosure and tap “Agree & Enable Voice Mode.”
7. Close Settings and tap the microphone button.
8. Say: “Add groceries for 10 euros and coffee for 5 euros, split both in half.”
9. Review the two drafts, then tap Save.

The reviewer can turn Voice Mode off in Settings, which revokes consent, and can remove the saved key from Settings.

BACKUP TESTING

Settings → Backup & Restore can export all local expenses as JSON. Import intentionally replaces existing local expenses only after a destructive confirmation.

PRIVACY POLICY

https://xn--muse-loa.app/privacy.html

SUPPORT

https://xn--muse-loa.app/support.html

BUSINESS MODEL

The app is free. There are no purchases, subscriptions, advertisements, referral payments, or paid unlocks sold by the developer. Optional Voice Mode interoperates with the user's existing OpenAI API project. OpenAI may bill that project directly; the developer receives no part of that payment.

CONTACT

Michael Diestelberg
m.diestelberg@gmail.com
[APP_REVIEW_PHONE_NUMBER]

---
