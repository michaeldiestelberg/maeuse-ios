# Mäuse 1.3.0 Submission Checklist

Items marked `[x]` with a July 2026 date were verified for the 1.2.0 submission and remain
valid for the app record itself. Anything version-specific — metadata, screenshots, build
numbers, device QA — was reset for 1.3.0 and needs re-verification before submitting.

## Developer account and app record

- [x] Apple Developer Program membership is active (confirmed by account holder July 12, 2026).
- [x] All updated Apple agreements have been accepted (confirmed by account holder July 12, 2026).
- [x] App record uses bundle ID `com.michaeldiestelberg.maeuse`.
- [x] Primary language is German; English (U.S.) localization is added.
- [x] App name `Mäuse` is reserved.
- [x] Primary category is Finance; secondary category is Lifestyle.
- [x] Price is Free.
- [x] Availability is set to all 175 storefronts.
- [x] DSA status is entered in App Store Connect as **EU non-trader** (completed July 12, 2026).
- [x] Updated 2026 age-rating questionnaire is complete with a 4+ rating.
- [x] Content-rights question is answered conservatively for the OpenAI integration.
- [x] Compliance questions are entered from `compliance-answers.md` and rechecked against the live form.

## Public URLs

- [x] `https://xn--muse-loa.app/` is deployed and loads without authentication.
- [x] `https://xn--muse-loa.app/privacy.html` is deployed.
- [x] `https://xn--muse-loa.app/support.html` is deployed and includes working contact information.
- [x] `https://xn--muse-loa.app/terms.html` is deployed.
- [ ] Website “coming soon” links are replaced with the final App Store URL after Apple provides the numeric app ID.
- [x] Account holder has classified the app as an EU non-trader; reassess public provider-detail requirements if that status or the commercial operation changes.

## App Store metadata

- [ ] English name, subtitle, description, promotional text, and keywords are re-entered from `metadata-en.md` (updated for 1.3.0 with widgets, Lock Screen, and Control Center).
- [ ] German localization is re-entered from `metadata-de.md` (same 1.3.0 update).
- [x] Support, marketing, and privacy URLs are entered.
- [x] Copyright is `2026 Michael Diestelberg`.
- [x] A fifth scene, `05-widgets`, was captured on iPhone 17 Pro Max showing the Home Screen widget, and framed in both languages.
- [ ] Scenes `01-dashboard`, `02-editor`, `03-voice`, and `04-settings` are re-captured for 1.3.0 — those four still predate widgets, Lock Screen, and Control Center capture.
- [x] Framed screenshots regenerated with `scripts/frame-app-store-screenshots.swift`; all ten carry the new marketing captions.
- [ ] Five English 6.9-inch screenshots are uploaded in the planned order.
- [ ] Five German 6.9-inch screenshots are uploaded in the planned order.
- [ ] Prepared screenshots contain no real personal data or secret API key.
- [ ] `AppStore/release-notes.md` 1.3.0 “What’s New” text is pasted for English (U.S.) and German.
- [ ] The 1.3.0 long form is mirrored on `https://xn--muse-loa.app/changelog.html`.

## Privacy and compliance

- [x] App Privacy answers are published using `privacy-answers.md`.
- [ ] Accessibility Nutrition Labels are entered conservatively using `compliance-answers.md`.
- [x] Privacy Policy URL is entered in App Privacy.
- [x] Voice Mode consent screen is present in the selected build, and consent is revocable by turning Voice Mode off (there is no separate withdrawal button).
- [x] Microphone purpose string accurately describes OpenAI streaming.
- [x] Export compliance confirms only exempt/system encryption is used; `ITSAppUsesNonExemptEncryption` remains `false`.
- [x] No IDFA, tracking, advertising, or app analytics are introduced after this audit.
- [x] Both bundles ship a privacy manifest: `Maeuse/PrivacyInfo.xcprivacy` and `MaeuseControls/PrivacyInfo.xcprivacy` each declare `NSPrivacyAccessedAPICategoryUserDefaults` / `CA92.1` (the extension links `NSUserDefaults` via `CaptureExpenseIntent.perform()`).
- [ ] Current OpenAI Realtime retention and training statements are rechecked (last checked July 12, 2026 — recheck before this submission).

## Build and device QA

