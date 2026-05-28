import Foundation

/// Single shared `UserDefaults` instance bound explicitly to `com.qalamai.app`.
///
/// `UserDefaults.standard` isn't reliably bound to the bundle's preferences
/// domain when the app is launched outside LaunchServices (which our ad-hoc
/// signed @main entry can do). Using an explicit suite name guarantees every
/// read/write hits `~/Library/Preferences/com.qalamai.app.plist` consistently.
enum QalamDefaults {
    // UserDefaults is documented to be thread-safe (KVO + atomic plist writes).
    // Mark the global as unsafe so Swift 6 strict concurrency lets us share it.
    nonisolated(unsafe) static let suite: UserDefaults =
        UserDefaults(suiteName: Constants.bundleID) ?? .standard
}
