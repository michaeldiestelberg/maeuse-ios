import Foundation
import SwiftData
import Observation

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
    var hasSavedVoiceAPIKey: Bool = false

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

        if !self.voiceSettings.hasCurrentConsent {
            self.voiceSettings.enabled = false
        }
    }

    // MARK: - Voice Settings

    /// Consent is tied to the Voice Mode toggle: enabling requires the disclosure to be
    /// accepted first, and turning it off revokes consent again, so re-enabling always
    /// re-presents the disclosure. There is no separate withdrawal action.
    var voiceEnabled: Bool {
        get { voiceSettings.enabled }
        set {
            if newValue {
                voiceSettings.enabled = voiceSettings.isVerified
                    && hasSavedVoiceAPIKey
                    && voiceSettings.hasCurrentConsent
                saveVoiceSettings()
            } else {
                disableVoiceModeRevokingConsent()
            }
        }
    }

    var hasVoiceConsent: Bool {
        voiceSettings.hasCurrentConsent
    }

    func acceptVoiceConsent() {
        voiceSettings.consentVersion = VoiceSettings.currentConsentVersion
        voiceSettings.consentedAt = Date()
        saveVoiceSettings()
    }

    /// Turns Voice Mode off and clears the stored consent. Used both by the toggle and by
    /// the paths that force Voice Mode off because the key is gone or no longer verifies —
    /// consent must never outlive the enabled state, or re-enabling would skip the sheet.
    private func disableVoiceModeRevokingConsent() {
        voiceSettings.enabled = false
        voiceSettings.consentVersion = nil
        voiceSettings.consentedAt = nil
        saveVoiceSettings()
    }

    func verifyVoiceAPIKey() {
        let enteredKey = voiceAPIKeyText.trimmingCharacters(in: .whitespacesAndNewlines)
        let candidateKey: String
        let shouldSaveNewKey: Bool

        if enteredKey.isEmpty {
            guard let savedKey = try? apiKeyStore.readAPIKey(), !savedKey.isEmpty else {
                showErrorMessage(loc("EnterApiKeyPrompt"))
                return
            }
            candidateKey = savedKey
            shouldSaveNewKey = false
        } else {
            candidateKey = enteredKey
            shouldSaveNewKey = true
        }

        guard candidateKey.hasPrefix("sk-") else {
            showErrorMessage(loc("EnterValidApiKeyPrompt"))
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

                hasSavedVoiceAPIKey = true
                voiceSettings.apiKeySuffix = OpenAIAPIKeyStore.suffix(for: candidateKey)
                voiceSettings.verifiedAt = Date()
                saveVoiceSettings()
                showStatusMessage(loc("ApiKeyVerifiedKeychain"))
            } catch {
                voiceSettings.verifiedAt = nil
                disableVoiceModeRevokingConsent()
                showErrorMessage(loc("ApiKeyVerificationFailed", error.localizedDescription))
            }
            isVerifying = false
        }
    }

    func removeVoiceAPIKey() {
        do {
            try apiKeyStore.deleteAPIKey()
            voiceAPIKeyText = ""
            hasSavedVoiceAPIKey = false
            voiceSettings = .default
            saveVoiceSettings()
            showStatusMessage(loc("RemovedApiKeyMsg"))
        } catch {
            showErrorMessage(loc("CouldNotRemoveApiKey", error.localizedDescription))
        }
    }

    func saveVoiceSettings() {
        if let data = try? JSONEncoder().encode(voiceSettings) {
            UserDefaults.standard.set(data, forKey: VoiceSettings.storageKey)
        }
    }

    // MARK: - Export

    func prepareBackup(expenses: [Expense]) -> BackupDocument? {
        do {
            let data = try BackupService.exportBackup(expenses: expenses)
            return BackupDocument(data: data)
        } catch {
            showErrorStatus(loc("ExportFailedMsg", error.localizedDescription))
            return nil
        }
    }

    func exportCompleted(_ result: Result<URL, Error>) {
        switch result {
        case .success:
            showStatusMessage(loc("BackupExportedMsg"))
        case .failure(let error):
            if (error as NSError).code != NSUserCancelledError {
                showErrorStatus(loc("ExportFailedMsg", error.localizedDescription))
            }
        }
    }

    // MARK: - Import

    func handleImportFile(_ data: Data) {
        do {
            _ = try BackupService.parseBackup(data: data)
            pendingImportData = data
            showImportConfirmation = true
        } catch {
            showErrorStatus(loc("ImportFailedMsg", error.localizedDescription))
        }
    }

    func handleImportError(_ error: Error) {
        showErrorStatus(loc("ImportFailedMsg", error.localizedDescription))
    }

    func confirmImport(context: ModelContext) {
        guard let data = pendingImportData else { return }

        do {
            let backups = try BackupService.parseBackup(data: data)
            try BackupService.replaceAllExpenses(in: context, with: backups)
            showStatusMessage(loc("ImportedExpensesMsg", backups.count))
        } catch {
            showStatusMessage(loc("ImportFailedMsg", error.localizedDescription))
        }

        pendingImportData = nil
        showImportConfirmation = false
    }

    // MARK: - Helpers

    func reconcileStoredAPIKey() {
        guard let storedKey = try? apiKeyStore.readAPIKey(), !storedKey.isEmpty else {
            hasSavedVoiceAPIKey = false
            voiceSettings.apiKeySuffix = nil
            voiceSettings.verifiedAt = nil
            disableVoiceModeRevokingConsent()
            return
        }

        hasSavedVoiceAPIKey = true
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

    private func showErrorStatus(_ message: String) {
        statusMessage = message
        showStatus = true
        statusIsError = true
    }
}
