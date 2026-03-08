import SwiftUI

/// Full-screen onboarding overlay (matches the PWA welcome screen)
struct OnboardingView: View {
    @Binding var isPresented: Bool
    var onDismiss: (Bool) -> Void

    @State private var dontShowAgain: Bool = true
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            // Background
            Group {
                if colorScheme == .dark {
                    LinearGradient(
                        colors: [Color(hex: "0a0a0a"), Color(hex: "050505"), .black],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                } else {
                    LinearGradient(
                        colors: [Color(hex: "f4f3ef"), Color(hex: "eae8e1"), Color(hex: "e4e2db")],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                }
            }
            .ignoresSafeArea()

            VStack(spacing: 20) {
                Spacer()

                // Logo
                Image(systemName: "banknote")
                    .font(.system(size: 52))
                    .foregroundStyle(Color.maeusPrimary)
                    .frame(width: 88, height: 88)
                    .background(Color.maeusPrimaryLight)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))

                // Title
                Text("Mäuse")
                    .font(.system(.title, weight: .bold))
                    .tracking(-0.5)
                    .foregroundStyle(Color.maeusText)

                // Subtitle
                Text("Split expenses with your partner, effortlessly.")
                    .font(.subheadline)
                    .foregroundStyle(Color.maeusTextSecondary)

                // Steps
                VStack(spacing: 12) {
                    onboardingStep(
                        icon: "dollarsign",
                        title: "Log an expense",
                        subtitle: "Enter the amount and a short description"
                    )
                    onboardingStep(
                        icon: "plus.circle",
                        title: "Choose how to split",
                        subtitle: "By percentage or a fixed amount"
                    )
                    onboardingStep(
                        icon: "calendar",
                        title: "Track monthly totals",
                        subtitle: "See what your partner owes at a glance"
                    )
                }
                .padding(.top, 8)

                // Checkbox
                Toggle(isOn: $dontShowAgain) {
                    Text("Don't show this again")
                        .font(.caption)
                        .foregroundStyle(Color.maeusTextSecondary)
                }
                .toggleStyle(.checkboxStyle)
                .padding(.top, 4)

                // Get Started button
                Button("Get Started") {
                    onDismiss(dontShowAgain)
                    withAnimation(.easeOut(duration: 0.35)) {
                        isPresented = false
                    }
                }
                .buttonStyle(GlassPrimaryButtonStyle())
                .padding(.top, 4)

                // Hint
                Text("\"Mäuse\" is German slang for money — literally \"mice\"")
                    .font(.caption2)
                    .foregroundStyle(Color.maeusTextTertiary)
                    .italic()

                Spacer()
            }
            .padding(.horizontal, 32)
            .frame(maxWidth: 400)
        }
    }

    private func onboardingStep(icon: String, title: String, subtitle: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.body)
                .foregroundStyle(Color.maeusPrimary)
                .frame(width: 32, height: 32)
                .background(Color.maeusPrimaryLight)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.maeusText)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(Color.maeusTextTertiary)
            }

            Spacer()
        }
        .padding(12)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color(UIColor.separator).opacity(0.15), lineWidth: 0.5)
        )
    }
}

// MARK: - Checkbox Toggle Style

struct CheckboxToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: configuration.isOn ? "checkmark.square.fill" : "square")
                    .foregroundStyle(configuration.isOn ? Color.maeusPrimary : Color.maeusTextTertiary)
                configuration.label
            }
        }
    }
}

extension ToggleStyle where Self == CheckboxToggleStyle {
    static var checkboxStyle: CheckboxToggleStyle { CheckboxToggleStyle() }
}
