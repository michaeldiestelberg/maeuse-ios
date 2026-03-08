import Foundation
import AVFoundation

/// Records audio using AVAudioRecorder and returns the file URL
final class VoiceRecorderService: NSObject, ObservableObject {
    @Published var isRecording = false
    @Published var elapsedSeconds: Int = 0

    private var audioRecorder: AVAudioRecorder?
    private var timer: Timer?
    private var recordingURL: URL?

    static let maxRecordingDuration: TimeInterval = 45

    /// Start recording audio
    func startRecording() async throws -> Bool {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
        try session.setActive(true)

        // Request permission
        let permitted = await withCheckedContinuation { continuation in
            session.requestRecordPermission { allowed in
                continuation.resume(returning: allowed)
            }
        }

        guard permitted else { return false }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("maeuse_voice_\(UUID().uuidString).m4a")

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]

        let recorder = try AVAudioRecorder(url: url, settings: settings)
        recorder.delegate = self
        recorder.record(forDuration: Self.maxRecordingDuration)

        self.audioRecorder = recorder
        self.recordingURL = url

        await MainActor.run {
            self.isRecording = true
            self.elapsedSeconds = 0
        }

        startTimer()
        return true
    }

    /// Stop recording and return the audio file URL
    func stopRecording() -> URL? {
        audioRecorder?.stop()
        stopTimer()

        Task { @MainActor in
            self.isRecording = false
        }

        return recordingURL
    }

    /// Cleanup temporary recording file
    func cleanup() {
        if let url = recordingURL {
            try? FileManager.default.removeItem(at: url)
            recordingURL = nil
        }
    }

    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.elapsedSeconds += 1
            }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
}

extension VoiceRecorderService: AVAudioRecorderDelegate {
    func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        Task { @MainActor in
            self.isRecording = false
        }
        stopTimer()
    }
}
