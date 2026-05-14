import Foundation
import SwiftData
import Observation
import UIKit

/// Manages settings state: backup/restore, voice configuration
@MainActor
@Observable
final class SettingsViewModel {
    var isPresented: Bool = false
    var voiceSettings: VoiceSettings
    var statusMessage: String = ""
    var showStatus: Bool = false
    var statusIsError: Bool = false
    var isVerifying: Bool = false
    var showImportConfirmation: Bool = false
    var pendingImportData: Data? = nil
    var voiceAPIKeyText: String = ""
    var voiceErrorMessage: String = ""
    var showVoiceError: Bool = false

    private let apiKeyStore = OpenAIAPIKeyStore.shared
    private let clientSecretService = OpenAIRealtimeClientSecretService()

    init() {
        let storedData = UserDefaults.standard.data(forKey: VoiceSettings.storageKey)

        if let data = storedData,
           let settings = try? JSONDecoder().decode(VoiceSettings.self, from: data) {
            self.voiceSettings = settings
        } else {
            self.voiceSettings = .default
        }

        reconcileStoredAPIKey()
    }

    // MARK: - Voice Settings

    var voiceEnabled: Bool {
        get { voiceSettings.enabled }
        set {
            voiceSettings.enabled = newValue && voiceSettings.isVerified && apiKeyStore.hasAPIKey()
            saveVoiceSettings()
        }
    }

    var voiceStatusText: String {
        if voiceSettings.isVerified {
            return "API key verified \(voiceSettings.maskedAPIKey)"
        }
        return ""
    }

    var hasSavedVoiceAPIKey: Bool {
        apiKeyStore.hasAPIKey()
    }

    func verifyVoiceAPIKey() {
        let enteredKey = voiceAPIKeyText.trimmingCharacters(in: .whitespacesAndNewlines)
        let candidateKey: String
        let shouldSaveNewKey: Bool

        if enteredKey.isEmpty {
            guard let savedKey = try? apiKeyStore.readAPIKey(), !savedKey.isEmpty else {
                showErrorMessage("Enter an OpenAI API key first.")
                return
            }
            candidateKey = savedKey
            shouldSaveNewKey = false
        } else {
            candidateKey = enteredKey
            shouldSaveNewKey = true
        }

        guard candidateKey.hasPrefix("sk-") else {
            showErrorMessage("Enter a valid OpenAI API key.")
            return
        }

        isVerifying = true

        Task { @MainActor in
            do {
                _ = try await clientSecretService.createClientSecret(apiKey: candidateKey)

                if shouldSaveNewKey {
                    try apiKeyStore.saveAPIKey(candidateKey)
                    voiceAPIKeyText = ""
                }

                voiceSettings.apiKeySuffix = OpenAIAPIKeyStore.suffix(for: candidateKey)
                voiceSettings.verifiedAt = Date()
                saveVoiceSettings()
                showStatusMessage("API key verified and saved in Keychain.")
            } catch {
                voiceSettings.verifiedAt = nil
                voiceSettings.enabled = false
                saveVoiceSettings()
                showErrorMessage("API key verification failed: \(error.localizedDescription)")
            }
            isVerifying = false
        }
    }

    func removeVoiceAPIKey() {
        do {
            try apiKeyStore.deleteAPIKey()
            voiceAPIKeyText = ""
            voiceSettings = .default
            saveVoiceSettings()
            showStatusMessage("Removed the saved OpenAI API key.")
        } catch {
            showErrorMessage("Could not remove API key: \(error.localizedDescription)")
        }
    }

    func saveVoiceSettings() {
        if let data = try? JSONEncoder().encode(voiceSettings) {
            UserDefaults.standard.set(data, forKey: VoiceSettings.storageKey)
        }
    }

    // MARK: - Export

    @MainActor
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

    private func reconcileStoredAPIKey() {
        guard let storedKey = try? apiKeyStore.readAPIKey(), !storedKey.isEmpty else {
            voiceSettings.apiKeySuffix = nil
            voiceSettings.verifiedAt = nil
            voiceSettings.enabled = false
            saveVoiceSettings()
            return
        }

        let suffix = OpenAIAPIKeyStore.suffix(for: storedKey)
        if voiceSettings.apiKeySuffix != suffix {
            voiceSettings.apiKeySuffix = suffix
            saveVoiceSettings()
        }
    }

    private func showStatusMessage(_ message: String) {
        statusMessage = message
        showStatus = true
        statusIsError = false

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            if !statusIsError {
                showStatus = false
            }
        }
    }

    private func showErrorMessage(_ message: String) {
        statusMessage = message
        showStatus = true
        statusIsError = true
        voiceErrorMessage = message
        showVoiceError = true
    }
}
