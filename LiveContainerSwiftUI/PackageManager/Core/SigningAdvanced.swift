import Foundation

enum SigningAdvanced {
    struct App {
        let url: URL
        let name: String
        let identifier: String
        let fileSharingEnabled: Bool
        let extensionCount: Int
    }

    /// Applied to a disposable copy of the IPA before SideStore signs it.
    /// Defaults preserve the IPA's original file-sharing setting and extensions.
    struct Options: Sendable {
        var enableFileSharing: Bool
        var removeAppExtensions: Bool = false
    }
    static func inspect(_ directory: URL) throws -> App {
        let apps = try FileManager.default.contentsOfDirectory(at: directory.appendingPathComponent("Payload"), includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "app" }
        guard apps.count == 1, let app = apps.first else { throw SigningInjectionFailure.invalid("IPA must contain exactly one application") }
        let plist = try read(app)
        guard let identifier = plist["CFBundleIdentifier"] as? String,
              let executable = plist["CFBundleExecutable"] as? String,
              !executable.isEmpty, !executable.contains("/"), !executable.contains(".."),
              FileManager.default.fileExists(atPath: app.appendingPathComponent(executable).path) else {
            throw SigningInjectionFailure.invalid("Missing application identifier or executable")
        }
        try SigningInjectionPreset.validateTarget(identifier)
        try SigningBundleIdentifiers.validateBundle(at: app)
        let plugins = app.appendingPathComponent("PlugIns", isDirectory: true)
        let extensions = (try? FileManager.default.contentsOfDirectory(
            at: plugins, includingPropertiesForKeys: [.isDirectoryKey])) ?? []
        let count = extensions.filter { $0.pathExtension == "appex" }.count
        return App(url: app,
                   name: plist["CFBundleDisplayName"] as? String ?? plist["CFBundleName"] as? String ?? identifier,
                   identifier: identifier,
                   fileSharingEnabled: plist["UIFileSharingEnabled"] as? Bool ?? false,
                   extensionCount: count)
    }
    static func customize(_ app: App, name: String, identifier: String, iconPNG: Data?,
                          options: Options? = nil) throws {
        try SigningInjectionPreset.validateTarget(identifier)
        let options = options ?? Options(enableFileSharing: app.fileSharingEnabled)
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, name.count <= 128 else {
            throw SigningInjectionFailure.invalid("Enter an application name of 1–128 characters")
        }
        let manager = FileManager.default
        let plugins = app.url.appendingPathComponent("PlugIns", isDirectory: true)
        let extensionURLs = ((try? manager.contentsOfDirectory(
            at: plugins, includingPropertiesForKeys: [.isDirectoryKey])) ?? [])
            .filter { $0.pathExtension == "appex" }
        // The package is copied to a staging directory before any modification.
        // Preserve embedded app metadata except inside removed extensions.
        var bundles = [app.url]
        if let enumerator = manager.enumerator(at: app.url, includingPropertiesForKeys: [.isDirectoryKey]) {
            for case let url as URL in enumerator where url.pathExtension == "appex" || url.pathExtension == "app" {
                if options.removeAppExtensions &&
                   extensionURLs.contains(where: { url.path == $0.path || url.path.hasPrefix($0.path + "/") }) {
                    continue
                }
                bundles.append(url)
            }
        }
        var changes: [(URL, [String: Any])] = []
        for bundle in bundles {
            var plist = try read(bundle)
            guard let old = plist["CFBundleIdentifier"] as? String,
                  old == app.identifier || old.hasPrefix(app.identifier + ".") else {
                throw SigningInjectionFailure.invalid("Embedded application has an unrelated bundle identifier")
            }
            func mapped(_ value: Any, key: String = "") -> Any {
                if let dictionary = value as? [String: Any] { return dictionary.reduce(into: [String: Any]()) { $0[$1.key] = mapped($1.value, key: $1.key) } }
                if let array = value as? [Any] { return array.map { mapped($0, key: key) } }
                if let text = value as? String,
                   ["CFBundleIdentifier", "WKCompanionAppBundleIdentifier", "WKAppBundleIdentifier", "NSExtensionContainingAppBundleIdentifier"].contains(key),
                   text == app.identifier || text.hasPrefix(app.identifier + ".") {
                    return identifier + text.dropFirst(app.identifier.count)
                }
                return value
            }
            guard let updated = mapped(plist) as? [String: Any] else { throw SigningInjectionFailure.invalid("Invalid application metadata") }
            plist = updated
            if bundle == app.url {
                plist["CFBundleDisplayName"] = name; plist["CFBundleName"] = name
                plist["UIFileSharingEnabled"] = options.enableFileSharing
                if options.enableFileSharing {
                    // Also expose Documents in the Files app; this alone cannot
                    // grant access to a sandbox outside the app's Documents folder.
                    plist["LSSupportsOpeningDocumentsInPlace"] = true
                }
                if iconPNG != nil {
                    let primary: [String: Any] = ["CFBundleIconFiles": ["LCOSCustomIcon"], "UIPrerenderedIcon": false]
                    plist["CFBundleIcons"] = ["CFBundlePrimaryIcon": primary]
                    plist["CFBundleIcons~ipad"] = ["CFBundlePrimaryIcon": primary]
                    plist["CFBundleIconFiles"] = ["LCOSCustomIcon"]
                    plist.removeValue(forKey: "CFBundleIconName")
                }
            }
            changes.append((bundle, plist))
        }
        if let iconPNG {
            try iconPNG.write(to: app.url.appendingPathComponent("LCOSCustomIcon.png"), options: .atomic)
            try iconPNG.write(to: app.url.appendingPathComponent("LCOSCustomIcon@2x.png"), options: .atomic)
            try iconPNG.write(to: app.url.appendingPathComponent("LCOSCustomIcon@3x.png"), options: .atomic)
        }
        for (bundle, plist) in changes {
            try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
                .write(to: bundle.appendingPathComponent("Info.plist"), options: .atomic)
            let signature = bundle.appendingPathComponent("_CodeSignature")
            if manager.fileExists(atPath: signature.path) { try manager.removeItem(at: signature) }
        }
        if options.removeAppExtensions {
            // Remove only the selected top-level .appex bundles. Other resources,
            // frameworks and watch apps remain intact. SideStore will derive
            // provisioning profiles from this *prepared* IPA.
            for extensionURL in extensionURLs {
                try manager.removeItem(at: extensionURL)
            }
        }
        try SigningBundleIdentifiers.validateBundle(at: app.url)
    }
    private static func read(_ app: URL) throws -> [String: Any] {
        guard let value = try PropertyListSerialization.propertyList(from: Data(contentsOf: app.appendingPathComponent("Info.plist")), format: nil) as? [String: Any] else {
            throw SigningInjectionFailure.invalid("Unreadable Info.plist")
        }
        return value
    }
}
