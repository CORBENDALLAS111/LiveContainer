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
    func testFileSharingActuallyUpdatesAppMetadata() throws {
        let (root, app) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        XCTAssertFalse(app.fileSharingEnabled)
        XCTAssertEqual(app.extensionCount, 1)
        try SigningAdvanced.customize(app, name: app.name, identifier: app.identifier, iconPNG: nil,
                                      options: .init(enableFileSharing: true))
        let updated = try SigningAdvanced.inspect(root)
        XCTAssertTrue(updated.fileSharingEnabled)
        XCTAssertEqual(updated.extensionCount, 1)
        let plist = try XCTUnwrap(PropertyListSerialization.propertyList(
            from: Data(contentsOf: updated.url.appendingPathComponent("Info.plist")),
            format: nil) as? [String: Any])
        XCTAssertEqual(plist["UIFileSharingEnabled"] as? Bool, true)
        XCTAssertEqual(plist["LSSupportsOpeningDocumentsInPlace"] as? Bool, true)
    }

    func testRemoveAppExtensionsRetainsExecutableAndAppIdentity() throws {
        let (root, app) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let executable = try Data(contentsOf: app.url.appendingPathComponent("Test"))
        try SigningAdvanced.customize(app, name: "Clone", identifier: "org.example.clone", iconPNG: nil,
                                      options: .init(enableFileSharing: false, removeAppExtensions: true))
        let updated = try SigningAdvanced.inspect(root)
        XCTAssertEqual(updated.identifier, "org.example.clone")
        XCTAssertEqual(updated.name, "Clone")
        XCTAssertEqual(updated.extensionCount, 0)
        XCTAssertFalse(updated.fileSharingEnabled)
        XCTAssertFalse(FileManager.default.fileExists(atPath: app.url.appendingPathComponent("PlugIns/Widget.appex").path))
        XCTAssertEqual(try Data(contentsOf: app.url.appendingPathComponent("Test")), executable)
    }

    func testDefaultsKeepAppExtensionsAndOriginalFileSharing() throws {
        let (root, app) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        try SigningAdvanced.customize(app, name: "Normal", identifier: app.identifier, iconPNG: nil)
        let updated = try SigningAdvanced.inspect(root)
        XCTAssertEqual(updated.extensionCount, 1)
        XCTAssertFalse(updated.fileSharingEnabled)
    }

    func testSelectivelyRemoveOneExtensionAndPreserveAnother() throws {
        let (root, app) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let other = app.url.appendingPathComponent("PlugIns/Share.appex")
        try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)
        let plist: [String: Any] = [
            "CFBundleIdentifier": "org.example.test.share",
            "CFBundleExecutable": "Share",
            "CFBundleDisplayName": "Share Extension",
            "NSExtension": ["NSExtensionPointIdentifier": "com.apple.share-services"]
        ]
        try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            .write(to: other.appendingPathComponent("Info.plist"))
        let inspected = try SigningAdvanced.inspect(root)
        XCTAssertEqual(inspected.extensionCount, 2)
        XCTAssertEqual(Set(inspected.extensions.map(\.id)), ["Widget.appex", "Share.appex"])
        XCTAssertEqual(inspected.extensions.first { $0.id == "Share.appex" }?.extensionPoint,
                       "com.apple.share-services")
        try SigningAdvanced.customize(inspected, name: "Clone", identifier: "org.example.clone",
            iconPNG: nil, options: .init(enableFileSharing: false,
                                         excludedExtensionNames: ["Widget.appex"]))
        let result = try SigningAdvanced.inspect(root)
        XCTAssertEqual(result.extensionCount, 1)
        XCTAssertEqual(result.extensions.first?.id, "Share.appex")
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: app.url.appendingPathComponent("PlugIns/Widget.appex").path))
        XCTAssertEqual(result.extensions.first?.bundleIdentifier, "org.example.clone.share")
    }

    func testUnknownExtensionChoiceDoesNotChangeIPA() throws {
        let (root, app) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        XCTAssertThrowsError(try SigningAdvanced.customize(app, name: "Clone",
            identifier: "org.example.clone", iconPNG: nil,
            options: .init(enableFileSharing: false,
                           excludedExtensionNames: ["../Unknown.appex"])))
        XCTAssertEqual(try SigningAdvanced.inspect(root).identifier, app.identifier)
        XCTAssertEqual(try SigningAdvanced.inspect(root).extensionCount, 1)
    }

    func testIncreasedMemoryOptInCreatesValidatedSigningRequest() throws {
        let (root, app) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        XCTAssertFalse(try SigningIncreasedMemory.requested(
            in: app.url, bundleIdentifier: app.identifier))
        try SigningAdvanced.customize(app, name: "More RAM",
            identifier: "org.example.clone", iconPNG: nil,
            options: .init(enableFileSharing: false, increasedMemoryLimit: true))
        let edited = try SigningAdvanced.inspect(root)
        XCTAssertTrue(try SigningIncreasedMemory.requested(
            in: edited.url, bundleIdentifier: "org.example.clone"))
        XCTAssertThrowsError(try SigningIncreasedMemory.requested(
            in: edited.url, bundleIdentifier: "org.example.other"))
        XCTAssertEqual(try Data(contentsOf: edited.url.appendingPathComponent("Test")),
                       Data([1, 2, 3]))
    }

    func testDisabledMemoryOptionRemovesAnOldMarker() throws {
        let (root, app) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        try SigningIncreasedMemory.writeRequest(in: app.url,
                                               bundleIdentifier: app.identifier)
        XCTAssertTrue(try SigningIncreasedMemory.requested(
            in: app.url, bundleIdentifier: app.identifier))
        try SigningAdvanced.customize(app, name: "Normal",
            identifier: app.identifier, iconPNG: nil,
            options: .init(enableFileSharing: false))
        XCTAssertFalse(try SigningIncreasedMemory.requested(
            in: app.url, bundleIdentifier: app.identifier))
    }

    func testMalformedMemoryRequestFailsClosed() throws {
        let (root, app) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let path = app.url.appendingPathComponent(SigningIncreasedMemory.fileName)
        try Data("invalid".utf8).write(to: path)
        XCTAssertThrowsError(try SigningIncreasedMemory.requested(
            in: app.url, bundleIdentifier: app.identifier))
    }

    func testStreamingIPARoundTripAndLinkRejection() throws {
        let (root, app) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let output = root.deletingLastPathComponent().appendingPathComponent(UUID().uuidString + ".ipa")
        defer { try? FileManager.default.removeItem(at: output) }
        var error = [CChar](repeating: 0, count: 1024)
        XCTAssertEqual(lc_ipa_pack(root.path, output.path, &error, error.count), 0, String(cString: error))
        let destination = root.appendingPathComponent("RoundTrip")
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let alias = root.appendingPathComponent("DestinationAlias")
        try FileManager.default.createSymbolicLink(atPath: alias.path, withDestinationPath: destination.path)
        XCTAssertEqual(lc_ipa_extract(output.path, alias.path, &error, error.count), 0, String(cString: error))
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
