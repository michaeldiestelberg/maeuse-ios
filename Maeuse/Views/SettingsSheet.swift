import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// Settings sheet: backup/restore + voice configuration
struct SettingsSheet: View {
    @Bindable var viewModel: SettingsViewModel
    let expenses: [Expense]
    let onShowWelcomeGuide: () -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @AppStorage("maeuse.colorScheme") private var colorSchemePreference: String = "system"
    @State private var languageManager = LanguageManager.shared
    @State private var showFilePicker = false
    @State private var showFileExporter = false
    @State private var exportDocument = BackupDocument()
    @State private var consentRequest: VoiceProvider?
    @State private var showModeSelection = false
    @State private var showsDiagnosis = false
    @State private var diagnosisStore = LocalVoiceDiagnosticStore.shared

    var body: some View {
        GeometryReader { geometry in
        VStack(spacing: 0) {
            Capsule().fill(Color.maeusTextTertiary.opacity(0.45)).frame(width: 40, height: 5).padding(.top, 10)
            settingsHeader.padding(.horizontal, 22).padding(.top, 8).padding(.bottom, 4)
            ScrollViewReader { proxy in
            ScrollView {
                settingsContent(wide: geometry.size.width >= 720 && !dynamicTypeSize.isAccessibilitySize)
                    .padding(.horizontal, 22).padding(.top, 14).padding(.bottom, 40)
                    .frame(maxWidth: 1080).frame(maxWidth: .infinity)
            }
            .background(Color.maeusBackground)
            .accessibilityIdentifier("settings-scroll")
            #if targetEnvironment(simulator)
            .onAppear {
                if ProcessInfo.processInfo.arguments.contains("--settings-local-diagnostic") {
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(250))
                        proxy.scrollTo("local-diagnostics", anchor: .top)
                    }
                }
            }
            #endif
            }
        }
        }
        .fontDesign(.rounded)
        .background(Color.maeusBackground.ignoresSafeArea())
        .preferredColorScheme(resolvedColorScheme)
        .modifier(MaeusePagePresentation())
        .presentationDetents([.large])
        .presentationDragIndicator(.hidden)
        .presentationCornerRadius(30)
        .fileImporter(isPresented: $showFilePicker, allowedContentTypes: [.json]) { result in
            switch result {
            case .success(let url):
                let accessed = url.startAccessingSecurityScopedResource()
                defer { if accessed { url.stopAccessingSecurityScopedResource() } }
                do {
                    let data = try Data(contentsOf: url)
                    viewModel.handleImportFile(data)
                } catch {
                    viewModel.handleImportError(error)
                }
            case .failure(let error):
                if (error as NSError).code != NSUserCancelledError {
                    viewModel.handleImportError(error)
                }
            }
        }
        .fileExporter(isPresented: $showFileExporter,
                      item: exportDocument,
                      contentTypes: [.json],
                      defaultFilename: BackupService.exportFileName()) {
            viewModel.exportCompleted($0)
        }
        .alert(loc("ReplaceExpensesTitle"), isPresented: $viewModel.showImportConfirmation) {
            Button(loc("Cancel"), role: .cancel) {
                viewModel.pendingImportData = nil
            }
            Button(loc("Replace"), role: .destructive) {
                viewModel.confirmImport(context: modelContext)
            }
        } message: {
            Text(loc("ReplaceExpensesMsg"))
        }
        .alert(loc("VoiceModeErrorTitle"), isPresented: $viewModel.showVoiceError) {
            Button(loc("OK"), role: .cancel) {}
        } message: {
            Text(viewModel.voiceErrorMessage)
        }
        .onAppear { viewModel.refreshLocalAvailability() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { viewModel.refreshLocalAvailability() }
        }
        .onChange(of: languageManager.activeLanguageCode) { _, _ in viewModel.refreshLocalAvailability() }
        // Switching to OpenAI while Voice Mode is on asks for its disclosure; it can only be
        // presented once the chooser has closed.
        .sheet(isPresented: $showModeSelection, onDismiss: { consentRequest = viewModel.pendingConsentProvider }) {
            VoiceModeSelectionView(viewModel: viewModel) { provider in
                viewModel.confirmVoiceMode(provider)
                showModeSelection = false
            } onCancel: { showModeSelection = false }
        }
        .sheet(item: $consentRequest) { _ in
            VoicePrivacyConsentSheet(isSwitching: viewModel.isSwitchingProvider) {
                viewModel.acceptPendingConsent()
                consentRequest = nil
            } onCancel: {
                viewModel.cancelPendingConsent()
                consentRequest = nil
            }
        }
        .onAppear { if consentRequest == nil { consentRequest = viewModel.pendingConsentProvider } }
    }

    @ViewBuilder
    private func settingsContent(wide: Bool) -> some View {
        if wide {
            HStack(alignment: .top, spacing: 20) {
                VStack(spacing: 16) {
                    appSection
                    backupSection
                    legalAndSupportSection
                    helpSection
                    if viewModel.showStatus { statusCard }
                }.frame(maxWidth: .infinity)
                voiceSection.frame(maxWidth: .infinity)
            }.accessibilityIdentifier("settings-wide")
        } else {
            VStack(spacing: 16) {
                appSection
                voiceSection
                backupSection
                legalAndSupportSection
                if viewModel.showStatus { statusCard }
                helpSection
            }
        }
    }

    private var settingsHeader: some View {
        HStack {
            Text(loc("Settings")).font(.system(.title3, design: .rounded, weight: .heavy)).foregroundStyle(Color.maeusForeground)
            Spacer()
            Button { viewModel.isPresented = false; dismiss() } label: {
                Text(loc("Done")).font(.system(.subheadline, design: .rounded, weight: .heavy))
                    .padding(.horizontal, 16).padding(.vertical, 8)
            }
                .buttonStyle(StampedButtonStyle(fill: .maeusCheese, foreground: .maeusInk, cornerRadius: 18, borderColor: .maeusInk, shadow: 2.5))
                .accessibilityIdentifier("settings-done")
        }
    }

    private var resolvedColorScheme: ColorScheme? {
        switch colorSchemePreference {
        case "light": return .light
        case "dark": return .dark
        default: return nil
        }
    }

    // MARK: - App Section

    private var appSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            themeLabel(loc("Appearance"))
            choiceStrip([
                (loc("System"), "system"), (loc("Light"), "light"), (loc("Dark"), "dark")
            ], selection: $colorSchemePreference)

            Divider()
                .overlay(Color.maeusSoftBorder).frame(height: 2)

            themeLabel(loc("Language"))
            languageChoiceStrip
        }
        .padding(18)
        .glassSurface()
    }

    private func themeLabel(_ text: String) -> some View {
        Text(text.uppercased()).font(.system(.caption, design: .rounded, weight: .heavy)).tracking(1.5).foregroundStyle(Color.maeusTextSecondary)
    }

    private func choiceStrip(_ choices: [(String, String)], selection: Binding<String>) -> some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: 6)) : AnyLayout(HStackLayout(spacing: 0))
        return layout {
            ForEach(choices, id: \.1) { choice in
                choiceButton(choice.0, selected: selection.wrappedValue == choice.1) { selection.wrappedValue = choice.1 }
            }
        }
        .padding(3).background(Color.maeusInputBackground, in: RoundedRectangle(cornerRadius: 18)).overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.maeusCardBorder, lineWidth: 2))
    }

    private var languageChoiceStrip: some View {
        let current = LanguageManager.shared.languagePreference
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: 6)) : AnyLayout(HStackLayout(spacing: 0))
        return layout {
            choiceButton(loc("System"), selected: current == .system) { LanguageManager.shared.languagePreference = .system }
            choiceButton(loc("English"), selected: current == .english) { LanguageManager.shared.languagePreference = .english }
            choiceButton("Deutsch", selected: current == .german) { LanguageManager.shared.languagePreference = .german }
        }
        .padding(3).background(Color.maeusInputBackground, in: RoundedRectangle(cornerRadius: 18)).overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.maeusCardBorder, lineWidth: 2))
    }

    private func choiceButton(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.system(.subheadline, design: .rounded, weight: selected ? .heavy : .bold))
                .foregroundStyle(selected ? Color.maeusInk : Color.maeusTextSecondary)
                .fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, minHeight: 44).padding(.vertical, 4)
                .background(selected ? Color.maeusCheese : Color.clear, in: Capsule())
                .overlay(Capsule().stroke(selected ? Color.maeusInk : Color.clear, lineWidth: 2))
        }.buttonStyle(.plain)
    }

    /// Only meaningful while Apple's on-device mode is chosen and Voice Mode is on.
    private var showsLocalDiagnostics: Bool {
        viewModel.voiceSettings.provider == .appleLocal && viewModel.voiceEnabled
    }

    private var diagnosticsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            DisclosureGroup(isExpanded: $showsDiagnosis) {
                if let diagnostic = diagnosisStore.displayed {
                    Text(diagnostic.exportText).font(.caption.monospaced()).textSelection(.enabled)
                        .accessibilityIdentifier("settings-local-diagnostic-details")
                    ShareLink(item: diagnostic.exportText) {
                        Label(loc("LocalShareDiagnosis"), systemImage: "square.and.arrow.up")
                    }.frame(minHeight: 44).accessibilityIdentifier("settings-local-diagnostic-share")
                    Button(loc("LocalClearDiagnosis")) { diagnosisStore.clear() }
                        .frame(minHeight: 44)
                } else { Text(loc("LocalDiagnosisEmpty")).font(.callout) }
                Text(loc("LocalDiagnosisPrivacy")).font(.caption).foregroundStyle(Color.maeusTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            } label: {
                Label(loc("LocalDiagnosis"), systemImage: "stethoscope").font(.subheadline.weight(.bold)).frame(minHeight: 44)
            }
        }.foregroundStyle(Color.maeusForeground)
        .accessibilityIdentifier("settings-local-diagnostic")
        #if targetEnvironment(simulator)
        .onAppear { if ProcessInfo.processInfo.arguments.contains("--settings-local-diagnostic") { showsDiagnosis = true } }
        #endif
    }

    // MARK: - Backup Section

    private var backupSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            themeLabel(loc("BackupRestore"))

            VStack(spacing: 8) {
                Button {
                    if let document = viewModel.prepareBackup(expenses: expenses) {
                        exportDocument = document
                        showFileExporter = true
                    }
                } label: {
                    Label(loc("ExportBackup"), systemImage: "square.and.arrow.up")
                }
                .buttonStyle(GlassPrimaryButtonStyle())

                Button {
                    showFilePicker = true
                } label: {
                    Label(loc("ImportBackup"), systemImage: "square.and.arrow.down")
                }
                .buttonStyle(GlassSecondaryButtonStyle())
            }

        }
        .padding(18)
        .glassSurface()
    }

    // MARK: - Voice Section

    private var voiceSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            themeLabel(loc("VoiceMode"))

            HStack {
                Text(viewModel.voiceSettings.provider.title).font(.headline)
                Spacer()
                Button(loc("VoiceChangeMode")) { showModeSelection = true }
                    .font(.subheadline.weight(.bold)).frame(minHeight: 44)
                    .accessibilityLabel(loc("VoiceChangeModeAccessibility"))
                    .accessibilityIdentifier("voice-change-mode").disabled(viewModel.isVerifying)
            }
            if viewModel.voiceSettings.provider == .appleLocal {
                // How Apple mode behaves is explained in the mode chooser; here only the
                // device state matters, with requirements shown when something is missing.
                Text(viewModel.localAvailability.message)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color.maeusTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .task(id: viewModel.voiceSettings.provider) { await viewModel.refreshSpeechAvailability() }
                if !viewModel.localAvailability.allowsCapture {
                    Text(loc("LocalRequirements")).font(.caption).foregroundStyle(Color.maeusTextSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if viewModel.localAvailability == .speechModelMissing {
                    Button {
                        Task { await viewModel.downloadSpeechModel() }
                    } label: {
                        HStack(spacing: 8) {
                            if viewModel.isDownloadingSpeechModel { ProgressView() }
                            Text(loc(viewModel.isDownloadingSpeechModel ? "LocalSpeechModelDownloading" : "LocalDownloadSpeechModel"))
                        }
                    }
                    .buttonStyle(GlassSecondaryButtonStyle())
                    .disabled(viewModel.isDownloadingSpeechModel)
                    .accessibilityIdentifier("local-download-speech-model")
                }
                if !viewModel.localAvailability.allowsCapture {
                    Button(loc("LocalCheckAgain")) { Task { await viewModel.refreshSpeechAvailability() } }
                        .buttonStyle(GlassSecondaryButtonStyle())
                }
                if showsLocalDiagnostics {
                    Divider().overlay(Color.maeusSoftBorder)
                    diagnosticsSection.id("local-diagnostics")
                }
            } else {
                Text(loc("VoiceChoiceCloudBody"))
                    .font(.caption).foregroundStyle(Color.maeusTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            if viewModel.hasSavedVoiceAPIKey {
                savedVoiceKeyRow
            } else {
                voiceKeyEntryField

                Link(destination: URL(string: "https://xn--muse-loa.app/openai-api-key.html")!) {
                    HStack(spacing: 4) {
                        Image(systemName: "questionmark.circle")
                        Text(loc("HowToGetApiKey"))
                        Image(systemName: "arrow.up.right")
                            .font(.caption2.weight(.heavy))
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.maeusPrimaryHover)
                }
            }

            if !viewModel.hasSavedVoiceAPIKey || !viewModel.voiceSettings.isVerified {
                Button {
                    viewModel.verifyVoiceAPIKey()
                } label: {
                    if viewModel.isVerifying {
                        ProgressView().tint(.white)
                    } else {
                        Label(loc("VerifySaveKey"), systemImage: "key")
                    }
                }
                .buttonStyle(GlassSecondaryButtonStyle())
                .disabled(
                    viewModel.isVerifying
                    || (!viewModel.hasSavedVoiceAPIKey && viewModel.voiceAPIKeyText.isEmpty)
                )
            }

            if viewModel.hasSavedVoiceAPIKey {
                Button(role: .destructive) {
                    viewModel.removeVoiceAPIKey()
                } label: {
                    Label(loc("RemoveSavedKey"), systemImage: "trash")
                }
                .buttonStyle(GlassSecondaryButtonStyle())
            }

            }

            Divider()
                .overlay(Color.maeusSoftBorder)

            Toggle(isOn: Binding(
                get: { viewModel.voiceEnabled },
                set: { enabled in
                    if enabled && !viewModel.hasVoiceConsent {
                        viewModel.pendingConsentProvider = viewModel.voiceSettings.provider
                        consentRequest = viewModel.voiceSettings.provider
                    } else {
                        viewModel.voiceEnabled = enabled
                    }
                }
            )) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(loc("EnableVoiceMode"))
                        .font(.subheadline.weight(.medium))
                    Text(loc("ShowsMicButton"))
                        .font(.caption)
                        .foregroundStyle(Color.maeusTextTertiary)
                }
            }
            .tint(Color.maeusPrimary)
            .disabled(!viewModel.voiceEnabled && !viewModel.canEnableVoice)
            .accessibilityIdentifier("voice-enable")

            if viewModel.isVoiceSetupPending {
                Label(loc("VoicePendingSetup"), systemImage: "hourglass")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.maeusTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("voice-pending-setup")
            }

            Toggle(isOn: Binding(
                get: { viewModel.voiceSettings.hapticsEnabled },
                set: {
                    viewModel.voiceSettings.hapticsEnabled = $0
                    viewModel.saveVoiceSettings()
                }
            )) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(loc("VoiceHaptics"))
                        .font(.subheadline.weight(.medium))
                    Text(loc("VoiceHapticsDesc"))
                        .font(.caption)
                        .foregroundStyle(Color.maeusTextTertiary)
                }
            }
            .tint(Color.maeusPrimary)
        }
        .padding(18)
        .glassSurface()
    }

    // MARK: - Legal & Support Section

    private var legalAndSupportSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            themeLabel(loc("PrivacySupport"))

            Link(destination: URL(string: "https://xn--muse-loa.app/privacy.html")!) {
                legalLinkLabel(loc("PrivacyPolicy"), systemImage: "hand.raised.fill")
            }

            Link(destination: URL(string: "https://xn--muse-loa.app/support.html")!) {
                legalLinkLabel(loc("Support"), systemImage: "envelope.fill")
            }

            Link(destination: URL(string: "https://xn--muse-loa.app/terms.html")!) {
                legalLinkLabel(loc("TermsOfUse"), systemImage: "doc.text.fill")
            }
        }
        .padding(18)
        .glassSurface()
    }

    private func legalLinkLabel(_ title: String, systemImage: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .frame(width: 20)
                .foregroundStyle(Color.maeusPrimaryHover)
            Text(title)
                .font(.system(size: 14, weight: .heavy, design: .rounded))
                .foregroundStyle(Color.maeusForeground)
            Spacer()
            Image(systemName: "arrow.up.right")
                .font(.caption.weight(.heavy))
                .foregroundStyle(Color.maeusTextTertiary)
        }
        .padding(.vertical, 4)
    }

    private var savedVoiceKeyRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "lock.fill")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Color.maeusTextSecondary)

            VStack(alignment: .leading, spacing: 2) {
                Text(loc("OpenAIApiKey"))
                    .font(.system(size: 12, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color.maeusForeground)

                Text(viewModel.voiceSettings.maskedAPIKey)
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color.maeusTextSecondary)
            }

            Spacer()

            if viewModel.voiceSettings.isVerified {
                Label(loc("Verified"), systemImage: "checkmark.circle.fill")
                    .font(.system(size: 10, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color.maeusSuccess)
            }
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 48)
        .background(Color.maeusInputBackground, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.maeusCardBorder, lineWidth: 1.5))
    }

    private var voiceKeyEntryField: some View {
        HStack(spacing: 8) {
            Image(systemName: "lock")
                .font(.caption.weight(.bold))
                .foregroundStyle(Color.maeusTextSecondary)

            SecureField("sk-proj-...", text: Binding(
                get: { viewModel.voiceAPIKeyText },
                set: { viewModel.voiceAPIKeyText = $0 }
            ))
            .textFieldStyle(.plain)
            .font(.system(.subheadline, design: .rounded, weight: .bold))
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 44)
        .background(Color.maeusInputBackground, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.maeusCardBorder, lineWidth: 1.5))
    }

    // MARK: - Help Section

    private var helpSection: some View {
        Button {
            viewModel.isPresented = false
            dismiss()
            onShowWelcomeGuide()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "questionmark.circle")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(Color.maeusPrimaryHover)

                VStack(alignment: .leading, spacing: 2) {
                    Text(loc("HelpAbout"))
                        .font(.system(size: 14, weight: .heavy, design: .rounded))
                        .foregroundStyle(Color.maeusForeground)

                    Text(loc("WelcomeGuideDesc"))
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.maeusTextSecondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .heavy))
                    .foregroundStyle(Color.maeusTextTertiary)
            }
            .padding(18)
            .contentShape(Rectangle())
            .glassSurface()
        }
        .buttonStyle(.plain)
        .accessibilityLabel(loc("HelpAbout"))
        .accessibilityIdentifier("settings-help")
    }

    // MARK: - Helpers

    private var statusCard: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: viewModel.statusIsError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(viewModel.statusIsError ? Color.orange : Color.maeusSuccess)

            Text(viewModel.statusMessage)
                .font(.caption)
                .foregroundStyle(Color.maeusTextSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
        .padding(12)
        .background(Color.maeusSurface)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

}

