import Foundation
#if canImport(ObjectiveC)
import ObjectiveC
#endif

/// Separate files per process avoid interleaved writes between LC and embedded SideStore.
enum SigningDiagnostics {
    struct Entry: Codable, Identifiable {
        var id = UUID()
        var date = Date()
        let process: String
        let level: String
        let stage: String
        let detail: String
    }
    private static let lock = NSLock()
    private static let session = UUID().uuidString
    static var root: URL? {
        #if canImport(ObjectiveC)
        guard let type = NSClassFromString("LCSharedUtils"),
              let method = class_getClassMethod(type, NSSelectorFromString("appGroupPath")) else { return nil }
        typealias Getter = @convention(c) (AnyObject, Selector) -> Unmanaged<AnyObject>?
        let getter = unsafeBitCast(method_getImplementation(method), to: Getter.self)
        return (getter(type as AnyObject, NSSelectorFromString("appGroupPath"))?.takeUnretainedValue() as? URL)?
            .appendingPathComponent("LiveContainer/Diagnostics")
        #else
        return nil
        #endif
    }
    static var enabled: Bool { root.map { FileManager.default.fileExists(atPath: $0.appendingPathComponent("enabled").path) } ?? false }
    static func setEnabled(_ enabled: Bool) throws {
        guard let root else { throw SigningInjectionFailure.invalid("Shared diagnostic storage is unavailable") }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let marker = root.appendingPathComponent("enabled")
        if enabled { try Data().write(to: marker, options: .atomic) }
        else if FileManager.default.fileExists(atPath: marker.path) { try FileManager.default.removeItem(at: marker) }
    }
    static func redact(_ text: String) -> String {
        [#"(?i)(?:https?|file)://\S+"#,
         #"(?i)(?:authorization|cookie|set-cookie)\s*:[^\r\n]*"#,
         #"(?i)\bbearer\s+\S+"#,
         #"(?i)(?:token|api[_-]?key|password|secret|anisette)[\"']?\s*[=:]\s*[\"']?[^\s,}]+"#,
         #"[A-Z0-9a-z._%+-]+@[A-Z0-9a-z.-]+\.[A-Za-z]{2,}"#]
            .reduce(String(text.prefix(6000))) { $0.replacingOccurrences(of: $1, with: "[redacted]", options: .regularExpression) }
    }
    static func record(_ stage: String, _ detail: String = "", level: String = "info") {
        guard enabled, let root else { return }
        lock.lock(); defer { lock.unlock() }
        do {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            let url = root.appendingPathComponent("\(ProcessInfo.processInfo.processIdentifier)-\(session).jsonl")
            let entry = Entry(process: ProcessInfo.processInfo.processName, level: level, stage: stage, detail: redact(detail))
            var data = try JSONEncoder().encode(entry); data.append(10)
            if !FileManager.default.fileExists(atPath: url.path) { _ = FileManager.default.createFile(atPath: url.path, contents: nil) }
            let handle = try FileHandle(forWritingTo: url); defer { try? handle.close() }
            let size = try handle.seekToEnd()
            if size > 512 * 1024 {
                try handle.truncate(atOffset: 0); try handle.seek(toOffset: 0)
            }
            try handle.write(contentsOf: data)
            // Persist stage boundaries before native signing / installation can terminate the process.
            try handle.synchronize()
            let files = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: [.contentModificationDateKey])
                .filter { $0.pathExtension == "jsonl" }
                .sorted { ((try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast) >
                          ((try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast) }
            for old in files.dropFirst(8) { try? FileManager.default.removeItem(at: old) }
        } catch { /* Diagnostics must never break installation. */ }
    }
    static func failure(_ stage: String, _ error: Error) {
        var current: NSError? = error as NSError
        var parts: [String] = []
        for _ in 0..<6 {
            guard let value = current else { break }
            parts.append("\(value.domain) (\(value.code)): \(value.localizedDescription)")
            current = value.userInfo[NSUnderlyingErrorKey] as? NSError
        }
        record(stage, parts.joined(separator: "\nCaused by: "), level: "error")
    }
    static func entries() -> [Entry] {
        guard let root else { return [] }
        lock.lock(); defer { lock.unlock() }
        let files = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.pathExtension == "jsonl" }.flatMap { url -> [Entry] in
            guard let handle = try? FileHandle(forReadingFrom: url) else { return [] }
            defer { try? handle.close() }
            guard let data = try? handle.read(upToCount: 600_000) else { return [] }
            return data.split(separator: 10).compactMap { try? JSONDecoder().decode(Entry.self, from: Data($0)) }
        }.sorted { $0.date < $1.date }.suffix(1200).map { $0 }
    }
    static func clear() throws {
        guard let root else { return }
        lock.lock(); defer { lock.unlock() }
        for file in try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) where file.pathExtension == "jsonl" {
            try FileManager.default.removeItem(at: file)
        }
    }
}
