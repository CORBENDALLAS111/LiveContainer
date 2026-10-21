import Foundation
#if canImport(LCArchiveBridge)
import LCArchiveBridge
#endif

struct TweakRepository: Codable, Identifiable, Equatable {
    var id: String { url.absoluteString }
    let url: URL
    static func validated(_ text: String) throws -> Self {
        guard var url = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines)),
              url.scheme == "https", url.host != nil, url.user == nil, url.password == nil,
              url.query == nil, url.fragment == nil else { throw PackageFailure.invalid("Use an HTTPS repository URL without credentials or query parameters.") }
        if !url.absoluteString.hasSuffix("/") { url.appendPathComponent("") }
        return Self(url: url)
    }
}

struct TweakRepositoryPackage: Identifiable, Hashable {
    var id: String { download.absoluteString + "#" + version }
    let identifier: String
    let name: String
    let version: String
    let summary: String
    let architecture: String
    let section: String
    let download: URL
    let sha256: String
    let size: Int
    let source: String

    func verify(_ data: Data) throws {
        guard data.count == size, PackageSHA256.hex(data) == sha256 else {
            throw PackageFailure.invalid("Downloaded package does not match the repository checksum or size.")
        }
    }
}

enum TweakRepositoryIndex {
    static func parse(_ input: Data, repository: TweakRepository) throws -> [TweakRepositoryPackage] {
        guard input.count <= 16 * 1024 * 1024 else { throw PackageFailure.invalid("Repository index exceeds the download limit.") }
        let data: Data
        if input.starts(with: [0x1f, 0x8b]) || input.starts(with: [0xfd, 0x37, 0x7a]) || input.starts(with: [0x42, 0x5a, 0x68]) {
            var output = Data(count: 32 * 1024 * 1024)
            let count = input.withUnsafeBytes { bytes in output.withUnsafeMutableBytes { buffer in
                lc_index_expand(bytes.baseAddress, input.count, buffer.baseAddress, buffer.count)
            } }
            guard count >= 0 else { throw PackageFailure.invalid("Unsupported or oversized compressed repository index.") }
            data = output.prefix(Int(count))
        } else { data = input }
        guard let text = String(data: data, encoding: .utf8) else { throw PackageFailure.invalid("Repository metadata is not UTF-8.") }
        let stanzas = text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n\n")
        guard stanzas.count <= 50_000 else { throw PackageFailure.invalid("Repository has too many packages.") }
        var seen = Set<String>()
        return stanzas.compactMap { stanza in
            guard let control = try? DebianControl(Data(stanza.utf8)),
                  ["iphoneos-arm64", "iphoneos-arm", "all"].contains(control["architecture"]),
                  let size = Int(control["size"]), size > 0, size <= PackageLimits().archiveBytes,
                  control["sha256"].range(of: "^[A-Fa-f0-9]{64}$", options: .regularExpression) != nil,
                  !control["filename"].isEmpty,
                  let download = URL(string: control["filename"], relativeTo: repository.url)?.absoluteURL.standardized,
                  download.scheme == "https", download.host == repository.url.host,
                  download.user == nil, download.password == nil,
                  download.path.hasPrefix(repository.url.path), download.pathExtension == "deb" else { return nil }
            let key = download.absoluteString + "#" + control["version"]
            guard seen.insert(key).inserted else { return nil }
            return TweakRepositoryPackage(identifier: control["package"], name: control["name"].isEmpty ? control["package"] : control["name"],
                version: control["version"], summary: String(control["description"].prefix(600)),
                architecture: control["architecture"], section: control["section"], download: download,
                sha256: control["sha256"].lowercased(), size: size, source: repository.url.absoluteString)
        }
    }
}
