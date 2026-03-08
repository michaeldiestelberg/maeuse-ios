# Mäuse — Native iOS App

A native SwiftUI expense-splitting app for couples. Full replica of the [Mäuse PWA](https://github.com/michaeldiestelberg/maeuse), rebuilt from scratch for iOS.

"Mäuse" is German slang for money — literally "mice."

## Features

- **Expense tracking** — log expenses with amount, description, date
- **Flexible splitting** — percentage-based or fixed-amount splits
- **Monthly overview** — navigate months, see totals and partner's share at a glance
- **Voice mode** — speak an expense, AI transcribes and extracts all fields (uses your own OpenAI API key)
- **Backup & restore** — export/import JSON backups (compatible with PWA format)
- **Dark mode** — full light/dark theme with Liquid Glass design language
- **Onboarding** — welcome screen with "don't show again" preference
- **100% local** — all data stored on-device via SwiftData, no server, no account

## Architecture

```
Maeuse/
├── MaeuseApp.swift              # App entry point
├── ContentView.swift            # Root view + onboarding gate
├── Models/
│   ├── Expense.swift            # SwiftData model + backup codable
│   └── VoiceDraft.swift         # Voice pipeline draft model
├── ViewModels/
│   ├── ExpenseListViewModel.swift    # Month nav, filtering, summaries
│   ├── ExpenseEditorViewModel.swift  # Add/edit sheet state
│   ├── VoiceModeViewModel.swift      # Voice recording + AI pipeline
│   └── SettingsViewModel.swift       # Settings, backup, voice config
├── Views/
│   ├── MainExpenseView.swift         # Primary screen: header, list, FABs
│   ├── ExpenseEditorSheet.swift      # Add/edit expense bottom sheet
│   ├── VoiceSheet.swift              # Voice recording + review sheet
│   ├── SettingsSheet.swift           # Settings: backup + voice config
│   ├── OnboardingView.swift          # Welcome screen
│   └── Components/
│       └── ExpenseRow.swift          # Single expense list row
├── Services/
│   ├── OpenAIService.swift           # Transcription, cleanup, extraction
│   ├── VoiceRecorderService.swift    # AVAudioRecorder wrapper
│   └── BackupService.swift           # JSON export/import
├── Theme/
│   └── LiquidGlass.swift             # Design system: colors, glass surfaces, button styles
└── Assets.xcassets/                  # App icon, accent color
```

## Requirements

- iOS 17.0+
- Xcode 16.0+
- Swift 5.9+
- OpenAI API key (for voice mode only)

## Getting Started

1. Open `Maeuse.xcodeproj` in Xcode
2. Select your development team in **Signing & Capabilities**
3. Build and run on your device or simulator

### Voice Mode Setup

1. Go to **Settings** → **Voice Mode**
2. Enter your OpenAI API key
3. Tap **Verify Key**
4. Enable the **Voice mode** toggle
5. The mic button appears on the main screen

## Data Compatibility

Backup files are JSON-compatible with the [Mäuse PWA](https://maeuse.vercel.app). You can export from the PWA and import into the native app (and vice versa).

## Tech Stack

- **SwiftUI** — declarative UI
- **SwiftData** — on-device persistence (replaces IndexedDB)
- **AVFoundation** — audio recording
- **OpenAI API** — whisper transcription + GPT extraction (voice mode)
- **Observation** — reactive state management

## Privacy

- All expense data is stored locally on your device
- No server, no database, no sign-up
- Voice mode is the only feature that connects to the cloud — it sends audio to OpenAI using your own API key
- No tracking, no analytics

## License

MIT
