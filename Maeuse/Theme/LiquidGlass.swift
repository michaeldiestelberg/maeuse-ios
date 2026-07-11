import SwiftUI

// MARK: - Mäuse “Cheese & Ink” theme

extension Color {
    static let maeusCheese = Color(hex: "FFCF3F")
    static let maeusInk = Color(hex: "241C05")
    static let maeusBackground = Color(light: Color(hex: "FFF6DE"), dark: Color(hex: "211A09"))
    static let maeusSurface = Color(light: .white, dark: Color(hex: "31280F"))
    static let maeusSurfaceElevated = maeusSurface
    static let maeusInputBackground = Color(light: Color(hex: "FFF1C2"), dark: Color(hex: "3A3013"))
    static let maeusPrimary = maeusCheese
    static let maeusPrimaryLight = Color(light: Color(hex: "FFF1C2"), dark: Color(hex: "3A3013"))
    static let maeusPrimaryHover = Color(light: Color(hex: "D19000"), dark: Color(hex: "FFB800"))
    static let maeusAccentSecondary = Color(hex: "D19000")
    static let maeusAccentTertiary = Color(hex: "FFB800")
    static let maeusAccentWarm = Color(hex: "FFCF3F")
    static let maeusDestructive = Color(light: Color(hex: "CE4A21"), dark: Color(hex: "FF8A5C"))
    static let maeusSuccess = Color(hex: "3CA455")
    static let maeusForeground = Color(light: maeusInk, dark: Color(hex: "FFF6DE"))
    static let maeusTextSecondary = Color(light: Color(hex: "A08F55"), dark: Color(hex: "B9A96E"))
    static let maeusTextTertiary = Color(light: Color(hex: "C4B584"), dark: Color(hex: "6E5F33"))
    static let maeusCardBorder = Color(light: maeusInk, dark: Color(hex: "665423"))
    static let maeusSoftBorder = Color(light: Color(hex: "E8DFC4"), dark: Color(hex: "4A3E18"))
}

extension LinearGradient {
    static let maeusTriGradient = LinearGradient(colors: [.maeusCheese, .maeusPrimaryHover], startPoint: .top, endPoint: .bottom)
}

struct PrismBackground: View {
    var body: some View { Color.maeusBackground.ignoresSafeArea() }
}

struct CheeseCard<Content: View>: View {
    var cornerRadius: CGFloat = 22
    var borderWidth: CGFloat = 2.5
    var shadow: CGFloat = 4
    var fill: Color = .maeusSurface
    var borderColor: Color = .maeusCardBorder
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .background {
                let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                ZStack {
                    shape.fill(cardShadowColor).offset(x: shadow, y: shadow)
                    shape.fill(fill)
                    shape.stroke(borderColor, lineWidth: borderWidth)
                }
            }
    }

    private var cardShadowColor: Color {
        shadow >= 5 ? .maeusInk : Color(light: Color.maeusInk.opacity(0.12), dark: Color.black.opacity(0.5))
    }
}

struct GlassSurface: ViewModifier {
    var elevated = false
    func body(content: Content) -> some View {
        CheeseCard(cornerRadius: 22, shadow: elevated ? 5 : 4) { content }
    }
}

extension View {
    func glassSurface(elevated: Bool = false) -> some View { modifier(GlassSurface(elevated: elevated)) }
    func maeusRounded() -> some View { fontDesign(.rounded) }
}

struct StampedButtonStyle: ButtonStyle {
    var fill: Color = .maeusCheese
    var foreground: Color = .maeusInk
    var cornerRadius: CGFloat = 14
    var borderColor: Color = .maeusInk
    var shadow: CGFloat = 3
    var shadowColor: Color = .maeusInk

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(foreground)
            .background {
                let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                ZStack {
                    shape.fill(shadowColor).offset(x: configuration.isPressed ? 1 : shadow, y: configuration.isPressed ? 1 : shadow)
                    shape.fill(fill)
                    shape.stroke(borderColor, lineWidth: 2)
                }
            }
            .offset(x: configuration.isPressed ? 2 : 0, y: configuration.isPressed ? 2 : 0)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct GlassPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.subheadline, design: .rounded, weight: .heavy))
            .frame(maxWidth: .infinity).padding(.vertical, 14)
            .buttonStyleBody(configuration: configuration, fill: .maeusCheese, foreground: .maeusInk)
    }
}

struct GlassSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.subheadline, design: .rounded, weight: .heavy))
            .frame(maxWidth: .infinity).padding(.vertical, 14)
            .buttonStyleBody(configuration: configuration, fill: .maeusSurface, foreground: .maeusForeground)
    }
}

