import Foundation

/// Persists a user-chosen save folder and resolves it on launch.
///
/// The folder is stored as a security-scoped bookmark so it survives relaunch
/// (and keeps working if the app is later sandboxed). If bookmark creation or
/// resolution fails we fall back to storing/reading a plain path string.
///
/// Each instance owns its own `UserDefaults` keys (derived from `keyPrefix`) and
/// its own `defaultFolder`, so several independent folders can coexist.
public final class SaveFolderStore {
    private let defaults: UserDefaults
    private let bookmarkKey: String
    private let pathKey: String
    private let creationOptions: URL.BookmarkCreationOptions
    private let resolutionOptions: URL.BookmarkResolutionOptions
    private var accessedURL: URL?

    /// Folder used when nothing valid is stored.
    public let defaultFolder: URL

    public init(
        defaults: UserDefaults = .standard,
        keyPrefix: String,
        defaultFolder: URL,
        securityScoped: Bool = true
    ) {
        self.defaults = defaults
        self.bookmarkKey = "\(keyPrefix)Bookmark"
        self.pathKey = "\(keyPrefix)Path"
        self.defaultFolder = defaultFolder
        self.creationOptions = securityScoped ? [.withSecurityScope] : []
        self.resolutionOptions = securityScoped ? [.withSecurityScope] : []
    }

    /// `~/Pictures/<appName>/`.
    public static func picturesSubfolder(appName: String) -> URL {
        let pictures = FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask)[0]
        return pictures.appendingPathComponent(appName, isDirectory: true)
    }

    /// Folder captures should be written to. Falls back to `defaultFolder` when
    /// nothing valid is stored. The directory is created if missing.
    public func resolvedFolder() -> URL {
        let folder = storedFolder() ?? defaultFolder
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    /// Records a new save folder chosen by the user.
    public func setFolder(_ url: URL) {
        stopAccessing()
        if let data = try? url.bookmarkData(
            options: creationOptions,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        ) {
            defaults.set(data, forKey: bookmarkKey)
        } else {
            defaults.removeObject(forKey: bookmarkKey)
        }
        defaults.set(url.path, forKey: pathKey)
    }

    /// Releases any security-scoped resource currently held.
    public func stopAccessing() {
        accessedURL?.stopAccessingSecurityScopedResource()
        accessedURL = nil
    }

    private func storedFolder() -> URL? {
        if let data = defaults.data(forKey: bookmarkKey) {
            var stale = false
            if let url = try? URL(
                resolvingBookmarkData: data,
                options: resolutionOptions,
                relativeTo: nil,
                bookmarkDataIsStale: &stale
            ) {
                if url.startAccessingSecurityScopedResource() {
                    accessedURL = url
                }
                if stale { setFolder(url) }
                return url
            }
        }
        if let path = defaults.string(forKey: pathKey) {
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        return nil
    }

    /// Round-trips a folder URL through bookmark data. Returns `nil` if the
    /// platform refuses to create or resolve the bookmark. Exposed for tests.
    public static func bookmarkRoundTrip(
        _ url: URL,
        options: URL.BookmarkCreationOptions = []
    ) -> URL? {
        guard let data = try? url.bookmarkData(
            options: options,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        ) else { return nil }
        var stale = false
        let resolution: URL.BookmarkResolutionOptions =
            options.contains(.withSecurityScope) ? [.withSecurityScope] : []
        return try? URL(
            resolvingBookmarkData: data,
            options: resolution,
            relativeTo: nil,
            bookmarkDataIsStale: &stale
        )
    }
}
