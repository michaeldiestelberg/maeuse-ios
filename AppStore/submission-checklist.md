# Mäuse 1.2.0 Submission Checklist

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

- [x] English name, subtitle, description, promotional text, and keywords are entered from `metadata-en.md`.
- [x] German localization is entered from `metadata-de.md`.
- [x] Support, marketing, and privacy URLs are entered.
- [x] Copyright is `2026 Michael Diestelberg`.
- [x] Four English 6.9-inch screenshots are uploaded in the planned order.
- [x] Four German 6.9-inch screenshots are uploaded in the planned order.
- [x] Prepared screenshots contain no real personal data or secret API key.

## Privacy and compliance

- [x] App Privacy answers are published using `privacy-answers.md`.
- [ ] Accessibility Nutrition Labels are entered conservatively using `compliance-answers.md`.
- [x] Privacy Policy URL is entered in App Privacy.
- [x] Voice Mode consent screen and withdrawal path are present in the selected build.
- [x] Microphone purpose string accurately describes OpenAI streaming.
- [x] Export compliance confirms only exempt/system encryption is used; `ITSAppUsesNonExemptEncryption` remains `false`.
- [x] No IDFA, tracking, advertising, or app analytics are introduced after this audit.
- [x] Current OpenAI Realtime retention and training statements were checked on July 12, 2026; recheck if submission occurs later.

## Build and device QA

- [ ] Full Xcode 26 or later is selected: `sudo xcode-select -s /Applications/Xcode.app/Contents/Developer`.
- [x] Marketing version is `1.2.1`.
- [x] Build number is incremented above every previously uploaded build (`11`).
- [x] Release archive succeeds with the iOS 26.5 SDK.
- [x] Unit tests pass.
- [x] Xcode Release static analysis succeeds for the app target.
- [ ] App is tested on a physical iPhone running a currently supported iOS version.
- [ ] Manual add, edit, delete, split, month navigation, and totals work.
- [ ] Backup export, import, replacement warning, and malformed-file error handling work.
- [ ] English and German layouts work in light and dark appearance.
- [ ] Voice Mode works with valid, invalid, revoked, and insufficient-credit API keys.
- [ ] Microphone allow, deny, and later-enable flows work.
- [ ] Voice consent accept, decline, disable, withdraw, and re-consent flows work.
- [ ] App remains usable offline with Voice Mode unavailable.
- [ ] Privacy, Support, and Terms links open successfully from Settings.

## Archive and upload

- [x] A Release archive is created successfully for Any iOS Device.
- [x] An App Store Connect distribution-signed IPA exports successfully and passes local signature/archive integrity checks.
- [ ] Xcode Organizer validation passes.
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
- [ ] Build 12 (`1.2.1`, Voice Mode haptics) is uploaded to App Store Connect for Internal TestFlight.
- [ ] Build 13 (`1.2.1`, Voice Mode haptics) is uploaded via Xcode Cloud for Internal TestFlight.

## After approval

- [ ] Final numeric App Store URL replaces every “coming soon” link on the website.
- [ ] Website badge and call-to-action are changed to “Now on the App Store.”
- [ ] Production website is redeployed and links are tested.
- [ ] App is manually released.
- [ ] Store availability is checked in English and German storefront views.
- [ ] Temporary reviewer API key is revoked.
- [ ] Support inbox and App Store Connect notifications are monitored.
