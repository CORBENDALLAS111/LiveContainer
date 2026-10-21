import Foundation
import XCTest
@testable import PackageCore

final class TweakRepositoryTests: XCTestCase {
    func testIndexAndDownloadedChecksum() throws {
        let repo = try TweakRepository.validated("https://example.org/repo/")
        let bytes = Data("test deb payload".utf8)
        let index = "Package: org.example.tweak\nName: Example\nVersion: 1.0\nArchitecture: iphoneos-arm64\nFilename: debs/example.deb\nSize: \(bytes.count)\nSHA256: \(PackageSHA256.hex(bytes))\nDescription: App tweak\n continuation\n"
        let packages = try TweakRepositoryIndex.parse(Data(index.utf8), repository: repo)
        XCTAssertEqual(packages.count, 1)
        XCTAssertEqual(packages[0].download.absoluteString, "https://example.org/repo/debs/example.deb")
        try packages[0].verify(bytes)
        XCTAssertThrowsError(try packages[0].verify(Data("tampered".utf8)))
        let outside = index.replacingOccurrences(of: "debs/example.deb", with: "https://evil.example/app.deb")
        XCTAssertTrue(try TweakRepositoryIndex.parse(Data(outside.utf8), repository: repo).isEmpty)
        let traversal = index.replacingOccurrences(of: "debs/example.deb", with: "../example.deb")
        XCTAssertTrue(try TweakRepositoryIndex.parse(Data(traversal.utf8), repository: repo).isEmpty)
        XCTAssertThrowsError(try TweakRepository.validated("http://example.org/"))
        XCTAssertThrowsError(try TweakRepository.validated("https://user:password@example.org/"))
    }
}
