import Foundation
import AppIntents
import UIKit

// Compiled into the main executable so Shortcuts discovers metadata without loading a guest.
@available(iOS 16.0, *)
private enum LCShortcutCatalog {
    static func read() -> [String: Any] {
        let home = getenv("LC_HOME_PATH").map { String(cString: $0) } ?? NSHomeDirectory()
        let url = URL(fileURLWithPath: home).appendingPathComponent("Documents/LCOSAutomations.json")
        guard let data = try? Data(contentsOf: url), data.count <= 512_000,
              let value = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              value["version"] as? Int == 1 else { return [:] }
        return value
    }
    static func url(app: String, profile: String? = nil) throws -> URL {
        guard !app.isEmpty, app == (app as NSString).lastPathComponent else { throw CocoaError(.fileReadCorruptFile) }
        var components = URLComponents()
        components.scheme = read()["scheme"] as? String ?? "livecontainer"
        components.host = "livecontainer-launch"
        components.queryItems = [.init(name: "bundle-name", value: app)]
        if let profile { components.queryItems?.append(.init(name: "automation", value: profile)) }
        guard let url = components.url else { throw CocoaError(.fileReadCorruptFile) }
        return url
    }
}

@available(iOS 16.0, *)
struct LCShortcutApp: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Container app"
    static var defaultQuery = LCShortcutAppQuery()
    var id: String
    var name: String
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }
}
@available(iOS 16.0, *)
struct LCShortcutAppQuery: EntityStringQuery {
    func suggestedEntities() async throws -> [LCShortcutApp] {
        (LCShortcutCatalog.read()["apps"] as? [[String: Any]] ?? []).compactMap {
            guard let id = $0["id"] as? String, let name = $0["name"] as? String else { return nil }
            return LCShortcutApp(id: id, name: name)
        }
    }
    func entities(for identifiers: [String]) async throws -> [LCShortcutApp] {
        try await suggestedEntities().filter { identifiers.contains($0.id) }
    }
    func entities(matching string: String) async throws -> [LCShortcutApp] {
        try await suggestedEntities().filter { $0.name.localizedCaseInsensitiveContains(string) }
    }
}
@available(iOS 16.0, *)
struct LCLaunchGuestIntent: AppIntent {
    static var title: LocalizedStringResource = "Launch container app"
    static var description = IntentDescription("Launch an installed LiveContainer app using its usual authentication and JIT settings.")
    @Parameter(title: "App") var app: LCShortcutApp
    static var openAppWhenRun: Bool = true
    static var parameterSummary: some ParameterSummary { Summary("Launch \(\.$app)") }
    @MainActor func perform() async throws -> some IntentResult {
        guard await UIApplication.shared.open(try LCShortcutCatalog.url(app: app.id)) else { throw LCShortcutError.cannotOpen }
        return .result()
    }
}
@available(iOS 16.0, *)
enum LCShortcutError: Error, CustomLocalizedStringResourceConvertible {
    case cannotOpen
    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .cannotOpen: "LiveContainer could not open the launch link. Open the app once and try again."
        }
    }
}
@available(iOS 16.0, *)
struct LCOSAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: LCLaunchGuestIntent(), phrases: ["Launch an app in \(.applicationName)"], shortTitle: "Launch App", systemImageName: "app.badge")
    }
}
