## 1.5.0 (65) — proposed App Store release, 2026-10-23

Consolidates Apple on-device Voice Mode, iPhone Duo layouts, and related changes tested in 1.5.0 builds 49–64 since 1.4.0 (48), plus the review fixes merged in `398bdf7`. Candidate binary is **65** (bump PR `cursor/bump-build-65-5f1a`). This entry is for account-holder review and is not a submission.

- **iPhone Duo:** on the unfolded inner screen, month totals sit beside the expense list. Welcome, Settings, and OpenAI Voice Mode use the extra width. A closed or narrow window keeps the regular iPhone layout.
- Optional **Apple · On device** Voice Mode: on-device speech recognition and Apple Foundation Models, no API key, no usage fees, no cloud fallback. Audio stays on the iPhone. Requires iOS 26+, a compatible device, Apple Intelligence, and downloaded language resources.
- Apple mode works one expense at a time: say it, check the draft, save; the screen then listens for the next one. Several priced purchases in one sentence are asked one after another.
- Optional **OpenAI · Cloud** remains the recommended, more accurate continuous-capture mode with the user’s own API key. A setup screen compares privacy, accuracy, and cost. Switching modes keeps Voice Mode on.
- OpenAI disclosure is asked once. Turning Voice Mode off stops capture but keeps that consent; deleting the API key withdraws it. Apple mode has no disclosure.
- Review fixes in this binary: System Boot Time in the privacy manifest, OpenAI consent v2 for 1.4 upgraders, microphone purpose string names OpenAI vs Apple, voice Save inserts through an isolated context.
- The expense-editor delete confirmation is a centred alert.
- Backups, manual entry, and local expense storage are unchanged.

The version bump to 65 is a separate PR. App Store copy is in `AppStore/1.5.0-approval.md`. Status: awaiting account-holder approval; do not push this package to `main`.

## 1.5.0 (64) — internal TestFlight candidate, 2026-10-23
Apple mode now handles one expense at a time.
- Say one expense, check the draft, save it. The screen then clears, shows “Saved: … · €…” and listens for the next one. **Done** closes the session; saved expenses are already in the list.
- A complete draft pauses the microphone for review instead of listening on, so the next sentence can no longer change it by accident. Tap the microphone to say a correction; ✕ discards the draft and listens again. A draft that still needs details keeps listening for the answer.
- Several priced purchases in one sentence (“coffee 4.50 and flowers 12”) are no longer guessed at: Mäuse asks for them one after the other. Items sharing one price (“coffee and cake for 8 euros”) stay one expense. A new purchase while a draft is in review asks to save first.
- The listening screen shows an example (“Coffee for €4.50”) and the live transcript; the review shows what was heard.
- The delete confirmation in the expense editor appears as a centred alert instead of a popover in the top-left corner.
- Local diagnosis moved from its own Settings card into the Voice Mode card, below the Apple mode status. It only shows while Apple mode is selected and Voice Mode is on.
- 161 unit tests and 6 UI tests pass on the iPhone 18 Pro simulator; the Release device build has no warnings. Apple model check 18/18; accuracy suite 85/96, the 11 misses being the known model limits. Real speech recognition still needs a physical iPhone check.

## 1.5.0 (63) — internal TestFlight candidate, 2026-10-23
Fixes from the 1.5.0 release code review.
- Apple mode keeps what you said you pay across phrases: “Dinner 73 €, I pay 20” followed by “actually it was 80” gives your partner 60, not 53. Untouched cards no longer show as updated after each phrase.
- Price corrections that name two numbers work: “Die Blumen haben 13,50 € gekostet, nicht 12 €” or “the 2nd one was 13.50” set the new price instead of leaving the card without an amount.
- “Split it 50-50” or “70-30” is read as a ratio instead of a negative number.
- “Pizza 12 euros 2 days ago” stays €12 dated two days ago (before: €12.02 today); “4 Euro 3 Mal” is no longer €4.03.
- When Apple mode is selected but not available on this iPhone, the microphone opens setup instead of a voice screen that fails immediately. Availability is rechecked when the app returns to the foreground.
- An unclear split shows “Check split” instead of the whole spoken sentence, so long requests no longer fill the session.
- Starting the microphone between phrases no longer waits on the main thread; a late audio shutdown from the previous phrase can never stop the next recording.
- The retry after a failed phrase can choose a different price; the workspace is read once per phrase; unused interpreter code is removed, and its tests now run through the production path.
- The voice mode chooser no longer shows the “Your choice is remembered…” note.
- 157 unit tests and 6 UI tests pass on the iPhone 18 Pro simulator; the Release device build has no warnings. Apple model check 18/18; accuracy suite 83/94 with 4 new regression cases, the 11 misses being the known model limits.

