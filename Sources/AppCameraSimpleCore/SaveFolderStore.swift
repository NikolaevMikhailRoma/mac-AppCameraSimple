import Foundation

/// A user-chosen save folder, kept as a plain path. That suffices outside the
/// App Sandbox; inside it, security-scoped bookmarks would be needed (the earlier
/// implementation is in git history).
public final class SaveFolderStore {
    private let defaults: UserDefaults
    private let pathKey: String

    public let defaultFolder: URL

    public init(defaults: UserDefaults = .standard, keyPrefix: String, defaultFolder: URL) {
        self.defaults = defaults
        self.pathKey = "\(keyPrefix)Path"
        self.defaultFolder = defaultFolder
    }

    public static func picturesSubfolder(appName: String) -> URL {
        FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(appName, isDirectory: true)
    }

    /// Created if missing.
    public func resolvedFolder() -> URL {
        let folder = defaults.string(forKey: pathKey)
            .map { URL(fileURLWithPath: $0, isDirectory: true) } ?? defaultFolder
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    public func setFolder(_ url: URL) {
        defaults.set(url.path, forKey: pathKey)
    }
}
