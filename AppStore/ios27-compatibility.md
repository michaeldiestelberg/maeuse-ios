# iOS 27 compatibility verification

Date: September 15, 2026. Release candidate: 1.3.1 (44), local verification complete; Cloud distribution pending.

## Scope

Includes the existing Voice Mode processing/history/layout work requested by the owner, plus:

- A scrollable expense editor with pinned Save/Cancel actions and a bounded content width.
- A scrollable calendar and dashboard summary for short or resizable windows.
- JSON backup export using CoreTransferable and SwiftUI's `fileExporter(item:)` (iOS 17+).
- Restore staged in one ModelContext save with rollback on failure.
- Audio-session activation/deactivation serialized off the main thread; pending connection tasks cancelled when closing Voice Mode.
- Reliable consent test fixtures independent of simulator preferences.
- Editable amounts without thousands separators, preserving values above €1,000 in English and German.

Apple explicitly recommends WritableDocument **or Transferable** when replacing FileDocument. Transferable matches this app's immutable JSON export and preserves the iOS 17 deployment target without a deprecated fallback. The imported JSON format and Expense schema remain unchanged.

## Evidence collected

| Check | Result |
| --- | --- |
| iOS 26.5 regression suite | Final build 44: 50 tests passed with Xcode 27.0 (27A266a), including resizing and English/German large-amount editing |
| System Transferable JSON representation | Passed; exported data imported into SwiftData with correct values |
| Create/edit/delete and monthly totals | Passed with comma/dot amounts and a 40% partner split |
| Restore and reopen on-disk store | Passed; stable IDs, fixed splits, dates, creation time and amounts preserved |
| Invalid JSON preserves current ledger | Passed |
| Editor resizing | Hosted editor resized 320×400 → 700×400 → 393×852 → 320×400; scrollability assertions passed and renders reviewed on iOS 26.5 and iOS 27 |
| Xcode 27 build and static analysis | Release build and analysis passed with zero warnings using Xcode 27.0 (27A266a); simulator test build also passed |
| iOS 27 regression suite | Final build 44: all 50 tests passed on iPhone 18 Pro, iOS 27.0 (24A434), Xcode 27.0 (27A266a) |
| iOS 27 interactive journeys | Device Hub resizing: 402×874 → 375×667 → 700×525; created €12.50, edited note with keyboard visible, changed date, saved and verified totals. Keypad scrolls into view; Save/Cancel remain pinned. Dark settings and JSON Files export completed; six-record JSON verified on disk, then imported through Files; replacement warning shown and “Imported 6 expenses” confirmed. |
| Live Voice Mode | Passed with production session configuration and authorized existing test key: German creation/correction/removal, stable IDs, English €4.50 with 30% partner split, request history, speech/response lifecycle, no transcription events |
| Xcode Cloud/TestFlight | Workflow pinned to Xcode 27 RC (27A266a), matching local release build; Family internal post-action verified; Next Build Number set and confirmed as 44. The proposed separate verification workflow was not created/run; build 43 is skipped. Default release workflow pending main push |

## Coverage and follow-up checks

- Automated coverage: manual create/edit/delete, monthly totals, percent/fixed splits, English/German large amounts, backup round trips and invalid data, launch routing, Voice Mode consent and failure/processing/correction states.
- Interactive iOS 27 coverage: English entry and note/date editing, short/wide window reflow, dark settings, actual Files export and restore, German Voice preview history expansion, draft removal and saving. After removing the €4.50 coffee draft, the remaining €15.99 saved and the dashboard total became €221.89.
- Follow-up on a physical iPhone: microphone permission/capture, interruptions, Bluetooth, widget/control launch integration and in-place OS upgrade. No physical device is available here.
- Exhaustive Dynamic Type, every cancellation permutation, and every accessibility setting were not manually rerun on iOS 27; earlier simulator records and targeted automated coverage are retained in the submission checklist.

## Environment and limits

No physical iPhone is connected to this Mac. Simulator checks and synthetic audio/API checks do not certify a physical microphone, Bluetooth route changes, or an in-place physical-device OS upgrade. Record these limits in the TestFlight test notes.

## Apple references

- [FileDocument replacement guidance](https://developer.apple.com/documentation/swiftui/view/fileexporter(ispresented:document:contenttype:defaultfilename:oncompletion:))
- [Transferable exporter, supported from iOS 17](https://developer.apple.com/documentation/swiftui/view/fileexporter(ispresented:item:contenttypes:defaultfilename:oncompletion:oncancellation:))
- [Xcode 27 SwiftUI source compatibility](https://developer.apple.com/documentation/technotes/tn3211-resolving-swiftui-source-incompatibilities-for-state-and-contentbuilder)
- [Resizable iPhone apps](https://developer.apple.com/videos/play/wwdc2026/278/)
