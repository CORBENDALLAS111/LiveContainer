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
struct LCShortcutProfile: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Automation"
    static var defaultQuery = LCShortcutProfileQuery()
    var id: String
    var name: String
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }
}
@available(iOS 16.0, *)
struct LCShortcutProfileQuery: EntityStringQuery {
    func suggestedEntities() async throws -> [LCShortcutProfile] {
        (LCShortcutCatalog.read()["profiles"] as? [[String: Any]] ?? []).compactMap {
            guard let id = $0["id"] as? String, let name = $0["name"] as? String else { return nil }
            return LCShortcutProfile(id: id, name: name)
        }
    }
    func entities(for identifiers: [String]) async throws -> [LCShortcutProfile] {
        try await suggestedEntities().filter { identifiers.contains($0.id) }
    }
    func entities(matching string: String) async throws -> [LCShortcutProfile] {
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
        guard await UIApplication.shared.open(try LCShortcutCatalog.url(app: app.id)) else { throw LCShortcutError.unavailable }
        return .result()
    }
}
@available(iOS 16.0, *)
struct LCRunAutomationIntent: AppIntent {
    static var title: LocalizedStringResource = "Run container automation"
    static var description = IntentDescription("Run a saved foreground scenario. Enable scenarios in LiveContainer Settings first.")
    @Parameter(title: "Automation") var automation: LCShortcutProfile
    static var openAppWhenRun: Bool = true
    static var parameterSummary: some ParameterSummary { Summary("Run \(\.$automation)") }
    @MainActor func perform() async throws -> some IntentResult {
        let catalog = LCShortcutCatalog.read()
        guard catalog["enabled"] as? Bool == true,
              let profile = (catalog["profiles"] as? [[String: Any]])?.first(where: { $0["id"] as? String == automation.id }),
              let app = profile["app"] as? String else { throw LCShortcutError.unavailable }
        guard await UIApplication.shared.open(try LCShortcutCatalog.url(app: app, profile: automation.id)) else { throw LCShortcutError.unavailable }
        return .result()
    }
}
@available(iOS 16.0, *)
enum LCShortcutError: Error, CustomLocalizedStringResourceConvertible {
    case unavailable
    var localizedStringResource: LocalizedStringResource { "Enable automations in LiveContainer Settings and check that the scenario still exists." }
}
@available(iOS 16.0, *)
struct LCOSAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: LCLaunchGuestIntent(), phrases: ["Launch an app in \(.applicationName)"], shortTitle: "Launch App", systemImageName: "app.badge")
        AppShortcut(intent: LCRunAutomationIntent(), phrases: ["Run an automation in \(.applicationName)"], shortTitle: "Run Automation", systemImageName: "play.rectangle")
    }
}
