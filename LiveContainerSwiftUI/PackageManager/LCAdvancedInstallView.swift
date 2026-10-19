import SwiftUI
import UniformTypeIdentifiers
import ImageIO

/// All editing runs in the host. Embedded SideStore only receives the finished IPA and signs it.
struct LCAdvancedInstallView: View {
    let installInContainer: (URL) -> Void
    let installWithSideStore: (URL) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var importing = false
    @State private var importingIcon = false
    @State private var working = false
    @State private var status = ""
    @State private var app: SigningAdvanced.App?
    @State private var workspace: URL?
    @State private var name = ""
    @State private var identifier = ""
    @State private var icon: Data?
    @State private var failure: String?
    @State private var destination = 0
    @State private var injecting = false
    @State private var retained = false
    private var ready: Bool { app != nil && !working && !name.isEmpty && !identifier.isEmpty }
    var body: some View {
        NavigationView {
            Form {
                Section {
                    Button { importing = true } label: { Label("lc.appList.installFromIpa".loc, systemImage: "doc.badge.plus") }.disabled(working)
                    if let app { Text(app.identifier).font(.caption).foregroundStyle(.secondary).textSelection(.enabled) }
                }
                if app != nil {
                    Section("lcos.install.identity".loc) {
                        TextField("lcos.install.name".loc, text: $name)
                        TextField("Bundle ID", text: $identifier).textInputAutocapitalization(.never).disableAutocorrection(true)
                        Button { importingIcon = true } label: {
                            HStack {
                                Label("lcos.install.icon".loc, systemImage: "photo")
                                Spacer()
                                if let icon, let image = UIImage(data: icon) {
                                    Image(uiImage: image).resizable().scaledToFit().frame(width: 44, height: 44).clipShape(RoundedRectangle(cornerRadius: 10))
                                }
                            }
                        }
                        if icon != nil { Button("lcos.install.originalIcon".loc) { icon = nil } }
                    }.disabled(working)
                    Section {
                        Button { injecting = true } label: { Label("lcos.signing.title".loc, systemImage: "syringe") }
                            .disabled(working || (try? SigningInjectionPreset.validateTarget(identifier)) == nil)
                    } footer: { Text("lcos.install.injectionDescription".loc) }
                    Section {
                        Picker("lcos.install.destination".loc, selection: $destination) {
                            Text("LiveContainer").tag(0)
                            if UserDefaults.sideStoreExist() { Text("SideStore").tag(1) }
                        }
                        Button("lcos.install.start".loc) { Task { await prepare() } }.disabled(!ready)
                    } footer: { Text("lcos.install.description".loc) }
                }
                if working { HStack { ProgressView(); Text(status).font(.callout) } }
            }.lcSoftScrollEdges()
                .navigationTitle("lcos.install.advanced".loc)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("lc.common.cancel".loc) { dismiss() }.disabled(working) } }
        }.navigationViewStyle(.stack)
        .interactiveDismissDisabled(working)
        .fileImporter(isPresented: $importing, allowedContentTypes: [.data], allowsMultipleSelection: false) { result in
            do { if let url = try result.get().first { Task { await load(url) } } } catch { failure = error.localizedDescription }
        }
        .fileImporter(isPresented: $importingIcon, allowedContentTypes: [.image], allowsMultipleSelection: false) { result in
            do {
                guard let url = try result.get().first else { return }
                let scoped = url.startAccessingSecurityScopedResource(); defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? Int.max
                guard size <= 20 * 1024 * 1024, let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                      let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                        kCGImageSourceCreateThumbnailFromImageAlways: true,
                        kCGImageSourceCreateThumbnailWithTransform: true,
                        kCGImageSourceThumbnailMaxPixelSize: 180
                      ] as CFDictionary) else {
                    throw SigningInjectionFailure.invalid("Choose an image smaller than 20 MB")
                }
                let image = UIImage(cgImage: thumbnail)
                let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = true
                icon = UIGraphicsImageRenderer(size: CGSize(width: 180, height: 180), format: format).pngData { _ in
                    image.draw(in: CGRect(x: 0, y: 0, width: 180, height: 180))
                }
            } catch { failure = error.localizedDescription }
        }
        .sheet(isPresented: $injecting) {
            NavigationView { LCSigningInjectionView(target: identifier, appName: name) { _ in injecting = false } }.navigationViewStyle(.stack)
        }
        .alert("lc.common.error".loc, isPresented: Binding(get: { failure != nil }, set: { if !$0 { failure = nil } })) {
            Button("lc.common.ok".loc) { failure = nil }
        } message: { Text(failure ?? "") }
        .onDisappear { if !retained, let workspace { try? FileManager.default.removeItem(at: workspace) } }
    }
    private func load(_ source: URL) async {
        working = true; status = "lcos.install.inspect".loc; defer { working = false }
        let scoped = source.startAccessingSecurityScopedResource(); defer { if scoped { source.stopAccessingSecurityScopedResource() } }
        do {
            guard ["ipa", "tipa"].contains(source.pathExtension.lowercased()),
                  (try source.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? Int.max) <= 2 * 1024 * 1024 * 1024 else {
                throw SigningInjectionFailure.invalid("Choose an IPA smaller than 2 GB")
            }
            guard let group = LCSharedUtils.appGroupPath() else { throw SigningInjectionFailure.invalid("Shared app group unavailable") }
            let directory = group.appendingPathComponent("LiveContainer/AdvancedInstall/" + UUID().uuidString)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            SigningDiagnostics.record("advanced.extract.begin", source.lastPathComponent)
            do {
                let inspected = try await Task.detached(priority: .userInitiated) {
                    // Retain successful handoffs for retries; clean abandoned jobs after a week.
                    let parent = directory.deletingLastPathComponent()
                    let old = (try? FileManager.default.contentsOfDirectory(at: parent, includingPropertiesForKeys: [.creationDateKey, .isDirectoryKey])) ?? []
                    for item in old where UUID(uuidString: item.lastPathComponent) != nil && item != directory {
                        if let values = try? item.resourceValues(forKeys: [.creationDateKey, .isDirectoryKey]),
                           values.isDirectory == true, let date = values.creationDate, date.timeIntervalSinceNow < -604800 {
                            try? FileManager.default.removeItem(at: item)
                        }
                    }
                    var error = [CChar](repeating: 0, count: 1024)
                    guard lc_ipa_extract(source.path, directory.path, &error, error.count) == 0 else {
                        throw SigningInjectionFailure.invalid(String(cString: error))
                    }
                    return try SigningAdvanced.inspect(directory)
                }.value
                if let workspace { try? FileManager.default.removeItem(at: workspace) }
                workspace = directory; app = inspected; name = inspected.name; identifier = inspected.identifier; icon = nil
                SigningDiagnostics.record("advanced.extract.end", inspected.identifier)
            } catch { try? FileManager.default.removeItem(at: directory); throw error }
        } catch { SigningDiagnostics.failure("advanced.extract.failed", error); failure = error.localizedDescription }
    }
    private func prepare() async {
        guard app != nil, let workspace else { return }
        working = true; status = "lcos.install.prepare".loc; defer { working = false }
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let identifier = identifier.trimmingCharacters(in: .whitespacesAndNewlines)
        let icon = icon
        do {
            guard let group = LCSharedUtils.appGroupPath() else { throw SigningInjectionFailure.invalid("Shared app group unavailable") }
            let root = group.appendingPathComponent("LiveContainer/SigningInjection")
            let output = workspace.appendingPathComponent("Prepared.ipa")
            let staging = workspace.appendingPathComponent("Edited")
            try await Task.detached(priority: .userInitiated) {
                SigningDiagnostics.record("advanced.prepare.begin", identifier)
                if FileManager.default.fileExists(atPath: staging.path) { try FileManager.default.removeItem(at: staging) }
                try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
                try FileManager.default.copyItem(at: workspace.appendingPathComponent("Payload"), to: staging.appendingPathComponent("Payload"))
                let copy = try SigningAdvanced.inspect(staging)
                try SigningAdvanced.customize(copy, name: name, identifier: identifier, iconPNG: icon)
                try SigningInjectionApply.prepare(app: copy.url, identifier: identifier, root: root)
                var error = [CChar](repeating: 0, count: 1024)
                guard lc_ipa_pack(staging.path, output.path, &error, error.count) == 0 else {
                    throw SigningInjectionFailure.invalid(String(cString: error))
                }
                try FileManager.default.removeItem(at: staging)
                SigningDiagnostics.record("advanced.prepare.end", "IPA ready for signing")
            }.value
            retained = true
            dismiss()
            // The owner starts installation after SwiftUI dismisses this sheet.
            if destination == 1 { installWithSideStore(output) } else { installInContainer(output) }
        } catch { SigningDiagnostics.failure("advanced.prepare.failed", error); failure = error.localizedDescription }
    }
}
