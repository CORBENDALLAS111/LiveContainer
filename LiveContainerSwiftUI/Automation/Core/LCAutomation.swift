import Foundation

struct LCAutomationStep: Codable, Identifiable, Equatable {
    enum Kind: String, Codable, CaseIterable { case wait, button, point }
    var id = UUID()
    var kind: Kind = .wait
    var seconds: Double = 1
    var target = ""
    var x: Double = 0.5
    var y: Double = 0.5
}

struct LCAutomation: Codable, Identifiable, Equatable {
    var id = UUID()
    var name = ""
    var app = ""
    var steps: [LCAutomationStep] = [.init()]

    var isValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && name.count <= 100 &&
        !app.isEmpty && app == (app as NSString).lastPathComponent && app.hasSuffix(".app") &&
        !steps.isEmpty && steps.count <= 60 && steps.reduce(0, { $0 + $1.seconds }) <= 300 &&
        steps.allSatisfy { step in
            step.seconds.isFinite && (0.2...60).contains(step.seconds) &&
            (step.kind != .button || !step.target.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) &&
            step.target.count <= 256 && step.x.isFinite && step.y.isFinite &&
            (0...1).contains(step.x) && (0...1).contains(step.y)
        }
    }

    func launchURL(scheme: String) -> URL? {
        guard isValid else { return nil }
        var url = URLComponents()
        url.scheme = scheme; url.host = "livecontainer-launch"
        url.queryItems = [.init(name: "bundle-name", value: app), .init(name: "automation", value: id.uuidString)]
        return url.url
    }
}

struct LCAutomationFile: Codable {
    var version = 1
    var enabled = false
    var scheme = "livecontainer"
    var apps: [App] = []
    var profiles: [LCAutomation] = []
    struct App: Codable { var id: String; var name: String }

    static var url: URL {
        let home = getenv("LC_HOME_PATH").map { String(cString: $0) } ?? NSHomeDirectory()
        return URL(fileURLWithPath: home).appendingPathComponent("Documents/LCOSAutomations.json")
    }
    static func load(from url: URL = LCAutomationFile.url) -> Self {
        guard let data = try? Data(contentsOf: url), data.count <= 512_000,
              let value = try? JSONDecoder().decode(Self.self, from: data), value.version == 1 else { return Self() }
        return value
    }
    func save(to url: URL = LCAutomationFile.url) throws {
        guard version == 1, profiles.count <= 100, profiles.allSatisfy(\.isValid),
              Set(profiles.map(\.id)).count == profiles.count else { throw CocoaError(.fileWriteInvalidFileName) }
        let data = try JSONEncoder().encode(self)
        guard data.count <= 512_000 else { throw CocoaError(.fileWriteOutOfSpace) }
        try data.write(to: url, options: .atomic)
    }
}
