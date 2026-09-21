# Apple Voice Mode feasibility

Investigated September 15, 2026 against Mäuse build 44 (`11e0c3c`), Apple's current documentation, and the installed Xcode 27.0 (27A266a) SDK. This is a design and feasibility review, not an implemented or released provider.

## Recommendation

Add an optional Apple Intelligence voice provider while retaining OpenAI Realtime as the default for existing users. Evaluate on-device extraction first, with Private Cloud Compute (PCC) available as separately enabled assistance once Apple grants access. Do not route an Apple-selected session to OpenAI automatically.

The APIs exist and the basic integration compiles. Comparable recognition quality, correction behavior, and latency still need measurement on a supported iPhone; this review does not establish parity with OpenAI.

## What Apple provides

| Component | Availability and fit |
| --- | --- |
| SpeechAnalyzer + SpeechTranscriber | iOS 26+ speech-to-text pipeline, with on-device model assets. Handles streaming audio and provisional/final text. Check device/locale support and install required assets. |
| SystemLanguageModel | iOS 26+ on supported Apple Intelligence devices with the model available. Processes text locally and supports structured generation. Works offline after assets are installed, with no daily request quota. |
| PrivateCloudComputeLanguageModel | iOS 27+ API for Apple's server model, with structured generation, a larger context window and reasoning options. Requires network, supported device/region, eligible developer account and managed entitlement. Daily user quota applies. |

Speech must be a separate stage. Mäuse currently sends 24 kHz audio directly to OpenAI Realtime and uses semantic turn detection. The public Apple APIs reviewed do not expose a corresponding continuous audio-to-expense Realtime session. The proposed Apple flow is microphone → on-device speech recognition → finalized utterance plus current draft workspace → Foundation Models → validated draft update.

Both Apple models support `@Generable` output. Valid structure is useful, but does not guarantee a correct amount, date, or correction target. Keep existing monetary validation and explicit Save confirmation.

