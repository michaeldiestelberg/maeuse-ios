import Foundation

/// Destinations that Lock Screen / Control Center controls can request.
enum CaptureLaunchDestination: String, Codable, Sendable {
    case addExpense
    case dictateExpense
}

/// Stores a pending capture launch so Controls (extension process) can hand off
/// to the main app after unlock.
enum CaptureLaunchRouter {
    static let appGroupID = "group.com.michaeldiestelberg.maeuse"
    static let pendingKey = "maeuse.pending-capture-launch"

    private static var defaults: UserDefaults {
        UserDefaults(suiteName: appGroupID) ?? .standard
    }

    static func setPending(_ destination: CaptureLaunchDestination) {
        defaults.set(destination.rawValue, forKey: pendingKey)
    }

    /// Returns and clears any pending destination.
    static func consumePending() -> CaptureLaunchDestination? {
        guard let raw = defaults.string(forKey: pendingKey) else { return nil }
        defaults.removeObject(forKey: pendingKey)
        return CaptureLaunchDestination(rawValue: raw)
    }

    /// Peeks without clearing — used while onboarding is still visible.
    static func peekPending() -> CaptureLaunchDestination? {
        guard let raw = defaults.string(forKey: pendingKey) else { return nil }
        return CaptureLaunchDestination(rawValue: raw)
    }
}