## 1.5.0 (62) — internal TestFlight candidate, 2026-10-23
- The voice mode chooser recommends OpenAI · Cloud, lists it first and preselects it until a mode is chosen. Each mode shows accuracy, how you speak, cost and privacy side by side, including about $1–2 per 100 dictated expenses for OpenAI and an honest accuracy caveat for Apple. Only the selected card is highlighted; “Recommended” and “Free” are badges.
- Switching modes keeps Voice Mode on. Switching to OpenAI shows its disclosure first unless it was already accepted (“Not now” keeps the current mode). If the new mode still needs its API key or Apple Intelligence, Voice Mode stays on and Settings says it starts working once setup is complete.
- Apple mode turns on without a disclosure; only the system microphone and speech recognition prompts remain.
- The OpenAI disclosure is shorter (what is sent, retention, cost) and is asked once. Turning Voice Mode off stops capture but keeps consent; deleting the API key withdraws it.
- New installations default to OpenAI with voice off. 151 unit tests and 6 UI tests pass on the iPhone 18 Pro simulator.

## 1.5.0 (61) — internal TestFlight candidate, 2026-10-21
- Apple mode reads prices as dictation writes them: “€4.50”, “4,50 €” and “4 Euro 80” are one price each. Before, “Dinner €64” could lose its price, and “Kaffee für 4,50 € und Blumen für 12 €” could give both purchases the same €12.
- A price said once now belongs to one purchase only, and a purchase price is never mistaken for someone’s share.
- Shares without a number work: “my partner pays everything”, “das zahlt mein Partner komplett”, “just for me” and “das zahle ich alleine” set the partner’s part to 100% or 0% instead of falling back to 50/50. “Die Hälfte” is read as 50%.
- Saying the partner paid in full no longer deletes the expense: deleting needs an explicit request.
- If Apple’s model fails on a phrase, it tries once more with a different reading before showing the error.
- New accuracy suite: 78 of 90 dictation-style requests pass on the Mac model (build 60: 58); the misses are shares left open for the user and some weekday dates. Build 60’s own model check passes 18/18, and 147 unit tests pass on the iPhone 18 Pro simulator. Real speech recognition still needs a physical iPhone check.

## 1.5.0 (60) — internal TestFlight candidate, 2026-10-18
- The main screen no longer has the opaque bar from build 58: the microphone and plus buttons float over the expense list again, the list scrolls underneath with room for the last row, and short windows such as landscape still move them into the header.
- Settings → Voice Mode in Apple mode is much shorter. When everything is ready it shows only “Auf diesem iPhone bereit.” / “Ready on this iPhone.” Requirements and “Check availability again” appear only when Apple capture is unavailable; a missing speech model shows one line and the “Sprachmodell laden” button. OpenAI mode keeps its cloud-audio notice.
- In Apple mode, Save now saves right away and returns to the list once speaking and processing are done, even though the microphone has started listening again. Save also works while the microphone restarts between phrases. If you are still speaking, Save finishes that phrase first so nothing is lost.
- 145 unit tests (3 new regression tests for Save) and 6 UI tests pass on the iPhone 18 Pro simulator. Real speech recognition still needs a physical iPhone check.

