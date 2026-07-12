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

    @AppStorage("maeuse.colorScheme") private var colorSchemePreference: String = "system"
    @State private var languageManager = LanguageManager.shared
    @State private var showFilePicker = false
    @State private var showFileExporter = false
    @State private var exportDocument = BackupDocument()
    @State private var showVoiceConsent = false

    var body: some View {
        VStack(spacing: 0) {
            Capsule().fill(Color.maeusTextTertiary.opacity(0.45)).frame(width: 40, height: 5).padding(.top, 10)
            settingsHeader.padding(.horizontal, 22).padding(.top, 8).padding(.bottom, 4)
            ScrollView {
                VStack(spacing: 16) {
                    // App Settings
                    appSection

                    // Voice Settings
                    voiceSection

                    // Backup & Restore
                    backupSection

                    // Privacy, terms, and support
                    legalAndSupportSection

                    // Status
                    if viewModel.showStatus {
                        statusCard
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }

                    // Help & About
                    helpSection
                }
                .padding(.horizontal, 22).padding(.top, 14).padding(.bottom, 40)
            }
            .background(Color.maeusBackground)
        }
        .fontDesign(.rounded)
        .background(Color.maeusBackground.ignoresSafeArea())
        .preferredColorScheme(resolvedColorScheme)
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
                      document: exportDocument,
                      contentType: .json,
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
        .sheet(isPresented: $showVoiceConsent) {
            VoicePrivacyConsentSheet {
                viewModel.acceptVoiceConsent()
                viewModel.voiceEnabled = true
                showVoiceConsent = false
            } onCancel: {
                showVoiceConsent = false
            }
        }
    }

    private var settingsHeader: some View {
        HStack {
            Text(loc("Settings")).font(.system(size: 20, weight: .heavy, design: .rounded)).foregroundStyle(Color.maeusForeground)
            Spacer()
            Button { viewModel.isPresented = false; dismiss() } label: {
                Text(loc("Done")).font(.system(size: 14, weight: .heavy, design: .rounded))
                    .padding(.horizontal, 16).padding(.vertical, 8)
            }
                .buttonStyle(StampedButtonStyle(fill: .maeusCheese, foreground: .maeusInk, cornerRadius: 18, borderColor: .maeusInk, shadow: 2.5))
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
        Text(text.uppercased()).font(.system(size: 11, weight: .heavy, design: .rounded)).tracking(1.5).foregroundStyle(Color.maeusTextSecondary)
    }

    private func choiceStrip(_ choices: [(String, String)], selection: Binding<String>) -> some View {
        HStack(spacing: 0) {
            ForEach(choices, id: \.1) { choice in
                choiceButton(choice.0, selected: selection.wrappedValue == choice.1) { selection.wrappedValue = choice.1 }
            }
        }
        .padding(3).background(Color.maeusInputBackground, in: Capsule()).overlay(Capsule().stroke(Color.maeusCardBorder, lineWidth: 2))
    }

    private var languageChoiceStrip: some View {
        let current = LanguageManager.shared.languagePreference
        return HStack(spacing: 0) {
            choiceButton(loc("System"), selected: current == .system) { LanguageManager.shared.languagePreference = .system }
            choiceButton(loc("English"), selected: current == .english) { LanguageManager.shared.languagePreference = .english }
            choiceButton("Deutsch", selected: current == .german) { LanguageManager.shared.languagePreference = .german }
        }
        .padding(3).background(Color.maeusInputBackground, in: Capsule()).overlay(Capsule().stroke(Color.maeusCardBorder, lineWidth: 2))
    }

    private func choiceButton(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.system(size: 13, weight: selected ? .heavy : .bold, design: .rounded))
                .foregroundStyle(selected ? Color.maeusInk : Color.maeusTextSecondary).frame(maxWidth: .infinity).padding(.vertical, 8)
                .background(selected ? Color.maeusCheese : Color.clear, in: Capsule())
                .overlay(Capsule().stroke(selected ? Color.maeusInk : Color.clear, lineWidth: 2))
        }.buttonStyle(.plain)
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

            if viewModel.hasSavedVoiceAPIKey {
                savedVoiceKeyRow
            } else {
                voiceKeyEntryField
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

            Divider()
                .overlay(Color.maeusSoftBorder)

            Toggle(isOn: Binding(
                get: { viewModel.voiceEnabled },
                set: { enabled in
                    if enabled && !viewModel.hasVoiceConsent {
                        showVoiceConsent = true
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
            .disabled(!viewModel.voiceSettings.isVerified || !viewModel.hasSavedVoiceAPIKey)

            if viewModel.hasVoiceConsent {
                Label(loc("VoiceConsentAcceptedLabel"), systemImage: "checkmark.shield.fill")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.maeusSuccess)

                Button(role: .destructive) {
                    viewModel.withdrawVoiceConsent()
                } label: {
                    Label(loc("WithdrawVoiceConsent"), systemImage: "hand.raised.slash")
                }
                .buttonStyle(GlassSecondaryButtonStyle())
            }

            Text(loc("KeychainStorageDesc"))
                .font(.caption)
                .foregroundStyle(Color.maeusTextSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Text(loc("VoiceRequirementsDesc"))
                .font(.caption)
                .foregroundStyle(Color.maeusTextSecondary)
                .fixedSize(horizontal: false, vertical: true)
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
            .font(.system(size: 13, weight: .bold, design: .rounded))
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
        }
        .padding(.horizontal, 12)
        .frame(height: 38)
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

private struct VoicePrivacyConsentSheet: View {
    let onAccept: () -> Void
    let onCancel: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    MouseCoin(size: 72, fill: .maeusCheese) {
                        Image(systemName: "waveform")
                            .font(.system(size: 26, weight: .heavy))
                            .foregroundStyle(Color.maeusInk)
                    }
                    .frame(maxWidth: .infinity)

                    Text(loc("VoicePrivacyIntro"))
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.maeusTextSecondary)

                    disclosureRow(
                        icon: "mic.fill",
                        title: loc("VoicePrivacyDataTitle"),
                        body: loc("VoicePrivacyDataDesc")
                    )

                    disclosureRow(
                        icon: "clock.fill",
                        title: loc("VoicePrivacyRetentionTitle"),
                        body: loc("VoicePrivacyRetentionDesc")
                    )

                    disclosureRow(
                        icon: "creditcard.fill",
                        title: loc("VoicePrivacyBillingTitle"),
                        body: loc("VoicePrivacyBillingDesc")
                    )

                    Link(loc("ReadPrivacyPolicy"), destination: URL(string: "https://xn--muse-loa.app/privacy.html#voice-mode")!)
                        .font(.system(size: 14, weight: .heavy, design: .rounded))

                    Button(action: onAccept) {
                        Text(loc("AgreeEnableVoice"))
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
