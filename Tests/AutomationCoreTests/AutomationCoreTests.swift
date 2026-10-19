import Foundation
import XCTest
@testable import AutomationCore

final class AutomationCoreTests: XCTestCase {
    func testSavedScenarioRoundTripAndURLIsolation() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("profiles.json")
        let profile = LCAutomation(name: "Мой сценарий", app: "A & B.app", steps: [.init(kind: .button, target: "Continue")])
        var file = LCAutomationFile(); file.enabled = true; file.profiles = [profile]
        try file.save(to: url)
        XCTAssertEqual(LCAutomationFile.load(from: url).profiles, [profile])
        let components = try XCTUnwrap(URLComponents(url: XCTUnwrap(profile.launchURL(scheme: "livecontainer2")), resolvingAgainstBaseURL: false))
        XCTAssertEqual(components.scheme, "livecontainer2")
        XCTAssertEqual(components.queryItems?.first?.value, "A & B.app")
        XCTAssertEqual(components.queryItems?.count, 2)
    }
    func testRejectsInvalidAndUnboundedSteps() {
        var profile = LCAutomation(name: "Test", app: "Test.app")
        XCTAssertTrue(profile.isValid)
        profile.steps[0].seconds = .nan; XCTAssertFalse(profile.isValid)
        profile.steps[0].seconds = 61; XCTAssertFalse(profile.isValid)
        profile.steps = Array(repeating: .init(seconds: 60), count: 6); XCTAssertFalse(profile.isValid)
        profile.steps = [.init(kind: .button, target: "  ")]; XCTAssertFalse(profile.isValid)
        profile.steps = [.init(kind: .point, x: 1.1)]; XCTAssertFalse(profile.isValid)
        profile.steps = [.init()]; profile.app = "../Test.app"; XCTAssertFalse(profile.isValid)
    }
    func testInvalidSaveDoesNotOverwriteExistingFile() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        let original = Data("original".utf8); try original.write(to: url)
        var file = LCAutomationFile(); file.profiles = [.init()]
        XCTAssertThrowsError(try file.save(to: url))
        XCTAssertEqual(try Data(contentsOf: url), original)
        XCTAssertFalse(LCAutomationFile.load(from: url).enabled)
    }
    func testRejectsDuplicateProfileIDs() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let profile = LCAutomation(name: "Test", app: "Test.app")
        var file = LCAutomationFile(); file.profiles = [profile, profile]
        XCTAssertThrowsError(try file.save(to: url))
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }
}
