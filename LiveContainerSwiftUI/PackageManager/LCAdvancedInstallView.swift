import SwiftUI
import UniformTypeIdentifiers
import ImageIO

/// Only presented by the embedded SideStore; the shared module supplies the editor implementation.
struct LCAdvancedInstallView: View {
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
    @State private var ipaFilename = ""
    @State private var enableFileSharing = false
    @State private var excludedExtensions: Set<String> = []
    @State private var managingExtensions = false
    @State private var icon: Data?
    @State private var failure: String?
    @State private var injecting = false
    @State private var retained = false
    private var ready: Bool { app != nil && !working && !name.isEmpty && !identifier.isEmpty }
    var body: some View {
        NavigationView {
            Form {
                if let app {
                    appSummary(app)
                    appOptions(app)
                    identitySection
                    injectionSection
                } else {
                    chooseIPASection
                }
                if working { progressSection }
            }
            .lcSoftScrollEdges()
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if app != nil { installBar }
            }
            .navigationTitle("lcos.install.advanced".installLoc)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("lc.common.cancel".installLoc, action: cancel)
                        .disabled(working)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if app != nil {
                        Button("lcos.install.changeIPA".installLoc) { importing = true }
                            .disabled(working)
                    }
                }
            }
        }
        .navigationViewStyle(.stack)
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
                    let scale = max(180 / image.size.width, 180 / image.size.height)
                    let width = image.size.width * scale, height = image.size.height * scale
                    image.draw(in: CGRect(x: (180 - width) / 2, y: (180 - height) / 2, width: width, height: height))
                }
            } catch { failure = error.localizedDescription }
        }
        .sheet(isPresented: $managingExtensions) {
            if let app { extensionManager(app) }
        }
        .sheet(isPresented: $injecting) {
            NavigationView { LCSigningInjectionView(target: identifier, appName: name) { _ in injecting = false } }.navigationViewStyle(.stack)
        }
        .alert("lc.common.error".installLoc, isPresented: Binding(get: { failure != nil }, set: { if !$0 { failure = nil } })) {
            Button("lc.common.ok".installLoc) { failure = nil }
        } message: { Text(failure ?? "") }
    }
    private func cancel() {
        if !retained, let workspace {
            try? FileManager.default.removeItem(at: workspace)
        }
        dismiss()
    }

    private func appSummary(_ app: SigningAdvanced.App) -> some View {
        Section {
            HStack(spacing: 14) {
                appArtwork
                VStack(alignment: .leading, spacing: 4) {
                    Text(ipaFilename).font(.headline).lineLimit(2)
                    Text(app.name).font(.subheadline).foregroundStyle(.secondary)
                    Label("SideStore", systemImage: "iphone")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, 6)
            .accessibilityElement(children: .combine)
        } footer: {
            Text("lcos.install.sidestoreDescription".installLoc)
        }
    }

    @ViewBuilder
    private var appArtwork: some View {
        Group {
            if let icon, let image = UIImage(data: icon) {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Image(systemName: "app.fill")
                    .font(.title)
                    .foregroundStyle(.tint)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(width: 60, height: 60)
        .background(Color(uiColor: .tertiarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func appOptions(_ app: SigningAdvanced.App) -> some View {
        Section {
            Toggle(isOn: $enableFileSharing) {
                Label("lcos.install.fileSharing".installLoc, systemImage: "folder")
            }
            if app.extensionCount > 0 {
                Button { managingExtensions = true } label: {
                    HStack(spacing: 12) {
                        Label("lcos.install.manageExtensions".installLoc,
                              systemImage: "puzzlepiece.extension")
                        Spacer()
                        Text("\(app.extensionCount - excludedExtensions.count)/\(app.extensionCount)")
                            .foregroundStyle(.secondary).monospacedDigit()
                        Image(systemName: "chevron.right")
                            .font(.footnote).foregroundStyle(.tertiary)
                    }
                    .contentShape(Rectangle())
                }
                if !excludedExtensions.isEmpty {
                    Label("lcos.install.extensionWarning".installLoc,
                          systemImage: "exclamationmark.triangle")
                        .font(.footnote).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        } header: {
            Text("lcos.install.options".installLoc)
        } footer: {
            Text("lcos.install.fileSharingHelp".installLoc)
        }
        .disabled(working)
    }

    /// Retains every extension by default. Only selected omissions are removed
    /// from the disposable staging IPA before the SideStore signing flow begins.
    private func extensionManager(_ app: SigningAdvanced.App) -> some View {
        NavigationView {
            Form {
                Section {
                    ForEach(app.extensions) { item in
                        Toggle(isOn: Binding(
                            get: { !excludedExtensions.contains(item.id) },
                            set: { retained in
                                if retained { excludedExtensions.remove(item.id) }
                                else { excludedExtensions.insert(item.id) }
                            }
                        )) {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(item.title).font(.body.weight(.medium))
                                Text(item.bundleIdentifier)
                                    .font(.caption).foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                                if !item.extensionPoint.isEmpty {
                                    Text(item.extensionPoint)
                                        .font(.caption2).foregroundStyle(.tertiary)
                                }
                            }
                        }
                        .disabled(working)
                    }
                } header: {
                    Text("lcos.install.manageExtensions".installLoc)
                } footer: {
                    Text("lcos.install.extensionWarning".installLoc)
                }
                Section {
                    Button("lcos.install.keepAllExtensions".installLoc) {
                        excludedExtensions.removeAll()
                    }
                    .disabled(excludedExtensions.isEmpty || working)
                }
            }
            .navigationTitle("lcos.install.manageExtensions".installLoc)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("lcos.home.done".installLoc) { managingExtensions = false }
                }
            }
        }.navigationViewStyle(.stack)
    }

    private var identitySection: some View {
        Section("lcos.install.identity".installLoc) {
            VStack(alignment: .leading, spacing: 6) {
                Text("lcos.install.name".installLoc)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                TextField("lcos.install.name".installLoc, text: $name)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("Bundle ID")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                TextField("Bundle ID", text: $identifier)
                    .textInputAutocapitalization(.never)
                    .disableAutocorrection(true)
                    .font(.system(.body, design: .monospaced))
            }
            Button { importingIcon = true } label: {
                HStack {
                    Label("lcos.install.icon".installLoc, systemImage: "photo")
                    Spacer()
                    if icon != nil {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    }
                }
            }
            if icon != nil {
                Button("lcos.install.originalIcon".installLoc) { icon = nil }
            }
        }
        .disabled(working)
    }

    private var injectionSection: some View {
        Section {
            Button { injecting = true } label: {
                HStack {
                    Label("lcos.install.injection".installLoc, systemImage: "square.stack.3d.up")
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .disabled(working || (try? SigningInjectionPreset.validateTarget(identifier)) == nil)
        } footer: {
            Text("lcos.install.injectionDescription".installLoc)
        }
    }

    private var chooseIPASection: some View {
        Section {
            Button { importing = true } label: {
                Label("lc.appList.installFromIpa".installLoc, systemImage: "doc.badge.plus")
                    .frame(minHeight: 44)
            }
            .disabled(working)
        } footer: {
            Text("lcos.install.chooseIPADescription".installLoc)
        }
    }

    private var progressSection: some View {
        Section {
            HStack(spacing: 12) {
                ProgressView()
                Text(status).foregroundStyle(.secondary)
            }
        }
    }

    private var installBar: some View {
        Button {
            Task { await prepare() }
        } label: {
            HStack(spacing: 10) {
                if working {
                    ProgressView().tint(.white)
                } else {
                    Image(systemName: "checkmark.shield")
                }
                Text("lcos.install.start".installLoc).font(.headline)
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: 44)
        }
        .buttonStyle(.borderedProminent)
        .disabled(!ready)
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(.regularMaterial)
    }

    private func load(_ source: URL) async {
        working = true; status = "lcos.install.inspect".installLoc; defer { working = false }
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
                workspace = directory; app = inspected; name = inspected.name; identifier = inspected.identifier
                ipaFilename = source.lastPathComponent; icon = nil
                enableFileSharing = inspected.fileSharingEnabled; excludedExtensions.removeAll()
                SigningDiagnostics.record("advanced.extract.end", inspected.identifier)
            } catch { try? FileManager.default.removeItem(at: directory); throw error }
        } catch { SigningDiagnostics.failure("advanced.extract.failed", error); failure = error.localizedDescription }
    }
    private func prepare() async {
        guard app != nil, let workspace else { return }
        working = true; status = "lcos.install.prepare".installLoc; defer { working = false }
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let identifier = identifier.trimmingCharacters(in: .whitespacesAndNewlines)
        let icon = icon
        let options = SigningAdvanced.Options(enableFileSharing: enableFileSharing,
                                              removeAppExtensions: false,
                                              excludedExtensionNames: excludedExtensions)
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
                try SigningAdvanced.customize(copy, name: name, identifier: identifier,
                                              iconPNG: icon, options: options)
                try SigningInjectionApply.prepare(app: copy.url, identifier: identifier, root: root)
                var error = [CChar](repeating: 0, count: 1024)
                guard lc_ipa_pack(staging.path, output.path, &error, error.count) == 0 else {
                    throw SigningInjectionFailure.invalid(String(cString: error))
                }
                try FileManager.default.removeItem(at: staging)
                SigningDiagnostics.record("advanced.prepare.end", "IPA ready for signing")
            }.value
            retained = true
            // The presenter waits for actual dismissal before SideStore begins import.
            installWithSideStore(output)
        } catch { SigningDiagnostics.failure("advanced.prepare.failed", error); failure = error.localizedDescription }
    }
}

@objc(LCOSAdvancedInstallPresenter)
final class LCOSAdvancedInstallPresenter: NSObject {
    @MainActor @objc(presentFrom:completion:)
    static func present(from presenter: UIViewController, completion: @escaping (URL?) -> Void) {
        guard presenter.viewIfLoaded?.window != nil, presenter.presentedViewController == nil else { completion(nil); return }
        weak var presented: UIViewController?
        var completed = false
        let sheet = UIHostingController(rootView: LCAdvancedInstallView(installWithSideStore: { url in
            guard !completed else { return }; completed = true
            presented?.dismiss(animated: true) { completion(url) }
        }))
        presented = sheet
        sheet.modalPresentationStyle = .pageSheet
        presenter.present(sheet, animated: true)
    }
}

private extension String {
    var installLoc: String {
        let bundle = Bundle(for: LCOSAdvancedInstallPresenter.self)
        var root = bundle.bundleURL
        for _ in 0..<5 {
            if let candidate = Bundle(url: root), candidate.path(forResource: "en", ofType: "lproj") != nil {
                let localized = candidate.localizedString(forKey: self, value: nil, table: nil)
                if localized != self { return localized }
            }
            root.deleteLastPathComponent()
        }
        return self
    }
}
