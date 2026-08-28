import AppKit

/// Directory-only open panel used to choose a save folder.
@MainActor
enum FolderPicker {
    /// Presents the panel. `completion` runs only when the user picks a folder.
    static func present(startingAt current: URL?,
                        message: String,
                        completion: @escaping (URL) -> Void) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        panel.message = message
        if let current { panel.directoryURL = current }
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            completion(url)
        }
    }
}