private extension View {
    func buttonStyleBody(configuration: ButtonStyleConfiguration, fill: Color, foreground: Color) -> some View {
        self.foregroundStyle(foreground)
            .background {
                let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
                ZStack {
                    shape.fill(Color.maeusInk).offset(x: configuration.isPressed ? 1 : 3, y: configuration.isPressed ? 1 : 3)
                    shape.fill(fill)
                    shape.stroke(Color.maeusCardBorder, lineWidth: 2)
                }
            }
            .offset(x: configuration.isPressed ? 2 : 0, y: configuration.isPressed ? 2 : 0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct MouseCoin<Content: View>: View {
    var size: CGFloat
    var fill: Color = .maeusCheese
    var shadow: CGFloat = 0
    var wigglePeriod: Double = 5
    @ViewBuilder var content: () -> Content
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: wigglePeriod) / wigglePeriod
            let left = earAngle(t)
            let right = earAngle((t + 0.03).truncatingRemainder(dividingBy: 1))
            ZStack {
                ear(isLeft: true).rotationEffect(.degrees(left), anchor: .bottomTrailing)
                ear(isLeft: false).rotationEffect(.degrees(-right), anchor: .bottomLeading)

                if shadow > 0 {
                    Circle()
                        .fill(Color.maeusInk)
                        .frame(width: size, height: size)
                        .offset(x: shadow, y: shadow)
                }

                Circle().fill(fill)
                    .frame(width: size, height: size)
                    .overlay(Circle().stroke(Color.maeusInk, lineWidth: outlineWidth))

                content()
            }
            .frame(width: size, height: size)
        }
        .frame(width: size, height: size)
    }

    private func ear(isLeft: Bool) -> some View {
        let d = size * 0.36
        return Circle().fill(fill).overlay(Circle().stroke(Color.maeusInk, lineWidth: outlineWidth))
            .frame(width: d, height: d)
            .offset(x: (isLeft ? -1 : 1) * size * 0.37, y: -size * 0.44)
    }

    private var outlineWidth: CGFloat {
        if size >= 80 { return 3 }
        if size >= 50 { return 2.5 }
        return 2
    }

    private func earAngle(_ t: Double) -> Double {
        guard !reduceMotion, t > 0.86 && t < 0.98 else { return 0 }
        let p = (t - 0.86) / 0.12
        return sin(p * .pi * 4) * (1 - p) * 10
    }
}

struct FABStyle: ButtonStyle {
    var isPrimary = true
    func makeBody(configuration: Configuration) -> some View {
        let size: CGFloat = isPrimary ? 62 : 46
        return Group {
            if isPrimary {
                MouseCoin(size: size, shadow: 4) { configuration.label }
            } else {
                configuration.label.frame(width: size, height: size)
                    .background {
                        ZStack {
                            Circle().fill(Color.maeusInk).offset(x: 3, y: 3)
                            Circle().fill(Color.maeusSurface)
                            Circle().stroke(Color.maeusCardBorder, lineWidth: 2.5)
                        }
                    }
            }
        }
        .offset(x: configuration.isPressed ? 2 : 0, y: configuration.isPressed ? 2 : 0)
        .scaleEffect(configuration.isPressed ? 0.96 : 1)
        .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct FloatingCheeseHole: View {
    let size: CGFloat
    let duration: Double
    var delay: Double = 0
    var fill: Color = .maeusBackground
    var stroke: Color = .maeusCardBorder
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion)) { timeline in
            let phase = (timeline.date.timeIntervalSinceReferenceDate + delay).truncatingRemainder(dividingBy: duration) / duration
            Circle().fill(fill).overlay(Circle().stroke(stroke, lineWidth: 2.5))
                .frame(width: size, height: size)
                .offset(y: reduceMotion ? 0 : -5 * (0.5 - 0.5 * cos(phase * .pi * 2)))
        }
    }
}

// MARK: - Prototype-faithful line icons

struct MaeusePlusIcon: View {
    var body: some View {
        Canvas { context, size in
            var path = Path()
            path.move(to: CGPoint(x: size.width / 2, y: size.height * 0.21))
            path.addLine(to: CGPoint(x: size.width / 2, y: size.height * 0.79))
            path.move(to: CGPoint(x: size.width * 0.21, y: size.height / 2))
            path.addLine(to: CGPoint(x: size.width * 0.79, y: size.height / 2))
            context.stroke(path, with: .color(.maeusInk), style: StrokeStyle(lineWidth: 3, lineCap: .round))
        }.frame(width: 24, height: 24)
    }
}

