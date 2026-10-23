# Recommended App Privacy Answers

These answers reflect Mäuse 1.5.0 with optional OpenAI Voice Mode and optional Apple on-device Voice Mode. OpenAI's default API retention controls were rechecked on October 23, 2026.

## Does this app collect data?

Select **Yes, we collect data from this app**.

Although the developer does not operate a backend, OpenAI Voice Mode transmits data to a third-party service and OpenAI may retain Realtime API customer content in abuse-monitoring logs for up to 30 days by default. Under Apple's definition, this is collection by a third-party partner.

Apple · On device does **not** send audio or expense details off the iPhone. Nutrition Labels describe what the app *can* collect (OpenAI mode), not what every session collects. Do not remove the existing labels because of Apple mode.

## Data types

### Audio Data

- Collected: Yes
- Purpose: App Functionality
- Linked to the user: Yes
- Used for tracking: No

Rationale: live microphone audio is sent to OpenAI in OpenAI mode. Requests are authenticated to the user's OpenAI API project, so the conservative and supportable answer is that the data may be linked to that account. Apple mode audio stays on the device and is not saved by Mäuse.

### Other Financial Info

- Collected: Yes
- Purpose: App Functionality
- Linked to the user: Yes
- Used for tracking: No

Rationale: OpenAI Voice Mode specifically asks users to speak expense amounts, descriptions, dates, and split details, and also sends the current voice-draft workspace. This is financial information rather than merely an unrestricted generic text field.

### Other User Content

- Collected: Yes
- Purpose: App Functionality
- Linked to the user: Yes
- Used for tracking: No

Rationale: spoken expense descriptions and related free-form details are sent to OpenAI during an optional OpenAI Voice Mode session. Some of that content may not fit solely within Apple's financial-information category, so this is the conservative disclosure.

## Do not select

- Advertising data
- Device ID
- Product interaction
- Crash or performance data
- Purchases
- Contact information
- Location
- Tracking

The iPhone app contains no advertising or analytics SDK. Vercel Web Analytics runs on the public website, not inside the iPhone app, so it is not part of the app's Privacy Nutrition Label.

Local diagnosis in Settings exports technical metadata only (version, OS, model variant, timing, error category) if the user taps Share. It is not an analytics SDK, is not written to disk, and contains no audio, transcript, or amounts. Do not add a new data type for it.

## Privacy links

- Privacy Policy: `https://xn--muse-loa.app/privacy.html`
- Privacy Choices: `https://xn--muse-loa.app/privacy.html#voice-mode`

## Review before submission

Reconfirm OpenAI's current `/v1/realtime` retention policy immediately before submission. Rechecked October 23, 2026: no training by default, 30-day abuse monitoring, no application-state retention, ZDR-eligible. If the implementation or OpenAI account configuration changes—for example, an approved Zero Data Retention project is used—update these answers only after verifying the production behavior.

Source: https://developers.openai.com/api/docs/guides/your-data

Existing privacy labels should be preserved; Apple on-device Voice Mode introduces no new collected-data category. Publish the Apple-mode and consent-wording updates in `1.5.0-website-updates.md` on the privacy page when 1.5.0 is released, not before.

## Required Reason APIs (privacy manifest)

Nutrition Labels above are collected-data categories. Separately, App Store Connect validates `PrivacyInfo.xcprivacy`.

| API | Reason | Bundles | In build 65? |
| --- | --- | --- | --- |
| `NSPrivacyAccessedAPICategoryUserDefaults` | `CA92.1` | App and Controls | Yes |
| `NSPrivacyAccessedAPICategorySystemBootTime` | `35F9.1` (elapsed time between events) | App only | Yes — merged in #17. Apple Voice Mode uses `ProcessInfo.systemUptime` to time speech endpoints. |

Do not add System Boot Time to Nutrition Labels. It is not collected data.