Sources: [SpeechAnalyzer session](https://developer.apple.com/videos/play/wwdc2025/277/), [SpeechTranscriber](https://developer.apple.com/documentation/speech/speechtranscriber), [Foundation Models updates](https://developer.apple.com/videos/play/wwdc2026/241/), [PCC integration guide](https://developer.apple.com/documentation/foundationmodels/adding-server-side-intelligence-with-private-cloud-compute).

## PCC eligibility and limits

Apple's current access page requires App Store Small Business Program enrollment, fewer than two million first-time downloads under the stated app eligibility criteria, and the PCC entitlement assigned to the developer account. TestFlight and ad hoc distribution can test PCC. If eligibility is lost, Apple specifies a six-month migration period after notification. We have not verified this account's enrollment or entitlement; the current project has no PCC entitlement configured.

There is no cloud API charge to eligible developers or API-key entry for the user. PCC has daily usage limits linked to the user's iCloud account; iCloud+ can increase access. Do not promise a fixed number of daily requests: use `quotaUsage`, `isLimitReached`, reset date and runtime errors. Handle network/service failures and unavailable models explicitly.

Apple describes PCC requests as processed without retaining the user's data. This is cloud processing, so the Settings description must distinguish it from the fully on-device path.

Sources: [Accessing Private Cloud Compute](https://developer.apple.com/private-cloud-compute/), [PCC overview and usage handling](https://developer.apple.com/videos/play/wwdc2026/319/), [model API](https://developer.apple.com/documentation/foundationmodels/privatecloudcomputelanguagemodel).

## Proposed Settings behavior

Keep the existing Voice Mode enable control and add:

- **Use Apple Intelligence (Experimental)** — off for existing installations. English/German label: “Use Apple Intelligence” / “Apple Intelligence verwenden”. Off selects the existing OpenAI provider; on selects the Apple provider.
- **Allow Private Cloud Compute** — shown under the Apple option once the account entitlement is enabled. Initially off. Explain that recognized text and the current draft context can be processed by Apple's private servers.
- Show availability or asset-download status inline. An unavailable Apple model must not make the app imply that voice capture is ready.

OpenAI credentials and consent stay stored independently. Apple mode must not require an OpenAI API key or accept an OpenAI-specific disclosure. Switching providers must stop the active session and take effect at the next session; never mix microphone pipelines. Preserve drafts on provider errors. Offer manual completion or an explicit switch to configured OpenAI; never send Apple's pending audio/text there silently.

During evaluation, explicitly select on-device or PCC so results can be compared. Decide any automatic local-to-PCC escalation rule from those results. A model's self-reported confidence alone is not a reliable routing signal.

## Changes in Mäuse

1. Add a provider value to `VoiceSettings`, decoding missing values as OpenAI. Keep provider enablement, Apple readiness, and OpenAI verification/consent distinct. Update the dashboard microphone and capture-route availability checks, which currently depend on OpenAI `isReady`.
2. Introduce a small voice-provider interface for start, stop, events, and workspace updates. `VoiceModeViewModel` currently creates `RealtimeVoiceService` directly. Adapt that service without changing its audio protocol, then add an Apple implementation.
3. Build the Apple speech pipeline with `SpeechAnalyzer`, `SpeechTranscriber`, locale/asset management and audio interruption handling. Show provisional recognition as progress only. Batch finalized text into actual utterances using speech activity/pause handling; a final text segment is not necessarily the end of a user's request. Serialize model requests while continuing to capture later speech.
4. Generate a compact typed update and convert it to the existing workspace representation. Reuse draft rendering, ordering, changed-field highlights, clarification, session history, validation, and save logic. Assign request identity in the app. Resolve new/existing draft IDs deterministically and reject invalid or stale updates.
5. Include the current date, timezone, language, current drafts and latest utterance in each request. Keep context bounded and make manual draft removal part of the canonical state so a delayed response cannot resurrect deleted drafts. Avoid sending the historical ledger to PCC.
6. Update microphone-purpose text, provider-specific privacy disclosure, help and App Store privacy answers. Current microphone copy explicitly says audio streams to OpenAI. Keep recognized text and audio session-only unless the user explicitly saves expenses. Verify any permission requirements for the actual Speech API used.
7. Gate Apple APIs with runtime availability. Preserve the current iOS 17 minimum for manual input and OpenAI. On-device Apple mode can support iOS 26+; PCC requires iOS 27+.

## Evaluation and release gates

Use the existing synthetic German/English audio fixtures and add speech-specific cases. Run three separate comparisons: transcription accuracy, extraction on the same reference text, and end-to-end audio→draft behavior. This identifies whether a wrong amount originated in recognition or extraction.

Cover multiple expenses, decimal amounts, German compound number words, €1,234.56/1.234,56 €, relative dates, percent/fixed partner shares, same-title expenses, corrections, removal, missing amounts, silence/noise, rapid follow-up speech, manual edits during pending responses, long sessions and cancellation. Measure amount/date/split accuracy, unintended draft changes, duplicates, and median/tail time to visible draft.

Exercise unavailable/disabled Apple Intelligence, missing assets, supported locales, network loss, approaching/exhausted PCC quota, model refusal, interruption, and return to the existing OpenAI provider. Do not store personal utterances in diagnostic logs.

Require the existing 50 regressions to remain green, new provider-state/queue/migration checks to pass, and actual Apple inference on a supported iPhone before publishing the switch as usable. Physical microphone/Bluetooth tests remain necessary. Simulator availability controls can validate error UI but cannot prove model quality.

## Verification performed in this review

- Read current Swift settings, OpenAI audio/session instructions, workspace update logic, and microphone privacy text.
- Confirmed `PrivateCloudComputeLanguageModel`, quota and language APIs in the installed iOS 27 SDK; confirmed iOS 26 Speech/Generable APIs.
- Type-checked an isolated Swift probe with both model paths, `@Generable` expense output, speech locale/asset checks and PCC quota/reasoning options against Xcode 27's simulator SDK with deployment target iOS 17 and availability guards. It passed without diagnostics.
- Probe and downloaded source files are under `/tmp/maeuse-apple-voice-research/`. This was compile-only: no Apple inference request, entitlement application, app behavior change, or new TestFlight upload occurred.

Next implementation step: build the provider abstraction and opt-in on-device prototype, while verifying developer-account eligibility for PCC. Add the PCC path after the entitlement is granted and evaluate both on the same fixtures before choosing the Apple mode's default processing policy.