- [ ] Full Xcode 26 or later is selected: `sudo xcode-select -s /Applications/Xcode.app/Contents/Developer`.
- [x] Marketing version is `1.3.0`.
- [x] Build number is incremented above every previously uploaded build (`27`; TestFlight already holds 21–24 and 26).
- [ ] Release archive succeeds with the iOS 26.5 SDK.
- [x] Unit tests pass (30 tests, August 1, 2026).
- [x] Xcode Release static analysis succeeds for the app target (the scheme no longer analyzes `MaeuseTests`, whose `@testable import` cannot resolve against a non-testable Release build).
- [x] Release build produces zero compiler warnings across app and extension.
- [ ] App is tested on a physical iPhone running a currently supported iOS version.
- [ ] Manual add, edit, delete, split, month navigation, and totals work.
- [ ] Backup export, import, replacement warning, and malformed-file error handling work. (Import parsing, duplicate-ID rejection, unparseable dates, malformed JSON, and missing fields are now covered by unit tests; the device pass still needs to confirm the UI flow.)
- [ ] Home Screen widget, both Lock Screen widgets, and both Control Center controls each launch the correct capture destination on a physical device.
- [ ] Expense editor stays fully visible with the keyboard open, in both the new-expense and edit layouts.
- [ ] English and German layouts work in light and dark appearance.
- [ ] Voice Mode works with valid, invalid, revoked, and insufficient-credit API keys.
- [ ] Microphone allow, deny, and later-enable flows work.
- [ ] Voice consent accept and decline work, turning Voice Mode off revokes consent, and turning it back on re-presents the disclosure before enabling.
- [ ] App remains usable offline with Voice Mode unavailable.
- [ ] Privacy, Support, and Terms links open successfully from Settings.

## Archive and upload

- [x] A Release archive is created successfully for Any iOS Device.
- [x] An App Store Connect distribution-signed IPA exports successfully and passes local signature/archive integrity checks.
- [ ] Xcode Organizer validation passes, with no ITMS-91053 “missing API declaration” warning for either bundle.
- [x] Build 9, archived from the July 12 source tree, is uploaded to App Store Connect and finishes processing.
- [x] The stale build 8 review submission is removed before resubmission.
- [x] TestFlight information is entered from `testflight.md`; build 9 is validated and assigned to the internal Family group (2 testers).
- [ ] At least one physical-iPhone TestFlight pass covers the listed critical flows.
- [x] Correct build 9 is selected for version 1.2.0.
- [x] Temporary OpenAI review project/key is created with a low usage limit (confirmed by account holder July 12, 2026).
- [x] Temporary key and private reviewer phone number are entered only in App Store Connect review information.
- [x] App Review notes are copied from `review-notes.md`, completed with the temporary key, and checked for accuracy.
- [x] Release method is Manual Release.
- [x] Version 1.2.0 (build 9) is added to review and submitted (July 12, 2026); App Store Connect confirms the replacement submission.
- [x] Build 11 (`1.2.1`, voice-primary FAB) is uploaded to App Store Connect (July 19, 2026) and is processing for Internal TestFlight.
- [x] Build 11 is available to the internal Family group via automatic distribution (confirmed July 19, 2026).
- [x] Builds 12–22 (`1.2.1`) were distributed to Internal TestFlight via Xcode Cloud; build 22 (keyboard-stability fix) succeeded on August 1, 2026. Version 1.2.1 was never submitted to the App Store and is superseded by 1.3.0.
- [x] `CURRENT_PROJECT_VERSION` is synced to 27 to match Xcode Cloud → Settings → **Next Build Number**. Cloud assigns the uploaded number from that counter, not from the repo, which is why repo builds 23 and 25 were published as TestFlight 24 and 26. Keep the two aligned so the repo value and the uploaded build agree.
- [ ] Build 27 (`1.3.0`) is uploaded via Xcode Cloud and reaches Internal TestFlight.
- [ ] Correct build 27 is selected for version 1.3.0 in App Store Connect.
- [ ] Version 1.3.0 (build 27) is added to review and submitted.

## After approval

- [ ] Final numeric App Store URL replaces every “coming soon” link on the website.
- [ ] Website badge and call-to-action are changed to “Now on the App Store.”
- [ ] Production website is redeployed and links are tested.
- [ ] App is manually released.
- [ ] Store availability is checked in English and German storefront views.
- [ ] Temporary reviewer API key is revoked.
- [ ] Support inbox and App Store Connect notifications are monitored.