/// One-time disclosure for OpenAI mode, which sends voice data to a third party.
private struct VoicePrivacyConsentSheet: View {
    let isSwitching: Bool
    let onAccept: () -> Void
    let onCancel: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    MouseCoin(size: 64, fill: .maeusCheese) {
                        Image(systemName: "waveform")
                            .font(.system(size: 24, weight: .heavy))
                            .foregroundStyle(Color.maeusInk)
                    }
                    .frame(maxWidth: .infinity)

                    disclosureRow(icon: "mic.fill", title: loc("VoicePrivacyDataTitle"), body: loc("VoicePrivacyDataDesc"))
                    disclosureRow(icon: "clock.fill", title: loc("VoicePrivacyRetentionTitle"), body: loc("VoicePrivacyRetentionDesc"))
                    disclosureRow(icon: "creditcard.fill", title: loc("VoicePrivacyBillingTitle"), body: loc("VoicePrivacyBillingDesc"))

                    Text(loc("VoicePrivacyControl"))
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.maeusTextSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Link(loc("ReadPrivacyPolicy"), destination: URL(string: "https://xn--muse-loa.app/privacy.html#voice-mode")!)
                        .font(.system(size: 14, weight: .heavy, design: .rounded))

                    Button(action: onAccept) {
                        Text(loc(isSwitching ? "AgreeSwitchVoice" : "AgreeEnableVoice"))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(GlassPrimaryButtonStyle())

                    Button(loc("NotNow"), action: onCancel)
                        .buttonStyle(GlassSecondaryButtonStyle())
                }
                .padding(22)
            }
            .background(Color.maeusBackground)
            .navigationTitle(loc("VoicePrivacyTitle"))
            .navigationBarTitleDisplayMode(.inline)
        }
        .fontDesign(.rounded)
        .presentationDetents([.large])
        .interactiveDismissDisabled()
    }

    private func disclosureRow(icon: String, title: String, body: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(Color.maeusPrimaryHover)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 14, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color.maeusForeground)
                Text(body)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.maeusTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// Invoked for Voice Mode setup/change, never at app launch or as a recording action.
