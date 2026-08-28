import Foundation

/// Display name, taken from the bundle when packaged as a .app.
let appName = (Bundle.main.infoDictionary?["CFBundleName"] as? String) ?? "AppCameraSimple"
