import Foundation

/// A fresh, empty `UserDefaults` suite, so tests never see each other's writes
/// or the app's real preferences.
func makeDefaults() -> UserDefaults {
    let suite = "AppCameraSimpleTests-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    return defaults
}
