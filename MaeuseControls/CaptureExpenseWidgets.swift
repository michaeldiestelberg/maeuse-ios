import SwiftUI
import WidgetKit

private struct CaptureExpenseEntry: TimelineEntry {
    let date: Date
}

private struct CaptureExpenseProvider: TimelineProvider {
    func placeholder(in context: Context) -> CaptureExpenseEntry {
        CaptureExpenseEntry(date: .now)
    }

    func getSnapshot(in context: Context, completion: @escaping (CaptureExpenseEntry) -> Void) {
        completion(CaptureExpenseEntry(date: .now))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<CaptureExpenseEntry>) -> Void) {
        // These launcher widgets have no changing data, so one entry is enough.
        completion(Timeline(entries: [CaptureExpenseEntry(date: .now)], policy: .never))
    }
}

/// Home Screen and Lock Screen widget for manual expense entry.
struct AddExpenseWidget: Widget {
    static let kind = "com.michaeldiestelberg.maeuse.widget.addExpense"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: CaptureExpenseProvider()) { _ in
            CaptureExpenseWidgetView(target: .addExpense)
        }
        .configurationDisplayName(LocalizedStringResource("WidgetAddExpenseTitle"))
        .description(LocalizedStringResource("WidgetAddExpenseDescription"))
        .supportedFamilies([.systemSmall, .accessoryCircular, .accessoryRectangular, .accessoryInline])
        .contentMarginsDisabled()
    }
}

/// Home Screen and Lock Screen widget for Voice Mode capture.
struct DictateExpenseWidget: Widget {
    static let kind = "com.michaeldiestelberg.maeuse.widget.dictateExpense"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: CaptureExpenseProvider()) { _ in
            CaptureExpenseWidgetView(target: .dictateExpense)
        }
        .configurationDisplayName(LocalizedStringResource("WidgetDictateExpenseTitle"))
        .description(LocalizedStringResource("WidgetDictateExpenseDescription"))
        .supportedFamilies([.systemSmall, .accessoryCircular, .accessoryRectangular, .accessoryInline])
        .contentMarginsDisabled()
    }
}

private struct CaptureExpenseWidgetView: View {
    @Environment(\.widgetFamily) private var family

    let target: CaptureLaunchDestination

    private let cheese = Color(red: 1.00, green: 0.81, blue: 0.25)
    private let cream = Color(red: 1.00, green: 0.96, blue: 0.87)
    private let ink = Color(red: 0.14, green: 0.11, blue: 0.02)

    private var title: LocalizedStringResource {
        switch target {
        case .addExpense: "WidgetAddExpenseTitle"
        case .dictateExpense: "WidgetDictateExpenseTitle"
        }
    }

    private var prompt: LocalizedStringResource {
        switch target {
        case .addExpense: "WidgetAddExpensePrompt"
        case .dictateExpense: "WidgetDictateExpensePrompt"
        }
    }

    private var symbolName: String {
        switch target {
        case .addExpense: "mouse.plus"
        case .dictateExpense: "mouse.mic"
        }
    }

    var body: some View {
        Link(destination: CaptureLaunchRouter.url(for: target)) {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .containerBackground(for: .widget) {
            widgetBackground
        }
        .accessibilityLabel(Text(title))
        .accessibilityHint(Text(prompt))
    }

    @ViewBuilder
    private var content: some View {
        switch family {
        case .accessoryCircular:
            Image(symbolName)
                .resizable()
                .scaledToFit()
                .padding(11)
                .widgetAccentable()

        case .accessoryRectangular:
            HStack(spacing: 8) {
                Image(symbolName)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 28, height: 28)
                    .widgetAccentable()

                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.headline)
                        .lineLimit(1)
                    Text(prompt)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 2)

        case .accessoryInline:
            HStack(spacing: 4) {
                Image(symbolName)
                Text(title)
            }

        default:
            homeScreenWidget
        }
    }

    private var homeScreenWidget: some View {
        ZStack {
            CheeseHole(size: 29, fill: cream, ink: ink)
                .offset(x: 64, y: -44)
            CheeseHole(size: 13, fill: cream, ink: ink)
                .offset(x: 45, y: -12)
            CheeseHole(size: 23, fill: cream, ink: ink)
                .offset(x: 52, y: 58)

            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(ink, lineWidth: 2.5)
                .padding(4)

            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top) {
                    MouseActionCoin(target: target, fill: cream, ink: ink)
                    Spacer(minLength: 0)
                }

                Spacer(minLength: 6)

                Text(title)
                    .font(.system(size: 17, weight: .black, design: .rounded))
                    .foregroundStyle(ink)
                    .lineLimit(2)
                    .minimumScaleFactor(0.82)
                    .multilineTextAlignment(.leading)
            }
            .padding(14)
        }
        .background(cheese)
    }

    @ViewBuilder
    private var widgetBackground: some View {
        if family == .systemSmall {
            cheese
        } else {
            Color.clear
        }
    }
}

private struct MouseActionCoin: View {
    let target: CaptureLaunchDestination
    let fill: Color
    let ink: Color

    private var systemName: String {
        switch target {
        case .addExpense: "plus"
        case .dictateExpense: "mic.fill"
        }
    }

    var body: some View {
        ZStack {
            ear(x: -20)
            ear(x: 20)

            Circle()
                .fill(ink)
                .frame(width: 54, height: 54)
                .offset(x: 4, y: 4)

            Circle()
                .fill(fill)
                .frame(width: 54, height: 54)
                .overlay(Circle().stroke(ink, lineWidth: 2.5))

            Image(systemName: systemName)
                .font(.system(size: 25, weight: .black, design: .rounded))
                .foregroundStyle(ink)
        }
        .frame(width: 62, height: 62)
    }

    private func ear(x: CGFloat) -> some View {
        Circle()
            .fill(fill)
            .frame(width: 22, height: 22)
            .overlay(Circle().stroke(ink, lineWidth: 2.5))
            .offset(x: x, y: -24)
    }
}

private struct CheeseHole: View {
    let size: CGFloat
    let fill: Color
    let ink: Color

    var body: some View {
        Circle()
            .fill(fill)
            .frame(width: size, height: size)
            .overlay(Circle().stroke(ink, lineWidth: 2))
    }
}
