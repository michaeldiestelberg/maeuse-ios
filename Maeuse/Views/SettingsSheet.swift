import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// Settings sheet: backup/restore + voice configuration
struct SettingsSheet: View {
    @Bindable var viewModel: SettingsViewModel
    let expenses: [Expense]

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var showFilePicker = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Backup & Restore
                    backupSection

                    // Voice Settings
                    voiceSection

                    // Status
                    if viewModel.showStatus {
                        statusCard
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
                .padding(20)
            }
            .background(Color.maeusBackground)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        viewModel.isPresented = false
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .fileImporter(isPresented: $showFilePicker, allowedContentTypes: [.json]) { result in
            switch result {
            case .success(let url):
                guard url.startAccessingSecurityScopedResource() else { return }
                defer { url.stopAccessingSecurityScopedResource() }
                if let data = try? Data(contentsOf: url) {
                    viewModel.handleImportFile(data)
                }
            case .failure:
                break
            }
        }
        .alert("Replace all expenses?", isPresented: $viewModel.showImportConfirmation) {
            Button("Cancel", role: .cancel) {
                viewModel.pendingImportData = nil
            }
            Button("Replace", role: .destructive) {
                viewModel.confirmImport(context: modelContext)
            }
        } message: {
            Text("This will replace all current expenses with the imported backup. This cannot be undone.")
        }
        .alert("Voice Mode Error", isPresented: $viewModel.showVoiceError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.voiceErrorMessage)
        }
    }

    // MARK: - Backup Section

    private var backupSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader(kicker: "Data", title: "Backup & Restore")

            Text("Export your expenses to a JSON backup or import one on another device.")
                .font(.caption)
                .foregroundStyle(Color.maeusTextSecondary)

            VStack(spacing: 8) {
                Button {
                    viewModel.exportBackup(expenses: expenses)
                } label: {
                    Label("Export Backup", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(GlassPrimaryButtonStyle())

                Button {
                    showFilePicker = true
                } label: {
                    Label("Import Backup", systemImage: "square.and.arrow.down")
                }
                .buttonStyle(GlassSecondaryButtonStyle())
            }

            Text("Import replaces the expenses stored on this device after confirmation.")
                .font(.caption2)
                .foregroundStyle(Color.maeusTextTertiary)
        }
        .padding(20)
        .glassSurface()
    }

    // MARK: - Voice Section

    private var voiceSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader(kicker: "Voice", title: "Voice Mode")

            Text("Enable a realtime voice workspace that captures one or more expenses in a fresh session.")
                .font(.caption)
                .foregroundStyle(Color.maeusTextSecondary)

            // API key
            VStack(alignment: .leading, spacing: 8) {
                Text("OpenAI API key")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Color.maeusTextSecondary)

                SecureField(viewModel.hasSavedVoiceAPIKey ? "Leave blank to keep saved key" : "sk-proj-...", text: Binding(
                    get: { viewModel.voiceAPIKeyText },
                    set: { viewModel.voiceAPIKeyText = $0 }
                ))
                .textFieldStyle(.plain)
                .font(.body)
                .padding(12)
                .background(Color.maeusInputBackground)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
            }

            // Verify button
            Button {
                viewModel.verifyVoiceAPIKey()
            } label: {
                if viewModel.isVerifying {
                    ProgressView()
                        .tint(.white)
                } else {
                    Label("Verify & Save Key", systemImage: "key")
                }
            }
            .buttonStyle(GlassSecondaryButtonStyle())
            .disabled(viewModel.isVerifying)

            if viewModel.hasSavedVoiceAPIKey {
                Button(role: .destructive) {
                    viewModel.removeVoiceAPIKey()
                } label: {
                    Label("Remove Saved Key", systemImage: "trash")
                }
                .buttonStyle(GlassSecondaryButtonStyle())
            }

            // Enable toggle
            Toggle(isOn: Binding(
                get: { viewModel.voiceEnabled },
                set: { viewModel.voiceEnabled = $0 }
            )) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Enable voice mode")
                        .font(.subheadline.weight(.medium))
                    Text("Shows the mic button on the main screen")
                        .font(.caption)
                        .foregroundStyle(Color.maeusTextTertiary)
                }
            }
            .tint(Color.maeusPrimary)
            .disabled(!viewModel.voiceSettings.isVerified || !viewModel.hasSavedVoiceAPIKey)

            if !viewModel.voiceStatusText.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.maeusSuccess)
                        .font(.caption)
                    Text(viewModel.voiceStatusText)
                        .font(.caption)
                        .foregroundStyle(Color.maeusSuccess)
                }
            }

            Text("Your key is stored in iOS Keychain on this device and sent only to OpenAI over HTTPS to create short-lived Realtime client secrets.")
                .font(.caption2)
                .foregroundStyle(Color.maeusTextTertiary)

            Text("Voice mode requires an OpenAI API project with access to gpt-realtime-2; free-tier API keys are not supported for this model.")
                .font(.caption2)
                .foregroundStyle(Color.maeusTextTertiary)
        }
        .padding(20)
        .glassSurface()
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

    private func sectionHeader(kicker: String, title: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(kicker.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Color.maeusPrimary)
                .tracking(1)

            Text(title)
                .font(.headline.weight(.semibold))
                .foregroundStyle(Color.maeusText)
        }
    }
}
