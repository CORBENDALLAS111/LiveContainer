import SwiftUI
import UniformTypeIdentifiers

@MainActor
enum LifeBuiltInJIT {
    private static var active: [NSExtension] = []
    private static var tokens: [UUID: Task<Void, Never>] = [:]
    nonisolated static var pairingURL: URL { URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Documents/LifeJIT/pairing.plist") }
    static func validatePairing(_ data: Data) throws {
        guard data.count > 0, data.count <= 1_048_576,
              (try? PropertyListSerialization.propertyList(from: data, format: nil)) is [String: Any] else {
            throw PackageFailure.invalid("life.jit.invalidPairing".loc)
        }
    }
    static func send(pid: Int? = nil, script: String? = nil, log: @escaping (String) -> Void) throws {
        #if targetEnvironment(simulator)
        throw PackageFailure.invalid("life.jit.deviceOnly".loc)
        #else
        guard #available(iOS 26.0, *) else { throw PackageFailure.invalid("life.jit.requires26".loc) }
        guard let bundle = Bundle(path: Bundle.main.bundlePath + "/PlugIns/LifeJITHelper.appex"),
              let identifier = bundle.bundleIdentifier else { throw PackageFailure.invalid("life.jit.missingHelper".loc) }
        let pairing = try Data(contentsOf: pairingURL); try validatePairing(pairing)
        let helper = try NSExtension(identifier: identifier)
        let token = UUID()
        active.append(helper)
        let cleanup = {
            Self.tokens.removeValue(forKey: token)?.cancel()
            Self.active.removeAll { $0 === helper }
        }
        helper.setRequestCancellationBlock { _, error in Task { @MainActor in cleanup(); log(error?.localizedDescription ?? "life.jit.stopped".loc) } }
        helper.setRequestInterruptionBlock { _ in Task { @MainActor in cleanup(); log("life.jit.stopped".loc) } }
        // Completion is public only on the private NSExtension interface used by LiveProcess.
        helper.setRequestCompletionBlock { _, items in
            let message = (items?.first as? NSExtensionItem)?.userInfo?["message"] as? String
            Task { @MainActor in cleanup(); log(message ?? "life.jit.stopped".loc) }
        }
        let item = NSExtensionItem()
        var info: [String: Any] = ["operation": pid == nil ? "prepare" : "enable", "pairing": pairing]
        if let pid { info["pid"] = NSNumber(value: pid); info["script"] = script ?? "" }
        item.userInfo = info
        log("life.jit.starting".loc)
        Task { @MainActor in
            _ = await helper.beginRequest(withInputItems: [item])
            log(pid == nil ? "life.jit.preparing".loc : "life.jit.attaching".loc)
        }
        tokens[token] = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 300_000_000_000)
            guard !Task.isCancelled else { return }
            helper._kill(9); cleanup(); log("life.jit.timeout".loc)
        }
        #endif
    }
}

struct LifeJITSettingsView: View {
    @State private var importing = false
    @State private var paired = false
    @State private var messages = ""
    @State private var error = ""
    var body: some View {
        Form {
            Section {
                Label("life.jit.title".loc, systemImage: "bolt.fill").font(.title2.bold())
                Text("life.jit.explanation".loc).font(.subheadline).foregroundStyle(.secondary)
            }
            Section {
                Label(paired ? "life.jit.paired".loc : "life.jit.notPaired".loc, systemImage: paired ? "checkmark.seal.fill" : "key")
                Button("life.jit.import".loc) { importing = true }
                Link("life.jit.pairingGuide".loc, destination: URL(string: "https://github.com/StikDebug/StikDebug-Guide/blob/main/pairing_file.md")!)
                Link("LocalDevVPN", destination: URL(string: "https://apps.apple.com/app/localdevvpn/id6755608044")!)
                Button("life.jit.check".loc) {
                    do { try LifeBuiltInJIT.send { messages += $0 + "\n" } }
                    catch { self.error = error.localizedDescription }
                }.disabled(!paired)
                if paired {
                    Button("life.jit.removePairing".loc, role: .destructive) {
                        do { try FileManager.default.removeItem(at: LifeBuiltInJIT.pairingURL); paired = false }
                        catch { self.error = error.localizedDescription }
                    }
                }
            } header: { Text("life.jit.setup".loc) } footer: { Text("life.jit.requirements".loc) }
            if !messages.isEmpty { Section("life.jit.log".loc) { Text(messages).font(.caption.monospaced()).textSelection(.enabled) } }
        }.navigationTitle("life.jit.title".loc)
        .onAppear { paired = FileManager.default.fileExists(atPath: LifeBuiltInJIT.pairingURL.path) }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.propertyList, .data]) { result in
            do {
                let url = try result.get(), access = url.startAccessingSecurityScopedResource()
                defer { if access { url.stopAccessingSecurityScopedResource() } }
                let handle = try FileHandle(forReadingFrom: url); defer { try? handle.close() }
                let data = try handle.read(upToCount: 1_048_577) ?? Data(); try LifeBuiltInJIT.validatePairing(data)
                try FileManager.default.createDirectory(at: LifeBuiltInJIT.pairingURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                try data.write(to: LifeBuiltInJIT.pairingURL, options: [.atomic, .completeFileProtection])
                LCUtils.appGroupUserDefault.set(JITEnablerType.builtIn.rawValue, forKey: "LCJITEnablerType")
                paired = true
            } catch { self.error = error.localizedDescription }
        }
        .alert("lc.common.error".loc, isPresented: Binding(get: { !error.isEmpty }, set: { if !$0 { error = "" } })) {
            Button("lc.common.ok".loc) { error = "" }
        } message: { Text(error) }
    }
}
