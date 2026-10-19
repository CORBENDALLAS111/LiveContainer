import Foundation
import XCTest
import LCArchiveBridge
@testable import PackageCore

final class AdvancedInstallTests: XCTestCase {
    private func fixture() throws -> (URL, SigningAdvanced.App) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let app = root.appendingPathComponent("Payload/Test.app")
        let ext = app.appendingPathComponent("PlugIns/Widget.appex")
        try FileManager.default.createDirectory(at: ext, withIntermediateDirectories: true)
        for (url, id) in [(app, "org.example.test"), (ext, "org.example.test.widget")] {
            let plist: [String: Any] = ["CFBundleIdentifier": id, "CFBundleExecutable": "Test", "CFBundleDisplayName": "Original"]
            try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0).write(to: url.appendingPathComponent("Info.plist"))
        }
        try Data([1, 2, 3]).write(to: app.appendingPathComponent("Test"))
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: app.appendingPathComponent("Test").path)
        return (root, try SigningAdvanced.inspect(root))
    }
    func testCustomParentRewritesExtensionAndPreservesOriginal() throws {
        let (root, app) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        try SigningAdvanced.customize(app, name: "New name", identifier: "org.example.clone", iconPNG: Data([137,80,78,71]))
        let updated = try SigningAdvanced.inspect(root)
        XCTAssertEqual(updated.name, "New name")
        XCTAssertEqual(updated.identifier, "org.example.clone")
        let data = try Data(contentsOf: app.url.appendingPathComponent("PlugIns/Widget.appex/Info.plist"))
        let plist = try XCTUnwrap(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
        XCTAssertEqual(plist["CFBundleIdentifier"] as? String, "org.example.clone.widget")
        XCTAssertEqual(try Data(contentsOf: app.url.appendingPathComponent("Test")), Data([1,2,3]))
    }
    func testStreamingIPARoundTripAndLinkRejection() throws {
        let (root, app) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let output = root.deletingLastPathComponent().appendingPathComponent(UUID().uuidString + ".ipa")
        defer { try? FileManager.default.removeItem(at: output) }
        var error = [CChar](repeating: 0, count: 1024)
        XCTAssertEqual(lc_ipa_pack(root.path, output.path, &error, error.count), 0, String(cString: error))
        let destination = root.appendingPathComponent("RoundTrip")
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        XCTAssertEqual(lc_ipa_extract(output.path, destination.path, &error, error.count), 0, String(cString: error))
        XCTAssertEqual(try SigningAdvanced.inspect(destination).identifier, app.identifier)
        let permissions = try FileManager.default.attributesOfItem(atPath: destination.appendingPathComponent("Payload/Test.app/Test").path)[.posixPermissions] as? NSNumber
        XCTAssertEqual(permissions?.intValue, 0o755)
        try FileManager.default.createSymbolicLink(atPath: root.appendingPathComponent("escape").path, withDestinationPath: "/etc/passwd")
        XCTAssertNotEqual(lc_ipa_pack(root.path, output.path, &error, error.count), 0)
    }
    func testInvalidIdentityRejectedBeforeMutation() throws {
        let (root, app) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        XCTAssertThrowsError(try SigningAdvanced.customize(app, name: "", identifier: "org.example.clone", iconPNG: nil))
        XCTAssertThrowsError(try SigningAdvanced.customize(app, name: "Clone", identifier: "../../escape", iconPNG: nil))
        XCTAssertEqual(try SigningAdvanced.inspect(root).identifier, "org.example.test")
    }
    func testDiagnosticsRedactsSecretsAndLimitsUntrustedText() {
        let message = SigningDiagnostics.redact("password=secret token=credential user@example.com https://example.com/?key=x")
        XCTAssertFalse(message.contains("secret")); XCTAssertFalse(message.contains("credential"))
        XCTAssertFalse(message.contains("user@example.com")); XCTAssertFalse(message.contains("example.com"))
        XCTAssertLessThanOrEqual(SigningDiagnostics.redact(String(repeating: "x", count: 10_000)).count, 6000)
    }
    func testMaliciousZIPPathsLinksAndDuplicatesAreRejected() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        for name in ["ipa-traversal", "ipa-symlink", "ipa-duplicate"] {
            let source = try XCTUnwrap(Bundle.module.url(forResource: name, withExtension: "zip", subdirectory: "Fixtures"))
            let destination = root.appendingPathComponent(name)
            try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
            var error = [CChar](repeating: 0, count: 1024)
            XCTAssertNotEqual(lc_ipa_extract(source.path, destination.path, &error, error.count), 0, name)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("escape").path))
    }
}