## 1.5.0 (59) — internal TestFlight candidate, 2026-10-16
- Apple voice capture uses Apple's iOS 26 SpeechAnalyzer with the on-device SpeechTranscriber model (DictationTranscriber where the newer model is unavailable). If the speech model for the app language is missing, it downloads in the app: from Settings → Voice Mode, or automatically on the first capture. Afterwards capture works offline. Audio never leaves the iPhone in Apple mode.
- Updating from 1.4 no longer silently selects OpenAI: installations without any cloud setup move to Apple and see the mode chooser, and cloud users keep OpenAI. Fresh installations keep the chooser until a mode is actually chosen.
- Apple mode keeps both prices in requests like “Pizza 12,50 € und Cola 2,50 €”, reads thousands separators in the app language (“1.500 €”), and computes weekday dates such as “letzten Freitag” in the app from today’s date. A contribution it cannot read stays open for clarification instead of becoming €0.
- A spoken own contribution (“ich zahle 20”) stays correct when the total is corrected later, and a corrected total clears an outdated split warning. An empty cloud split note no longer blocks saving.
- After 50 seconds without speech the microphone pauses instead of restarting. A phrase that is already processing finishes when the app goes to the background. The audio session closes off the main thread, and the listening haptic is no longer muted while recording. Reaching 10 drafts shows a dedicated message.
- VoiceOver announces automatic listening, processing and pause changes, reads the recording state once, and labels the connecting and Change voice mode controls. On short screens such as the unfolded iPhone Duo, the second voice mode is visible in the chooser. Single expense counts use the singular.
- 142 unit tests pass on the iPhone Duo simulator (iOS 27.1) and the Release device build succeeds without warnings. UI tests pass on the iPhone 18 Pro, including landscape and the two-column month review; on the Duo simulator its inner display does not rotate, so the two landscape UI tests skip there instead of passing without checking anything. Real speech recognition, the model download and Apple model behavior still need a physical iPhone.

## 1.5.0 (58) — internal TestFlight candidate, 2026-10-16
- Month review uses the available window width: wide windows pair the monthly summary with the expense ledger, while narrow windows and accessibility text retain a scrollable single column.
- Onboarding and voice drafts adapt to larger windows. Settings and mode selection respect their sheet width; semantic text and scrollable content support larger text sizes. Portrait and landscape orientations are supported.
- Native Duo simulator checks cover inner portrait/landscape, Closed and Partially Open, including Settings and voice-draft state preservation, light/dark fixtures and actual provider selection. Voice preview images are explicitly simulated; real microphone/model behavior still requires an eligible physical iPhone.
- Local integrated-main validation passes all 126 unit/layout tests and five UI tests on iPhone 17e (iOS 27.0); build 58 device Release configuration builds successfully with Xcode 27.1.
- Some native Duo XCTest welcome-button queries timed out despite independently verified native navigation; those runs are not counted as passing. The previous missing-ink diagnosis was disproved by original-PNG checks. Internal distribution uses the existing Xcode Cloud workflow; no public App Store submission is included.

## 1.5.0 (57) — internal TestFlight candidate, 2026-10-15
- Apple recording uses a thin accent ring with a gentle six-second pulse during actual capture. There is no diffuse halo; pause and processing remove the listening ring. Reduce Motion keeps a static ring; the separate endpoint arc and microphone glyphs are preserved.
- Local technical diagnostics live in Settings, with explicit share and clear actions and no audio/transcript/financial values. They remain in memory until the app quits.
- A contextual Apple/OpenAI mode chooser explains behavior, requirements and cloud audio/context transfer. Selection is remembered, cancellable and revisitable in Settings, and starts no recording. Existing provider consent remains required.
- The recording screen has a single primary status label. Expense extraction, shares, save rules and endpoint behavior are unchanged.
- 124 simulator tests, Release build and static analysis passed. Physical-device speech and model behavior remain device checks. Internal distribution uses the existing Xcode Cloud workflow.

## 1.5.0 (56) — internal TestFlight candidate, 2026-10-10
- Apple Voice Mode validates original price/currency evidence before computing amounts. Guided source choices prevent numeric prices from being rewritten; recognized sharing intent stays open rather than silently becoming 50/50.
- Relative dates use separate distance/direction fields. The reported Tesla request retains €73, the date three days earlier and an unassigned 70/30 ratio until clarified.
- Private local diagnostics show app/OS/model variant, capture completion, processing stages/timing and specific error categories. Sharing is explicit; diagnostic exports contain no audio, transcript or financial values.
- 119 iOS simulator tests and Release/static analysis passed; two actual Apple-model runs passed 31/31 checks each. Real iPhone speech and its model variant remain a device verification step.

