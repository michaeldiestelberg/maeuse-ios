import Foundation
import SwiftData
import Observation
import UIKit

/// Manages settings state: backup/restore, voice configuration
@Observable
final class SettingsViewModel {
    var isPresented: Bool = false
    var voiceSettings: VoiceSettings
    var statusMessage: String = ""
    var showStatus: Bool = false
    var isVerifying: Bool = false
    var showImportConfirmation: Bool = false
    var pendingImportData: Data? = nil

    private let openAI = OpenAIService()

    init() {
        if let data = UserDefaults.standard.data(forKey: VoiceSettings.storageKey),
           let settings = try? JSONDecoder().decode(VoiceSettings.self, from: data) {
            self.voiceSettings = settings
        } else {
            self.voiceSettings = .default
        }
    }

    // MARK: - Voice Settings

    var voiceAPIKeyText: String {
        get { voiceSettings.apiKey }
        set { voiceSettings.apiKey = newValue.trimmingCharacters(in: .whitespacesAndNewlines) }
    }

    var voiceEnabled: Bool {
        get { voiceSettings.enabled }
        set {
            voiceSettings.enabled = newValue && voiceSettings.isVerified
            saveVoiceSettings()
        }
    }

    var voiceStatusText: String {
        if voiceSettings.isVerified {
            return "Key verified"
        }
        return ""
    }

    func verifyKey() {
        guard !voiceSettings.apiKey.isEmpty else {
            showStatusMessage("Enter an API key first.")
            return
        }

        isVerifying = true

        Task { @MainActor in
            do {
                let valid = try await openAI.verifyAPIKey(voiceSettings.apiKey)
                if valid {
                    voiceSettings.verifiedAt = Date()
                    saveVoiceSettings()
                    showStatusMessage("Key verified successfully.")
                } else {
                    voiceSettings.verifiedAt = nil
                    voiceSettings.enabled = false
                    saveVoiceSettings()
                    showStatusMessage("Invalid API key.")
                }
            } catch {
                showStatusMessage("Verification failed: \(error.localizedDescription)")
            }
            isVerifying = false
        }
    }

    func saveVoiceSettings() {
        if let data = try? JSONEncoder().encode(voiceSettings) {
            UserDefaults.standard.set(data, forKey: VoiceSettings.storageKey)
        }
    }

    // MARK: - Export

    func exportBackup(expenses: [Expense]) {
        do {
            let data = try BackupService.exportBackup(expenses: expenses)
            let filename = BackupService.exportFileName()

            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
            try data.write(to: tempURL)

            let activityVC = UIActivityViewController(activityItems: [tempURL], applicationActivities: nil)

            if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
               let rootVC = scene.windows.first?.rootViewController {
                // Handle iPad popover
                if let popover = activityVC.popoverPresentationController {
                    popover.sourceView = rootVC.view
                    popover.sourceRect = CGRect(x: rootVC.view.bounds.midX, y: rootVC.view.bounds.midY, width: 0, height: 0)
                    popover.permittedArrowDirections = []
                }
                rootVC.present(activityVC, animated: true)
            }

            showStatusMessage("Backup ready to share.")
        } catch {
            showStatusMessage("Export failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Import

    func handleImportFile(_ data: Data) {
        pendingImportData = data
        showImportConfirmation = true
    }

    func confirmImport(context: ModelContext) {
        guard let data = pendingImportData else { return }

        do {
            let backups = try BackupService.parseBackup(data: data)
            try BackupService.replaceAllExpenses(in: context, with: backups)
            showStatusMessage("Imported \(backups.count) expenses.")
        } catch {
            showStatusMessage("Import failed: \(error.localizedDescription)")
        }

        pendingImportData = nil
        showImportConfirmation = false
    }

    // MARK: - Helpers

    private func showStatusMessage(_ message: String) {
        statusMessage = message
        showStatus = true

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            showStatus = false
        }
    }
}
