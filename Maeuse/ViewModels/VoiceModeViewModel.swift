import Foundation
import Observation

/// Manages voice recording → transcription → cleanup → extraction pipeline
@Observable
final class VoiceModeViewModel {
    var phase: VoicePhase = .idle
    var draft: VoiceDraft = .empty(todayISO: todayISOString())
    var errorMessage: String = ""
    var isPresented: Bool = false
    var isSaving: Bool = false

    let recorder = VoiceRecorderService()
    private let openAI = OpenAIService()

    var elapsedFormatted: String {
        let secs = recorder.elapsedSeconds
        let m = secs / 60
        let s = secs % 60
        return String(format: "%d:%02d", m, s)
    }

    var captureLabel: String {
        switch phase {
        case .idle: return "Tap to record"
        case .recording: return "Tap to stop"
        case .processing: return "Processing…"
        case .review: return "Review your expense"
        case .error: return "Something went wrong"
        }
    }

    var captureHint: String {
        switch phase {
        case .idle: return "Speak one expense, then stop to process it"
        case .recording: return elapsedFormatted
        case .processing: return "Please wait while AI reviews your recording"
        case .review: return ""
        case .error: return errorMessage
        }
    }

    var showDoneButton: Bool {
        phase == .review && draft.amount != nil && draft.amount! > 0
    }

    // MARK: - Actions

    func open() {
        reset()
        isPresented = true
    }

    func reset() {
        phase = .idle
        draft = .empty(todayISO: Self.todayISOString())
        errorMessage = ""
        isSaving = false
        recorder.cleanup()
    }

    func close() {
        if recorder.isRecording {
            _ = recorder.stopRecording()
        }
        recorder.cleanup()
        isPresented = false
        reset()
    }

    func toggleRecording(apiKey: String) {
        if phase == .recording {
            stopAndProcess(apiKey: apiKey)
        } else {
            startRecording()
        }
    }

    func startRecording() {
        Task { @MainActor in
            do {
                let permitted = try await recorder.startRecording()
                if permitted {
                    phase = .recording
                } else {
                    phase = .error
                    errorMessage = "Microphone access denied. Enable it in Settings → Mäuse."
                }
            } catch {
                phase = .error
                errorMessage = "Could not start recording: \(error.localizedDescription)"
            }
        }
    }

    func stopAndProcess(apiKey: String) {
        guard let audioURL = recorder.stopRecording() else {
            phase = .error
            errorMessage = "No audio was recorded."
            return
        }

        phase = .processing

        Task { @MainActor in
            do {
                // Step 1: Transcribe
                let rawTranscript = try await openAI.transcribe(audioURL: audioURL, apiKey: apiKey)

                guard !rawTranscript.isEmpty else {
                    phase = .error
                    errorMessage = "No speech detected. Try again."
                    return
                }

                // Step 2: Cleanup
                let cleaned = try await openAI.cleanupTranscript(rawTranscript, apiKey: apiKey)

                guard !cleaned.isEmpty else {
                    phase = .error
                    errorMessage = "Could not understand the recording. Try speaking more clearly."
                    return
                }

                // Step 3: Extract
                let extracted = try await openAI.extractExpense(
                    cleanedTranscript: cleaned,
                    todayISO: Self.todayISOString(),
                    apiKey: apiKey
                )

                draft = extracted

                // Apply defaults for missing fields
                if draft.partnerShareMode == nil {
                    draft.partnerShareMode = .percent
                    draft.partnerShareValue = 50
                }

                phase = .review
            } catch {
                phase = .error
                errorMessage = "Processing failed: \(error.localizedDescription)"
            }
        }
    }

    func recordAgain() {
        recorder.cleanup()
        phase = .idle
        draft = .empty(todayISO: Self.todayISOString())
        errorMessage = ""
    }

    static func todayISOString() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f.string(from: Date())
    }
}

private func todayISOString() -> String {
    VoiceModeViewModel.todayISOString()
}
