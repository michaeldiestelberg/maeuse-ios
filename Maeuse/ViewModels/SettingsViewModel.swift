import Foundation
import SwiftData
import Observation

/// Manages settings state: backup/restore, voice configuration
@MainActor
@Observable
final class SettingsViewModel {
    var isPresented: Bool = false
    var isChoosingVoiceMode = false
    private var opensSetupAfterChoice = false
    static let modeChoiceKey = "maeuse.voice-mode-chosen"
    /// Only an explicit choice (or migrated evidence of real voice use) counts. Merely
    /// having stored settings does not: every launch persists them, including 1.4.
    var hasSelectedVoiceMode: Bool {
        UserDefaults.standard.bool(forKey: Self.modeChoiceKey)
    }
    func requestVoiceSetup() {
        if hasSelectedVoiceMode { isPresented = true }
        else { isChoosingVoiceMode = true }
    }
    func confirmVoiceMode(_ provider: VoiceProvider, openSetup: Bool = false) {
        guard !isVerifying else { return }
        selectProvider(provider)
        UserDefaults.standard.set(true, forKey: Self.modeChoiceKey)
        saveVoiceSettings()
        opensSetupAfterChoice = openSetup
        isChoosingVoiceMode = false
    }
    func modeChoiceDismissed() {
        if opensSetupAfterChoice { opensSetupAfterChoice = false; isPresented = true }
    }
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
    var localAvailability: LocalVoiceAvailability = .modelNotReady
    /// Provider whose disclosure must be accepted before enabling or switching to it.
    var pendingConsentProvider: VoiceProvider?

    private let apiKeyStore = OpenAIAPIKeyStore.shared
    private let clientSecretService = OpenAIRealtimeClientSecretService()

    var isDownloadingSpeechModel = false

    private let availabilityProvider: () -> LocalVoiceAvailability
    private let speechAvailabilityProvider: () async -> LocalVoiceAvailability
    private let speechModelInstaller: () async throws -> Void

    init(availabilityProvider: @escaping () -> LocalVoiceAvailability = { .current },
         speechAvailabilityProvider: @escaping () async -> LocalVoiceAvailability = { await LocalVoiceAvailability.resolved() },
         speechModelInstaller: @escaping () async throws -> Void = { try await LocalVoiceAvailability.installSpeechModel() }) {
        self.availabilityProvider = availabilityProvider
        self.speechAvailabilityProvider = speechAvailabilityProvider
        self.speechModelInstaller = speechModelInstaller
        let storedData = UserDefaults.standard.data(forKey: VoiceSettings.storageKey)

        if let data = storedData,
           let settings = try? JSONDecoder().decode(VoiceSettings.self, from: data) {
            self.voiceSettings = settings
            migrateStoredVoiceChoice(storedData: data)
        } else {
            self.voiceSettings = .default
        }

        localAvailability = availabilityProvider()
        // Stale OpenAI consent (1.4 off=revoke) is not current in 1.5. Turn capture off
        // and persist so a later reader of UserDefaults cannot start a session.
        if !self.voiceSettings.hasCurrentConsent && self.voiceSettings.enabled {
            self.voiceSettings.enabled = false
            saveVoiceSettings()
        }
    }

    /// Releases before 1.5 stored voice settings without a provider on every launch, so a
    /// missing provider does not mean the user chose the cloud. Keep OpenAI only where
    /// there is evidence of cloud setup; otherwise default to Apple and keep the chooser.
    private func migrateStoredVoiceChoice(storedData: Data) {
        let defaults = UserDefaults.standard
        let showsVoiceUse = voiceSettings.enabled || voiceSettings.consentVersion != nil ||
            voiceSettings.apiKeySuffix != nil || voiceSettings.verifiedAt != nil
        if VoiceSettings.isMissingProvider(in: storedData) {
            if !showsVoiceUse { voiceSettings.provider = .appleLocal }
            saveVoiceSettings()
        }
        if showsVoiceUse && !defaults.bool(forKey: Self.modeChoiceKey) {
            defaults.set(true, forKey: Self.modeChoiceKey)
        }
    }

    // MARK: - Voice Settings

    /// OpenAI mode asks for its disclosure once. Turning Voice Mode off stops all capture but
    /// keeps that consent, so turning it back on needs no second confirmation. Deleting the
    /// API key withdraws it. Apple's on-device mode needs no disclosure.
    var voiceEnabled: Bool {
        get { voiceSettings.enabled }
        set {
            if newValue {
                refreshLocalAvailability()
                voiceSettings.enabled = canEnableVoice && voiceSettings.hasCurrentConsent
            } else {
                voiceSettings.enabled = false
            }
            saveVoiceSettings()
        }
    }

    var canEnableVoice: Bool {
        switch voiceSettings.provider {
        case .appleLocal: return localAvailability.allowsCapture
        case .openAI: return voiceSettings.isVerified && hasSavedVoiceAPIKey && !isVerifying
        }
    }