## 1.5.0 (55) — internal TestFlight candidate, 2026-10-10
- Apple Voice Mode uses a structured action plan instead of free model tool calls. Multiple purchases retain their prices and dates; unspecified shares default to 50/50 in the app.
- Relative dates, money rounding, speaker/partner contributions and draft identities are computed or validated by shared app rules. Unassigned ratios remain open until the people are clarified; invalid dates/shares cannot be saved.
- Actual on-device Apple model validation on the Mac passed 26/26 checks twice, including German/English follow-ups and additional formulations. All 110 iOS simulator tests, Release build and static analysis passed. Physical iPhone audio/model validation remains the tester's final check.

## 1.5.0 (54)
- Apple listening keeps a stable microphone with a soft accent halo, breathing slowly only during actual capture; quiet and speech share the same clear state.
- Pause/inference extinguish the halo and show a crossed microphone. Resume intent alone never lights it. Reduce Motion uses a steady halo.
- Endpoint countdown, speech timing and manual-stop fix retained; no new text or display meter changes.

## 1.5.0 (53)
- Intentional microphone stops now finish empty speech normally when recognition reports an end-of-audio error; genuine recording failures remain visible.
- Endpoint ring appears after a settled pause and fades out with its last position when speech resumes, without backward reset animation. Actual endpoint and processing timing are unchanged.
- 95 simulator regression tests, Release build and analyzer validation; physical Apple speech/model remains a device check.

# Changelog

This file records user-facing changes to Mäuse. App Store and GitHub release notes should be based on the matching version section.

## 1.5.0 (52) — internal TestFlight candidate, 2026-10-04

- Apple's microphone now breathes when capture is actually ready, reacts to microphone audio with a waveform, and shows the real speech-pause timer as a ring. New audio or revised recognition resets that ring and the processing timer together.
- Processing shows a crossed-out microphone and progress arc. A pause/play badge makes the choice to resume afterward or remain paused visible. Actual listening resumption gets an optional soft haptic. Existing draft insertion and correction highlights remain the confirmation.
- Reduce Motion removes ambient/rotating motion while preserving distinct static states; VoiceOver retains the microphone action and actual state. No explanatory paragraphs or new recording architecture were added, and OpenAI capture behavior is preserved.
- Physical-device microphone noise, speech boundaries, and Apple model latency still need verification on an eligible iPhone.

## 1.5.0 (51) — internal TestFlight candidate, 2026-10-04

- Apple Voice Mode now uses one central microphone control, the familiar draft cards, total, and Save. The transcript is available in the collapsed understanding detail; long instructions no longer occupy the capture screen.
- A quiet pause with stable recognition automatically processes the phrase. The microphone is visibly paused during Apple processing, then listening resumes unless you requested a pause. Tap the microphone to finish a phrase and review, or to change whether listening resumes after processing.
- Save during recording finishes the current phrase for review first; tap Save again after reviewing the resulting drafts. Empty turns do not invoke the model. Backgrounding, interruptions, closing, and the 10-draft limit prevent automatic resumption.
- Existing OpenAI voice behavior is preserved. All processing in Apple mode remains on device with no cloud fallback. The build 50 audio-notification fix is retained.
- Speech endpoint timing and real Apple inference require testing on an eligible physical iPhone; simulator tests cover endpoint decisions, pause/resume intent, repeated turns, cancellation, stale callbacks, and draft preservation.
- Verified on the Mac mini with Xcode 27: all 91 iOS 27 simulator tests passed; the local Release build and static analysis succeeded without compiler warnings. Listening, processing, and paused screen layouts were visually checked in German and English.

## 1.5.0 (50) — internal TestFlight candidate, 2026-10-03

- Apple on-device recording ignores normal microphone category changes and interruption-end notifications instead of immediately showing “Recording was interrupted.” Audio-engine notifications are scoped to the active recorder.
- Real interruptions, microphone route loss, backgrounding, and audio-service resets still stop recording safely. Existing drafts remain available when resuming or recording another phrase.
- Verified locally on the Mac mini with Xcode 27: all 85 iOS 27 simulator tests passed, including repeated recovery and stale-callback regression coverage. Actual offline speech recognition and Foundation Models require an eligible physical iPhone; no physical device was connected during verification.

