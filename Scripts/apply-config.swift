import Foundation

// Reads app.json and writes CFBundleName/CFBundleExecutable/CFBundleShortVersionString/
// CFBundleIdentifier into an Info.plist. Usage: swift apply-config.swift <app.json> <Info.plist>

let args = CommandLine.arguments
guard args.count == 3 else {
    FileHandle.standardError.write("usage: apply-config.swift <app.json> <Info.plist>\n".data(using: .utf8)!)
    exit(1)
}

let configURL = URL(fileURLWithPath: args[1])
let plistURL = URL(fileURLWithPath: args[2])

let configData = try Data(contentsOf: configURL)
guard let config = try JSONSerialization.jsonObject(with: configData) as? [String: String],
      let name = config["name"], let version = config["version"], let bundleID = config["bundleIdentifier"] else {
    FileHandle.standardError.write("app.json must have string fields: name, version, bundleIdentifier\n".data(using: .utf8)!)
    exit(1)
}

let plistData = try Data(contentsOf: plistURL)
var format = PropertyListSerialization.PropertyListFormat.xml
guard var plist = try PropertyListSerialization.propertyList(from: plistData, options: [], format: &format) as? [String: Any] else {
    FileHandle.standardError.write("could not read Info.plist as a dictionary\n".data(using: .utf8)!)
    exit(1)
}

plist["CFBundleName"] = name
plist["CFBundleExecutable"] = name
plist["CFBundleShortVersionString"] = version
plist["CFBundleIdentifier"] = bundleID

let outData = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
try outData.write(to: plistURL)

print("Applied \(name) v\(version) (\(bundleID)) to \(plistURL.lastPathComponent)")