    func refreshLocalAvailability() { localAvailability = availabilityProvider() }

    /// Adds the asynchronous on-device speech model check to the synchronous one.
    func refreshSpeechAvailability() async {
        refreshLocalAvailability()
        guard localAvailability == .available else { return }
        let resolved = await speechAvailabilityProvider()
        if localAvailability == .available { localAvailability = resolved }
    }

    func downloadSpeechModel() async {
        guard !isDownloadingSpeechModel else { return }
        isDownloadingSpeechModel = true
        defer { isDownloadingSpeechModel = false }
        do {
            try await speechModelInstaller()
            await refreshSpeechAvailability()
        } catch {
            showErrorStatus(loc("LocalSpeechModelPreparationFailed"))
        }
    }

    /// Switching providers keeps Voice Mode on when it was on. Switching to OpenAI asks for its
    /// disclosure first unless it was already accepted. Voice Mode stays enabled while the new
    /// provider is being set up and becomes usable once `isReady` holds.
    func selectProvider(_ provider: VoiceProvider) {
        guard voiceSettings.provider != provider else { return }
        if voiceSettings.enabled && !voiceSettings.hasCurrentConsent(for: provider) {
            pendingConsentProvider = provider
            return
        }
        switchProvider(to: provider)
    }

    var isSwitchingProvider: Bool {
        pendingConsentProvider.map { $0 != voiceSettings.provider } ?? false
    }

    var hasVoiceConsent: Bool {
        voiceSettings.hasCurrentConsent
    }

    /// Whether the microphone may open a voice session now. Voice Mode can stay on while the
    /// selected mode is still being set up (no verified key, Apple Intelligence unavailable);
    /// the microphone then leads to setup instead of a session that fails immediately.
    var canStartVoice: Bool {
        voiceSettings.isReady && (voiceSettings.provider != .appleLocal || localAvailability.allowsCapture)
    }

    /// Voice Mode is switched on but the selected provider is not set up yet.
    var isVoiceSetupPending: Bool {
        guard voiceSettings.enabled else { return false }
        switch voiceSettings.provider {
        case .appleLocal: return !voiceSettings.isReady || !localAvailability.allowsCapture
        case .openAI: return !voiceSettings.isReady
        }
    }

    func acceptVoiceConsent() {
        voiceSettings.recordConsent(for: voiceSettings.provider)
        saveVoiceSettings()
    }

    /// Accepts the disclosure shown for `pendingConsentProvider`, then either completes the
    /// provider switch (keeping Voice Mode on) or enables Voice Mode for the current provider.
    func acceptPendingConsent() {
        guard let provider = pendingConsentProvider else { return }
        pendingConsentProvider = nil
        voiceSettings.recordConsent(for: provider)
        if provider == voiceSettings.provider {
            saveVoiceSettings()
            voiceEnabled = true
        } else {
            switchProvider(to: provider)
        }
    }

    func cancelPendingConsent() {
        pendingConsentProvider = nil
    }

    private func switchProvider(to provider: VoiceProvider) {
        voiceSettings.provider = provider
        voiceAPIKeyText = ""
        refreshLocalAvailability()
        saveVoiceSettings()
    }

    /// Deleting the API key (or losing it from the Keychain) withdraws OpenAI consent and turns
    /// OpenAI mode off. Apple mode is unaffected. Turning Voice Mode off alone keeps consent.
    private func withdrawCloudConsent() {
        if voiceSettings.provider == .openAI { voiceSettings.enabled = false }
        voiceSettings.revokeConsent()
    }

    func verifyVoiceAPIKey() {
        guard voiceSettings.provider == .openAI else { return }
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
        // A failed key entered while setting up a newly selected provider keeps Voice Mode
        // pending; only a setup that was working before is switched off.
        let wasReady = voiceSettings.isReady

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
                if voiceSettings.provider == .openAI && wasReady { voiceSettings.enabled = false }
                saveVoiceSettings()
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
            voiceSettings.apiKeySuffix = nil
            voiceSettings.verifiedAt = nil
            withdrawCloudConsent()
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
            showErrorStatus(loc("ImportFailedMsg", error.localizedDescription))
        }

        pendingImportData = nil
        showImportConfirmation = false
    }

    // MARK: - Helpers

    func reconcileStoredAPIKey() {
        guard let storedKey = try? apiKeyStore.readAPIKey(), !storedKey.isEmpty else {
            hasSavedVoiceAPIKey = false
            // Only a key that went missing withdraws consent; OpenAI mode that is still waiting
            // for its first key stays pending. Persist only real changes; an untouched install
            // must not gain stored settings.
            let lostKey = voiceSettings.apiKeySuffix != nil || voiceSettings.verifiedAt != nil
            guard lostKey else { return }
            voiceSettings.apiKeySuffix = nil
            voiceSettings.verifiedAt = nil
            withdrawCloudConsent()
            saveVoiceSettings()
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
