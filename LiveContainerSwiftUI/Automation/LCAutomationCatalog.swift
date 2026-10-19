import Foundation

enum LCAutomationCatalog {
    static func refresh(_ apps: [LCAppModel]) {
        var file = LCAutomationFile.load()
        file.scheme = LCUtils.appUrlScheme() ?? "livecontainer"
        file.apps = apps.filter { !$0.uiIsLocked && !$0.appInfo.isHidden }.compactMap {
            guard let id = $0.appInfo.relativeBundlePath else { return nil }
            return .init(id: id, name: $0.displayName)
        }
        do { try file.save() } catch { NSLog("[LCOS] Automation catalog: %@", error.localizedDescription) }
    }
}