## 1.5.0 (49) — internal TestFlight candidate, 2026-09-27

- Choose Apple on-device voice capture or OpenAI cloud capture when enabling Voice Mode. Setup explains cost, privacy, device requirements, and the difference between short dictation turns and continuous capture in English and German.
- Apple mode uses on-device speech recognition and Apple Foundation Models end to end. No OpenAI model, key, paid API, or cloud fallback is used in this mode. Downloaded Apple resources and an Apple Intelligence compatible device running iOS 26+ are required.
- Dictate a short phrase, tap Process phrase, review the drafts, and use Record more for additions or corrections. Recording pauses during local processing. Existing drafts survive errors and interruptions.
- Local amounts, partner shares, and dates are resolved from quoted speech and validated before saving. Missing prices require clarification; stale responses cannot restore removed drafts or refill closed sessions.
- Existing installations keep their selected cloud mode. New installations select Apple with voice disabled, and switching providers requires fresh consent.

## 1.4.0 (48) — submitted to App Review, 2026-09-27

Consolidates the changes tested in 1.3.1 builds 33–47 since public version 1.3.0 (32). Version 1.3.1 was distributed through TestFlight only.

- Voice Mode uses GPT-Realtime-2.1 for audio understanding and draft creation, with improved alphanumeric recognition. The separate transcription service and its additional charges are removed.
- A redesigned Voice Mode shows compact, stable draft cards, highlights corrections, and keeps a chronological “What I understood” history. Listening and processing animations make the session state visible, with Reduce Motion alternatives.
- The welcome screen, expense editor, calendar, and dashboard adapt to short or wide windows on iOS 27. Save and Cancel remain accessible in the editor.
- JSON export uses the current system exporter while retaining iOS 17 support. Backup import validates amounts, splits, IDs, and dates before an isolated replacement transaction; failed saves preserve the existing ledger.
- Editing amounts above €1,000 preserves their value in English and German.
- Removed drafts stay removed when delayed voice results arrive. Failed or malformed responses preserve existing drafts, and closed sessions ignore stale callbacks.
- Invalid spoken dates require correction. Audio interruptions and route changes offer Resume listening without losing the draft workspace.

No app behavior changes after the user-tested build 47; this candidate changes release versioning and App Store materials only. The account holder approved the copy and screenshots; build 48 was submitted on September 27, 2026. Status: Waiting for Review, with Manual Release enabled.

## 1.3.1 (47) — 2026-09-26

- The welcome screen scrolls in short windows, keeping the introduction and Get Started action reachable when resized. Wider windows keep a comfortable reading width.

## 1.3.1 (46) — 2026-09-21

Retries build 45 with the same review fixes. Xcode Cloud rejected the retired Xcode 27 release-candidate environment before compilation; the workflow now uses the supported final Xcode 27 (27A266a) release.

## 1.3.1 (45) — 2026-09-21

Internal TestFlight candidate with the pre-release review fixes; follows build 44.

- Backup import rejects unsupported amounts, invalid split values, and invalid dates before changing the ledger. Invalid split values already stored can be displayed and corrected without crashing.
- Backup replacement uses an isolated transaction so a failed save leaves the live ledger intact.
- Manually removed voice drafts stay removed when an older result arrives. Closing a session also rejects delayed callbacks from that connection.
- Failed, incomplete, and malformed voice responses show an error and preserve existing drafts. Only successfully completed structured results update the workspace.
- Explicitly invalid voice dates require correction before saving; omitted dates still default to today.
- Audio interruptions and device changes stop the listening indicator and offer **Resume listening**, preserving drafts and request history.

## 1.3.1 — 2026-09-15

Internal TestFlight candidate (build 44; follows build 42).

- The expense editor, calendar, and monthly overview adapt to shorter windows. Save and Cancel stay visible while the editor content scrolls.
- JSON backup export uses the current system sharing API, with the same portable backup format and iOS 17 support. Restoring a backup saves the replacement together and rolls back if saving fails.
- Voice Mode closes without blocking the interface on audio-session shutdown, and closing during connection setup cancels the pending connection.
- Fixed editing amounts above €1,000 in English and German, preserving the amount and partner share.

