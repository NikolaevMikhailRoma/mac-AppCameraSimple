import AppKit

/// Builds the app's main menu. Kept tiny: just an app menu (Settings, Quit).
@MainActor
func buildMainMenu(target: AppDelegate) -> NSMenu {
    let appMenu = NSMenu()
    let settings = appMenu.addItem(
        withTitle: "Settings\u{2026}",
        action: #selector(AppDelegate.showSettings),
        keyEquivalent: ","
    )
    settings.target = target
    appMenu.addItem(.separator())
    appMenu.addItem(
        withTitle: "Quit \(appName)",
        action: #selector(NSApplication.terminate(_:)),
        keyEquivalent: "q"
    )

    let appMenuItem = NSMenuItem()
    appMenuItem.submenu = appMenu

    let mainMenu = NSMenu()
    mainMenu.addItem(appMenuItem)
    return mainMenu
}