struct MaeuseSettingsIcon: View {
    var body: some View {
        Canvas { context, size in
            let sx = size.width / 16, sy = size.height / 16
            var lines = Path()
            lines.move(to: CGPoint(x: 2*sx, y: 4.5*sy)); lines.addLine(to: CGPoint(x: 14*sx, y: 4.5*sy))
            lines.move(to: CGPoint(x: 2*sx, y: 11.5*sy)); lines.addLine(to: CGPoint(x: 14*sx, y: 11.5*sy))
            context.stroke(lines, with: .color(.maeusForeground), style: StrokeStyle(lineWidth: 1.8, lineCap: .round))
            for (x, y) in [(10.5, 4.5), (5.5, 11.5)] {
                let rect = CGRect(x: (x-2.2)*sx, y: (y-2.2)*sy, width: 4.4*sx, height: 4.4*sy)
                context.fill(Path(ellipseIn: rect), with: .color(.maeusSurface))
                context.stroke(Path(ellipseIn: rect), with: .color(.maeusForeground), lineWidth: 1.8)
            }
        }.frame(width: 16, height: 16)
    }
}

struct MaeuseChevronIcon: View {
    var pointsRight = true
    var body: some View {
        Canvas { context, size in
            let sx = size.width / 24, sy = size.height / 24
            var path = Path()
            if pointsRight {
                path.move(to: CGPoint(x: 10*sx, y: 7*sy))
                path.addLine(to: CGPoint(x: 15*sx, y: 12*sy))
                path.addLine(to: CGPoint(x: 10*sx, y: 17*sy))
            } else {
                path.move(to: CGPoint(x: 14*sx, y: 7*sy))
                path.addLine(to: CGPoint(x: 9*sx, y: 12*sy))
                path.addLine(to: CGPoint(x: 14*sx, y: 17*sy))
            }
            context.stroke(path, with: .color(.maeusInk), style: StrokeStyle(lineWidth: 2.8, lineCap: .round, lineJoin: .round))
        }.frame(width: 26, height: 26)
    }
}

struct MaeuseCloseIcon: View {
    var color: Color = .maeusForeground
    var body: some View {
        Canvas { context, size in
            var path = Path()
            path.move(to: CGPoint(x: 2, y: 2)); path.addLine(to: CGPoint(x: size.width-2, y: size.height-2))
            path.move(to: CGPoint(x: size.width-2, y: 2)); path.addLine(to: CGPoint(x: 2, y: size.height-2))
            context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: 2.4, lineCap: .round))
        }.frame(width: 14, height: 14)
    }
}

struct MaeuseCheckIcon: View {
    var body: some View {
        Canvas { context, size in
            var path = Path()
            path.move(to: CGPoint(x: 2.5, y: 8.5)); path.addLine(to: CGPoint(x: 6, y: 12)); path.addLine(to: CGPoint(x: 13.5, y: 4))
            context.stroke(path, with: .color(.maeusInk), style: StrokeStyle(lineWidth: 2.6, lineCap: .round, lineJoin: .round))
        }.frame(width: 16, height: 16)
    }
}

struct MaeuseMicIcon: View {
    var body: some View {
        Canvas { context, size in
            let sx = size.width / 24, sy = size.height / 24
            var path = Path(roundedRect: CGRect(x: 9*sx, y: 3*sy, width: 6*sx, height: 11*sy), cornerRadius: 3*sx)
            context.stroke(path, with: .color(.maeusForeground), style: StrokeStyle(lineWidth: 2.4, lineCap: .round))
            path = Path(); path.move(to: CGPoint(x: 5*sx, y: 11*sy)); path.addCurve(to: CGPoint(x: 19*sx, y: 11*sy), control1: CGPoint(x: 5*sx, y: 20*sy), control2: CGPoint(x: 19*sx, y: 20*sy))
            path.move(to: CGPoint(x: 12*sx, y: 18*sy)); path.addLine(to: CGPoint(x: 12*sx, y: 21*sy))
            context.stroke(path, with: .color(.maeusForeground), style: StrokeStyle(lineWidth: 2.4, lineCap: .round))
        }.frame(width: 18, height: 18)
    }
}

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0; Scanner(string: hex).scanHexInt64(&int)
        let r, g, b: UInt64
        if hex.count == 3 { (r, g, b) = ((int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17) }
        else { (r, g, b) = (int >> 16, int >> 8 & 0xFF, int & 0xFF) }
        self.init(.sRGB, red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255, opacity: 1)
    }

    init(light: Color, dark: Color) {
        self.init(UIColor { $0.userInterfaceStyle == .dark ? UIColor(dark) : UIColor(light) })
    }
}
