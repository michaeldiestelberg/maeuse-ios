import SwiftUI

// MARK: - Color Tokens (matching PWA Liquid Glass design system)

extension Color {
    // Primary brand
    static let maeusPrimary = Color("AccentColor")
    static let maeusPrimaryLight = Color("AccentColor").opacity(0.1)

    // Semantic
    static let maeusDestructive = Color.red
    static let maeusSuccess = Color.green

    // Surface colors adapt automatically via system light/dark
    static let maeusBackground = Color(UIColor.systemBackground)
    static let maeusSurface = Color(UIColor.secondarySystemBackground)
    static let maeusSurfaceElevated = Color(UIColor.tertiarySystemBackground)
    static let maeusInputBackground = Color(UIColor.quaternarySystemFill)

    // Text
    static let maeusText = Color(UIColor.label)
    static let maeusTextSecondary = Color(UIColor.secondaryLabel)
    static let maeusTextTertiary = Color(UIColor.tertiaryLabel)
}

// MARK: - Glass Surface Modifier

struct GlassSurface: ViewModifier {
    @Environment(\.colorScheme) var colorScheme

    var elevated: Bool = false

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .shadow(color: shadowColor, radius: elevated ? 24 : 12, y: elevated ? 8 : 4)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(borderColor, lineWidth: 0.5)
            )
    }

    private var shadowColor: Color {
        colorScheme == .dark
            ? Color.black.opacity(elevated ? 0.35 : 0.2)
            : Color.black.opacity(elevated ? 0.08 : 0.04)
    }

    private var borderColor: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.12)
            : Color.white.opacity(0.55)
    }
}

extension View {
    func glassSurface(elevated: Bool = false) -> some View {
        modifier(GlassSurface(elevated: elevated))
    }
}

// MARK: - Glass Button Style

struct GlassPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                LinearGradient(
                    colors: [Color(hex: "0f9fa6"), Color(hex: "01696f")],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .shadow(color: Color(hex: "01696f").opacity(0.25), radius: 12, y: 6)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.spring(duration: 0.25), value: configuration.isPressed)
    }
}

struct GlassSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.medium))
            .foregroundStyle(Color.maeusText)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color(UIColor.separator).opacity(0.3), lineWidth: 0.5)
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.spring(duration: 0.25), value: configuration.isPressed)
    }
}

// MARK: - FAB Style

struct FABStyle: ButtonStyle {
    var isPrimary: Bool = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(width: isPrimary ? 56 : 44, height: isPrimary ? 56 : 44)
            .background(
                isPrimary
                    ? AnyShapeStyle(LinearGradient(
                        colors: [Color(hex: "0f9fa6"), Color(hex: "01696f")],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
                    : AnyShapeStyle(.ultraThinMaterial)
            )
            .clipShape(Circle())
            .shadow(
                color: isPrimary ? Color(hex: "01696f").opacity(0.3) : Color.black.opacity(0.1),
                radius: isPrimary ? 16 : 8,
                y: isPrimary ? 6 : 3
            )
            .overlay(
                Circle().strokeBorder(
                    isPrimary ? Color.white.opacity(0.2) : Color(UIColor.separator).opacity(0.3),
                    lineWidth: 0.5
                )
            )
            .scaleEffect(configuration.isPressed ? 0.9 : 1)
            .animation(.spring(duration: 0.2), value: configuration.isPressed)
    }
}

// MARK: - Chip Style

struct ChipStyle: ButtonStyle {
    var isSelected: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.caption.weight(.medium))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                isSelected
                    ? AnyShapeStyle(Color.maeusPrimary.opacity(0.12))
                    : AnyShapeStyle(Color.maeusInputBackground)
            )
            .foregroundStyle(isSelected ? Color.maeusPrimary : Color.maeusTextSecondary)
            .clipShape(Capsule())
            .overlay(
                Capsule().strokeBorder(
                    isSelected ? Color.maeusPrimary.opacity(0.3) : Color.clear,
                    lineWidth: 0.5
                )
            )
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(.spring(duration: 0.2), value: configuration.isPressed)
    }
}

// MARK: - Hex Color Initializer

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3:
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}
