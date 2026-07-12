# Mäuse 1.2.0 Submission Checklist

## Developer account and app record

- [x] Apple Developer Program membership is active (confirmed by account holder July 12, 2026).
- [x] All updated Apple agreements have been accepted (confirmed by account holder July 12, 2026).
- [ ] App record uses bundle ID `com.michaeldiestelberg.maeuse`.
- [ ] Primary language is English (U.S.); German localization is added.
- [ ] App name `Mäuse` is reserved.
- [ ] Primary category is Finance; secondary category is Lifestyle.
- [ ] Price is Free.
- [ ] Availability/storefronts are selected.
- [ ] DSA status is entered in App Store Connect as **EU non-trader** (account-holder decision confirmed July 12, 2026).
- [ ] Updated 2026 age-rating questionnaire is complete.
- [ ] Content-rights question is answered accurately for the OpenAI integration.
- [ ] Compliance questions are entered from `compliance-answers.md` and rechecked against the live form.

## Public URLs

- [ ] `https://xn--muse-loa.app/` is deployed and loads without authentication.
- [ ] `https://xn--muse-loa.app/privacy.html` is deployed.
- [ ] `https://xn--muse-loa.app/support.html` is deployed and includes working contact information.
- [ ] `https://xn--muse-loa.app/terms.html` is deployed.
- [ ] Website “coming soon” links are replaced with the final App Store URL after Apple provides the numeric app ID.
- [ ] If the site/app is operated commercially in Germany, the website legal notice contains the legally required complete postal address and other provider details.

## App Store metadata

- [ ] English name, subtitle, description, promotional text, and keywords are entered from `metadata-en.md`.
- [ ] German localization is entered from `metadata-de.md`.
- [ ] Support, marketing, and privacy URLs are entered.
- [ ] Copyright is `2026 Michael Diestelberg` or the exact rights-owning legal entity.
- [ ] Four English 6.9-inch screenshots are uploaded in the planned order.
- [ ] Four German 6.9-inch screenshots are uploaded in the planned order.
- [x] Prepared screenshots contain no real personal data or secret API key.

## Privacy and compliance

- [ ] App Privacy answers are published using `privacy-answers.md`.
- [ ] Accessibility Nutrition Labels are entered conservatively using `compliance-answers.md`.
- [ ] Privacy Policy URL is entered in App Privacy.
- [x] Voice Mode consent screen and withdrawal path are present in the selected build.
- [x] Microphone purpose string accurately describes OpenAI streaming.
- [x] Export compliance confirms only exempt/system encryption is used; `ITSAppUsesNonExemptEncryption` remains `false`.
- [x] No IDFA, tracking, advertising, or app analytics are introduced after this audit.
- [x] Current OpenAI Realtime retention and training statements were checked on July 12, 2026; recheck if submission occurs later.

## Build and device QA

- [ ] Full Xcode 26 or later is selected: `sudo xcode-select -s /Applications/Xcode.app/Contents/Developer`.
- [x] Marketing version is `1.2.0`.
- [ ] Build number is incremented above every previously uploaded build.
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
- [ ] Archive is uploaded to App Store Connect.
- [ ] Build finishes processing without missing-compliance warnings.
- [ ] TestFlight information is entered from `testflight.md`.
- [ ] At least one physical-iPhone TestFlight pass covers the listed critical flows.
- [ ] Correct build is selected for version 1.2.0.
- [ ] Temporary OpenAI review project/key is created with a low usage limit.
- [ ] Temporary key and reviewer phone number are entered only in App Store Connect review information.
- [ ] App Review notes are copied from `review-notes.md` and checked for accuracy.
- [ ] Release method is Manual Release.
- [ ] Version is added to review and submitted.

## After approval

- [ ] Final numeric App Store URL replaces every “coming soon” link on the website.
- [ ] Website badge and call-to-action are changed to “Now on the App Store.”
- [ ] Production website is redeployed and links are tested.
- [ ] App is manually released.
- [ ] Store availability is checked in English and German storefront views.
- [ ] Temporary reviewer API key is revoked.
- [ ] Support inbox and App Store Connect notifications are monitored.
