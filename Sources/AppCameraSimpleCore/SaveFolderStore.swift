import Foundation

/// Persists a user-chosen save folder and resolves it on launch.
///
/// The folder is kept as a plain path in `UserDefaults`, which is all an
/// unsandboxed app needs: the path stays valid across relaunches. Security-scoped
/// bookmarks were dropped on purpose — they only matter inside the App Sandbox,
/// which is not on the roadmap; see `docs/future-plans.md` before re-adding them.
///
/// Each instance owns its own `UserDefaults` key (derived from `keyPrefix`) and
/// its own `defaultFolder`, so several independent folders can coexist.
public final class SaveFolderStore {
    private let defaults: UserDefaults
    private let pathKey: String

    /// Folder used when nothing is stored.
    public let defaultFolder: URL

    public init(defaults: UserDefaults = .standard, keyPrefix: String, defaultFolder: URL) {
        self.defaults = defaults
        self.pathKey = "\(keyPrefix)Path"
        self.defaultFolder = defaultFolder
    }

    /// `~/Pictures/<appName>/`.
    public static func picturesSubfolder(appName: String) -> URL {
        FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(appName, isDirectory: true)
    }

    /// Folder captures should be written to, falling back to `defaultFolder`.
    /// The directory is created if missing.
    public func resolvedFolder() -> URL {
        let folder = defaults.string(forKey: pathKey)
            .map { URL(fileURLWithPath: $0, isDirectory: true) } ?? defaultFolder
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    /// Records a new save folder chosen by the user.
    public func setFolder(_ url: URL) {
        defaults.set(url.path, forKey: pathKey)
    }
}
