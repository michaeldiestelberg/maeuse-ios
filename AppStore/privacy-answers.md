# Recommended App Privacy Answers

These answers reflect Mäuse 1.2.0 with Voice Mode enabled and OpenAI's default API retention controls as documented on July 12, 2026.

## Does this app collect data?

Select **Yes, we collect data from this app**.

Although the developer does not operate a backend, Voice Mode transmits data to a third-party service and OpenAI may retain Realtime API customer content in abuse-monitoring logs for up to 30 days by default. Under Apple's definition, this is collection by a third-party partner.

## Data types

### Audio Data

- Collected: Yes
- Purpose: App Functionality
- Linked to the user: Yes
- Used for tracking: No

Rationale: live microphone audio is sent to OpenAI. Requests are authenticated to the user's OpenAI API project, so the conservative and supportable answer is that the data may be linked to that account.

### Other Financial Info

- Collected: Yes
- Purpose: App Functionality
- Linked to the user: Yes
- Used for tracking: No

Rationale: Voice Mode specifically asks users to speak expense amounts, descriptions, dates, and split details. This is financial information rather than merely an unrestricted generic text field.

### Other User Content

- Collected: Yes
- Purpose: App Functionality
- Linked to the user: Yes
- Used for tracking: No

Rationale: spoken expense descriptions and related free-form details are sent to OpenAI during an optional Voice Mode session. Some of that content may not fit solely within Apple's financial-information category, so this is the conservative disclosure.

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

## Privacy links

- Privacy Policy: `https://xn--muse-loa.app/privacy.html`
- Privacy Choices: `https://xn--muse-loa.app/privacy.html#voice-mode`

## Review before submission

Reconfirm OpenAI's current `/v1/realtime` retention policy immediately before submission. If the implementation or OpenAI account configuration changes—for example, an approved Zero Data Retention project is used—update these answers only after verifying the production behavior.
