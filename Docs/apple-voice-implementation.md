# Apple Voice Mode implementation and access status

September 15, 2026. Branch `codex/apple-voice`, based on build 44 (`11e0c3c`). Unreleased prototype; no new TestFlight build has been requested from Xcode Cloud for this work.

## Implemented

- Settings provider switch off by default, separate Apple enablement, backward-compatible decoding for existing OpenAI settings, independent key/consent retention.
- On-device availability checks for OS, device, Apple Intelligence model, locale and Speech assets. Asset installation happens before microphone capture.
- iOS 26 SpeechAnalyzer / SpeechTranscriber / SpeechDetector pipeline. Final segments are collected across an utterance, then processed after a pause. Recognition progress and queued generation prevent premature Save.
- Structured Foundation Models mutations with app-assigned draft/response IDs, explicit monetary/date/split validation, stable order, incomplete amounts kept unsavable, and manual-removal tombstones.
- Serial request processing with current canonical drafts, cancellation guards, bounded requests/workspace, no persistent transcripts/audio and no silent provider fallback.
- Audio interruption/background handling retains completed drafts for explicit review/save. Active capture is stopped before another provider can start.
- Compiling iOS 27 PrivateCloudComputeLanguageModel path, guarded by a **false** build capability flag. The managed entitlement is not added prematurely. Once approved, configure the App ID/provisioning profile, enable the build flag, and validate PCC separately before release.
- English/German Settings, status and failure text; provider-neutral microphone purpose string.

## Apple developer access

The PCC entitlement is not enabled in this prototype. On-device Foundation Models requires no separate developer application. PCC requires Apple's managed entitlement and the account/program eligibility described in [Apple's access requirements](https://developer.apple.com/private-cloud-compute/).

Complete the account-holder enrollment steps and PCC request, wait for Apple's approval, then configure the App ID and provisioning profiles. Enable the build capability flag only after signing is ready. Validate PCC availability, quota, errors, privacy copy and extraction on a supported device before release.

Account-specific application details are kept outside this public repository. This document does not assert that the account has been approved.

## Prepared PCC use-case description

Mäuse is an iPhone app for couples to track shared everyday expenses. Its optional Voice Mode turns spoken English or German expense descriptions into structured drafts containing a title, amount, date, and partner share. Users can add multiple expenses, correct an earlier draft, or remove a draft before explicitly saving. Speech recognition runs on the device. With a separate Private Cloud Compute setting enabled, the app would send finalized recognized text and only the current temporary draft workspace to Apple's model for structured extraction and corrections. It would not send microphone audio or the user's historical expense ledger. The existing OpenAI provider remains independently selectable. The app handles availability, quota limits and errors explicitly and never silently changes providers.

## Validation

The final iOS 27 simulator run passes **73 tests**, with **2 live-model checks explicitly skipped**. There are no failures or compiler warnings. It includes the original 50 regressions plus provider migration/readiness, validation, speech segment deduplication, serial correction, manual deletion and cancellation checks. FoundationModels is linked with `LC_LOAD_WEAK_DYLIB`, preserving launch compatibility on the iOS 17 deployment target.

Actual SpeechAnalyzer transcription was tested on this Mac using the existing synthetic fixtures:

| Fixture | Recognized text |
| --- | --- |
| English add | Coffee for €4.50. My partner pays 30%. |
| German add | Ich habe Blumen für 12 Euro und Kinokarten für 24 Euro gekauft. Beides halbe halbe. |
| German correction/removal | Die Blumen haben 13,50 Euro gekostet, nicht 12 Euro. Entferne die Kinokarten. |

Both locale asset packages downloaded successfully. This verifies Apple's speech model with recorded audio, not live iPhone microphone capture or Foundation Models extraction. Harness/results are under `/tmp/maeuse-apple-voice-research/SpeechFixtureCheck.swift` and `speech-fixture-results.log`. Only synthetic fixture text is recorded there. No private utterances are logged by the app.

A real iOS 27 simulator inference attempt was made first: both English and German calls failed because Apple’s runtime returned `InferenceError::operationNotAllowed::Simulator is not supported`, even though `isAvailable` was true. That result is preserved in `/tmp/maeuse-apple-verified27.xcresult`. Production readiness now explicitly rejects this simulator environment. The live English/German tests skip on simulator and when the real device model is unavailable. They must pass on an Apple Intelligence device before release. Microphone/Bluetooth and PCC still require device/access validation. Final validation results:

- iOS 27: **73 passed, 2 skipped, 0 failed**, `/tmp/maeuse-apple-releasegate27.xcresult`.
- iOS 26.5: **73 passed, 2 skipped, 0 failed**, `/tmp/maeuse-apple-releasegate26.xcresult`.
- iPhone Release build and static analysis with Xcode 27: passed without compiler/analyzer warnings, `/tmp/maeuse-apple-release.log`.
- English/German Settings checked visually at the normal portrait size. The separate Apple switch and disabled PCC/voice controls reflect availability correctly. A 667 × 375 resizable window keeps Done visible and lets Settings content scroll to the bottom.
- Plist/localization syntax and `git diff --check`: clean.

These results must not be represented as successful live Foundation Models inference or physical microphone/Bluetooth validation.

Before TestFlight distribution, run the existing focused journeys plus Apple-specific queue/migration/validation tests on iOS 27 and iOS 26.5, inspect the settings on both app languages, run the release build/analyzer, then validate actual Apple inference on a supported device. Use synthetic EN/DE fixtures covering multiple expenses, decimals, corrections, deletion, dates and split values; retain no personal recordings in the repo.