- Every spoken request now has a processing animation: three cheese crumbs orbit inside the mouse until its result appears, moving to the rim when you speak again while work is pending.
- Removed the empty first-expense placeholder. New drafts slide into place; corrections briefly highlight only the changed fields.
- Processing feedback preserves pending requests across overlapping speech and response completion. Reduce Motion shows stationary crumbs, and VoiceOver retains activity labels.

- Simplified Voice Mode: Save uses a static label, the request history opens directly into its entries, and the footer shows only the total.
- “What I understood” now keeps a chronological session history of requests and corrections with more natural phrasing. The expanded section uses a subtle timeline; the collapsed section remains title-only. Removing or correcting a draft no longer erases earlier requests.
- Microphone animation now uses a decibel-based display range, making quiet and normal speech visibly stronger than the idle wave. Metering uses the same converted mono audio sent for expense capture.
- The listening mouse now has a gentle wave even in silence, with stronger movement from microphone input. Idle motion stops when the app is inactive and is disabled with Reduce Motion.

- Voice Mode opens with orbiting cheese crumbs that transform into the mouse when microphone capture starts; the mouse's audio bars respond to speech.
- Removed the visible connection/listening labels and repeated dictation hint. VoiceOver keeps the status labels, and Reduce Motion uses a short crossfade.
- Voice Mode now uses GPT-Realtime-2.1 for audio understanding and expense capture, without a separately billed transcription model.
- Voice drafts now stay in a compact vertical list, with a smaller listening header, a static Save button, and a total.
- One expandable “What I understood” / “So habe ich dich verstanden” section replaces the repetitive chat bubbles.
- Voice corrections update and briefly highlight the same card without reordering the list; clarification questions appear separately when information is missing.

## 1.3.0 — 2026-08-01

Released on the App Store (build 32).
- Lock Screen and Control Center controls now start manual or voice expense capture directly, with custom mouse-themed add and microphone icons that match the app's brand.
- Matching Home Screen and Lock Screen widgets provide one-tap access to manual entry or Voice Mode: a small Home Screen widget and two circular Lock Screen widgets.
- Lock Screen widgets now sit on a translucent background so the mouse add and microphone icons stay clearly legible over any wallpaper.
- The expense editor now places deletion in a separate, clearly destructive action below the split control, with native confirmation before an expense is removed.
- When Voice Mode is ready, the mic button is the primary action on the main screen and the plus button is secondary.
- Secondary plus icon uses a crisp white glyph in dark mode for readable contrast.
- Voice Mode adds haptic feedback when listening starts, when new expenses are captured, and a subtler cue when drafts are updated. Haptics can be turned off in Settings.
- Typing a note in the expense editor no longer pushes the sheet off screen: the close and save buttons and the amount stay in place while the keyboard is open, and the number pad returns as soon as you finish typing.

## 1.2.0 — 2026-07-12

Mäuse 1.2.0 is the first App Store-ready release: a focused, local-first way for two people to record and settle everyday expenses.

### Highlights

- Add, edit, delete, and browse expenses by month.
- Split each expense by percentage or an exact partner amount.
- See monthly totals and partner shares at a glance.
- Export and restore portable JSON backups.
- Use the complete interface in English or German.
- Choose light, dark, or system appearance.

### Voice Mode

- Optionally dictate several expenses in one session.
- Review, correct, remove, and add drafts before saving.
- Keep the OpenAI API key in iOS Keychain.
- Manage microphone access, consent, Voice Mode, and the saved key independently.
- Continue using manual expense tracking without an API key or network connection.

### App Store preparation

- Added the final app icon, brand assets, privacy manifest, localized metadata, and screenshot set.
- Added clear in-app privacy explanations and consent withdrawal controls.
- Prepared and submitted version 1.2.0 build 9 for App Review.

## 1.0.0 — 2026-05-14

- Established the native SwiftUI and SwiftData application baseline.
- Added manual shared-expense tracking, monthly navigation, split calculations, settings, and the first internal TestFlight build.