struct VoiceModeSelectionView: View {
    @Bindable var viewModel: SettingsViewModel
    let onSelect: (VoiceProvider) -> Void
    let onCancel: () -> Void
    @State private var selection: VoiceProvider
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    init(viewModel: SettingsViewModel, onSelect: @escaping (VoiceProvider) -> Void, onCancel: @escaping () -> Void) {
        self.viewModel = viewModel; self.onSelect = onSelect; self.onCancel = onCancel
        // Until a mode is chosen, preselect the recommended one.
        _selection = State(initialValue: viewModel.hasSelectedVoiceMode ? viewModel.voiceSettings.provider : .openAI)
    }

    var body: some View {
        GeometryReader { geometry in
            let wide = geometry.size.width >= 720 && !dynamicTypeSize.isAccessibilitySize
            VStack(spacing: 0) {
                HStack {
                    Text(loc("VoiceMode")).font(.headline.weight(.heavy))
                    Spacer()
                    Button(action: onCancel) { Image(systemName: "xmark").font(.headline).frame(width: 44, height: 44) }
                        .accessibilityLabel(loc("Close"))
                }.padding(.horizontal, 22).padding(.top, 12)
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        if wide {
                            HStack(spacing: 24) {
                                modeEmblem
                                introduction
                            }
                        } else {
                            // On shorter sheets (e.g. the unfolded iPhone Duo) the emblem would
                            // push the second option entirely below the fold.
                            if geometry.size.height >= 760 { modeEmblem.frame(maxWidth: .infinity) }
                            introduction
                        }
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), alignment: .top), count: wide ? 2 : 1), spacing: 18) {
                            // Recommended provider first: the cloud mode is far more accurate.
                            ForEach([VoiceProvider.openAI, .appleLocal]) { provider in providerCard(provider) }
                        }.accessibilityIdentifier("voice-choice-options")
                    }
                    .padding(.horizontal, 22).padding(.vertical, 20)
                    .frame(maxWidth: 1040).frame(maxWidth: .infinity)
                }
                .scrollIndicatorsFlash(onAppear: true)
                .accessibilityIdentifier("voice-choice-scroll")
                Button(loc("VoiceChoiceConfirm")) { onSelect(selection) }
                    .buttonStyle(GlassPrimaryButtonStyle()).padding(22)
                    .frame(maxWidth: 1040).frame(maxWidth: .infinity)
                    .accessibilityIdentifier("voice-choice-confirm").disabled(viewModel.isVerifying)
            }
        }
        .foregroundStyle(Color.maeusForeground).fontDesign(.rounded)
        .background(Color.maeusBackground.ignoresSafeArea())
        .modifier(MaeusePagePresentation())
        .presentationDetents([.large]).presentationDragIndicator(.visible)
        .onAppear {
            viewModel.refreshLocalAvailability()
            #if targetEnvironment(simulator)
            if ProcessInfo.processInfo.arguments.contains("--screenshot-voice-choice") { viewModel.localAvailability = .available }
            if ProcessInfo.processInfo.arguments.contains("--screenshot-voice-choice-unavailable") { viewModel.localAvailability = .deviceNotEligible }
            #endif
        }
    }

    private var modeEmblem: some View {
        MouseCoin(size: 82, fill: .maeusCheese) {
            Image(systemName: "mic.fill").font(.system(size: 30, weight: .heavy)).foregroundStyle(Color.maeusInk)
        }.accessibilityHidden(true)
    }

    private var introduction: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(loc("VoiceChooseTitle")).font(.system(.largeTitle, design: .rounded, weight: .heavy))
                .fixedSize(horizontal: false, vertical: true)
            Text(loc("VoiceChooseIntro")).font(.body).foregroundStyle(Color.maeusTextSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func providerCard(_ provider: VoiceProvider) -> some View {
        let selected = selection == provider
        let recommended = provider == .openAI
        return Button { selection = provider } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(provider.title).font(.headline.weight(.heavy)).fixedSize(horizontal: false, vertical: true)
                    Text(loc(recommended ? "VoiceRecommended" : "VoiceFree"))
                        .font(.system(.caption, design: .rounded, weight: .heavy))
                        .foregroundStyle(recommended ? Color.maeusInk : Color.maeusSuccess)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(recommended ? Color.maeusCheese : Color.maeusSuccess.opacity(0.18), in: Capsule())
                    Spacer(minLength: 4)
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(selected ? Color.maeusForeground : Color.maeusTextTertiary)
                        .accessibilityHidden(true)
                }
                Text(loc(recommended ? "VoiceCloudSummary" : "VoiceAppleSummary"))
                    .font(.callout.weight(.semibold)).foregroundStyle(Color.maeusTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(providerPoints(provider), id: \.text) { point in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Image(systemName: point.icon)
                                .foregroundStyle(point.isCaveat ? Color.orange : Color.maeusTextSecondary)
                                .frame(width: 18).accessibilityHidden(true)
                            Text(point.text).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .font(.caption).foregroundStyle(Color.maeusTextSecondary)
                if provider == .appleLocal && !viewModel.localAvailability.allowsCapture {
                    Label(loc("VoiceChoiceUnavailable"), systemImage: "exclamationmark.circle")
                        .font(.caption.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
                }
            }.padding(18).frame(maxWidth: .infinity, alignment: .leading)
            // Only selection changes the card's look: the selected card is stamped like the
            // app's buttons, the other stays flat. "Recommended" is carried by the badge.
            .background {
                let shape = RoundedRectangle(cornerRadius: 20, style: .continuous)
                ZStack {
                    if selected { shape.fill(Color.maeusInk).offset(x: 3, y: 3) }
                    shape.fill(selected ? Self.selectedFill : Color.maeusSurface)
                    shape.stroke(selected ? Self.selectedBorder : Color.maeusSoftBorder, lineWidth: selected ? 2 : 1.5)
                }
            }
            .animation(.easeOut(duration: 0.15), value: selected)
        }.buttonStyle(.plain).accessibilityElement(children: .combine)
            .accessibilityAddTraits(selected ? .isSelected : [])
            .accessibilityIdentifier("voice-choice-\(provider.rawValue)")
    }

    private static let selectedFill = Color(light: Color(hex: "FFE9A3"), dark: Color(hex: "4A3B10"))
    private static let selectedBorder = Color(light: .maeusInk, dark: .maeusCheese)

    private func providerPoints(_ provider: VoiceProvider) -> [(icon: String, text: String, isCaveat: Bool)] {
        switch provider {
        case .openAI:
            return [("scope", loc("VoiceCloudPointAccuracy"), false),
                    ("waveform", loc("VoiceCloudPointFlow"), false),
                    ("dollarsign.circle", loc("VoiceCloudPointCost"), false),
                    ("cloud", loc("VoiceCloudPointPrivacy"), false)]
        case .appleLocal:
            return [("exclamationmark.triangle", loc("VoiceApplePointAccuracy"), true),
                    ("pause.circle", loc("VoiceApplePointFlow"), false),
                    ("gift", loc("VoiceApplePointCost"), false),
                    ("iphone", loc("VoiceApplePointPrivacy"), false)]
        }
    }
}
