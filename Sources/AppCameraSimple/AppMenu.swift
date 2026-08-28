import AppKit

/// Builds the app's main menu. Kept tiny: just an app menu (Settings, Quit).
@MainActor
func buildMainMenu(target: AppDelegate) -> NSMenu {
    let mainMenu = NSMenu()

    let appMenuItem = NSMenuItem()
    mainMenu.addItem(appMenuItem)
    let appMenu = NSMenu()
    let settings = NSMenuItem(
        title: "Settings…",
        action: #selector(AppDelegate.showSettings),
        keyEquivalent: ","
    )
    settings.target = target
    appMenu.addItem(settings)
    appMenu.addItem(.separator())
    appMenu.addItem(
        withTitle: "Quit \(appName)",
        action: #selector(NSApplication.terminate(_:)),
        keyEquivalent: "q"
    )
    appMenuItem.submenu = appMenu

    return mainMenu
}
