import AppIntents
import Foundation

/// Destinations that Lock Screen / Control Center controls can request.
enum CaptureLaunchDestination: String, Codable, Sendable, AppEnum {
    case addExpense
    case dictateExpense

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Mäuse")
    static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .addExpense: DisplayRepresentation(title: "ControlAddExpenseTitle"),
        .dictateExpense: DisplayRepresentation(title: "ControlDictateExpenseTitle")
    ]
}

/// Stores the destination selected by an `OpenIntent` while the main app opens.
enum CaptureLaunchRouter {
    static let pendingKey = "maeuse.pending-capture-launch"
    static let urlScheme = "maeuse"

    /// A cross-process handoff URL for WidgetKit extensions, whose standard
    /// UserDefaults container is separate from the main app's container.
    static func url(for destination: CaptureLaunchDestination) -> URL {
        URL(string: "\(urlScheme)://capture/\(destination.rawValue)")!
    }

    static func destination(from url: URL) -> CaptureLaunchDestination? {
        guard url.scheme == urlScheme, url.host == "capture" else { return nil }
        return CaptureLaunchDestination(rawValue: url.lastPathComponent)
    }

    static func setPending(_ destination: CaptureLaunchDestination) {
        UserDefaults.standard.set(destination.rawValue, forKey: pendingKey)
    }

    /// Returns and clears any pending destination.
    static func consumePending() -> CaptureLaunchDestination? {
        guard let raw = UserDefaults.standard.string(forKey: pendingKey) else { return nil }
        UserDefaults.standard.removeObject(forKey: pendingKey)
        return CaptureLaunchDestination(rawValue: raw)
    }

    /// Peeks without clearing — used while onboarding is still visible.
    static func peekPending() -> CaptureLaunchDestination? {
        guard let raw = UserDefaults.standard.string(forKey: pendingKey) else { return nil }
        return CaptureLaunchDestination(rawValue: raw)
    }
}
