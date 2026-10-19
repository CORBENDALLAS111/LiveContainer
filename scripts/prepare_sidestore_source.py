"""Apply the signing overlay to one pinned personal SideStore build; never publishes upstream."""
import hashlib,json,pathlib,shutil,subprocess,sys
root=pathlib.Path(__file__).resolve().parent.parent
source=pathlib.Path(sys.argv[1]).resolve()
expected=(root/'Integrations/SideStore/SOURCE_COMMIT').read_text().strip()
actual=subprocess.check_output(['git','-C',str(source),'rev-parse','HEAD'],text=True).strip()
assert actual==expected, 'SideStore source revision changed; review signing integration before rebuilding'
operation=source/'SideStore/Core/Operations/PipelineOperations/ResignAppOperation.swift'
s=operation.read_text(encoding='utf-8')
anchor='        let appBundleURL = try await self.prepareAppBundle(for: appBundle, profiles: profiles, appexBundleIds: context.appexBundleIds ?? [:])'
assert s.count(anchor)==1
s=s.replace(anchor, '        let lcosOriginalBundleIdentifier = self.context.bundleIdentifier\n'+anchor+'\n        try SigningBundleIdentifiers.validateBundle(at: appBundleURL)\n        try LCOSSigningInjection.prepare(at: appBundleURL, bundleIdentifier: lcosOriginalBundleIdentifier)')
anchor='        let newBundleID = appexBundleIds[identifier] ?? profile.bundleIdentifier'
assert s.count(anchor)==1
s=s.replace(anchor, '''        if context.useMainProfile, identifier != context.targetBundleIdentifier, appexBundleIds[identifier] == nil {
            throw OperationError.invalidParameters("Missing extension bundle ID mapping for " + identifier)
        }
'''+anchor)
operation.write_text(s,encoding='utf-8')

extension_operation=source/'SideStore/Core/Operations/PipelineOperations/PrepareAppExtensionBundleIDsOperation.swift'
s=extension_operation.read_text(encoding='utf-8')
start=s.index('        if self.context.useMainProfile {')
end=s.index('        self.setProgress(100)',start)
s=s[:start]+'''        if self.context.useMainProfile {
            guard let appBundle = self.context.targetAppBundle,
                  let profile = self.context.provisioningProfiles?[self.context.targetBundleIdentifier] else {
                throw OperationError.invalidParameters("Missing main profile for extension bundle ID preparation")
            }
            self.context.appexBundleIds = try SigningBundleIdentifiers.extensionMap(
                originalParent: appBundle.bundleIdentifier, targetParent: self.context.targetBundleIdentifier,
                signedParent: profile.bundleIdentifier, extensions: appBundle.appExtensions.map { $0.bundleIdentifier })
        }
'''+s[end:]
extension_operation.write_text(s,encoding='utf-8')

executor=source/'SideStore/Core/Operations/PipelineExecutor.swift'
s=executor.read_text(encoding='utf-8')
anchor='''                let step = try UserCustomizationOperation(context: context)
                result = try await step.execute(parentProgress: progress)
                return nil'''
assert s.count(anchor)==1
s=s.replace(anchor,'''                let step = try UserCustomizationOperation(context: context)
                result = try await step.execute(parentProgress: progress)
                // Host-prepared presets; the guest only attaches its lightweight UIKit log console.
                return nil''')
anchor='        var finalApp: InstalledApp?'
assert s.count(anchor)==1
s=s.replace(anchor,'''        if let handler = context.handler as? PipelineHandler {
            try await handler.configureLCOSInjection(identifier: context.bundleIdentifier, appName: downloadingApp.name)
        }
'''+anchor)
anchor='        var result: Any? = "()"'
assert s.count(anchor)==1
s=s.replace(anchor,'''        let diagnosticStage = String(describing: step)
        let diagnosticStart = Date()
        SigningDiagnostics.record(diagnosticStage + ".begin", "App: " + context.bundleIdentifier + "; iOS " + ProcessInfo.processInfo.operatingSystemVersionString)
        defer { SigningDiagnostics.record(diagnosticStage + ".end", String(format: "Elapsed %.3fs", Date().timeIntervalSince(diagnosticStart))) }
'''+anchor)
anchor='            result = error\n            throw error'
assert s.count(anchor)==1
s=s.replace(anchor,'            SigningDiagnostics.failure(diagnosticStage + ".failed", error)\n'+anchor)
executor.write_text(s,encoding='utf-8')
file_import=source/'SideStore/DeepLinks/FileImportHandler.swift'
s=file_import.read_text(encoding='utf-8')
anchor='    private func handleIPAImport(fileURL: URL) -> Bool {'
assert s.count(anchor)==1
s=s.replace(anchor,anchor+'\n        SigningDiagnostics.record("import.begin", fileURL.lastPathComponent)')
s=s.replace('            debugLog("[FileImportHandler] Failed to', '            SigningDiagnostics.failure("import.failed", error)\n            debugLog("[FileImportHandler] Failed to')
file_import.write_text(s,encoding='utf-8')

# Preserve the picked file before dismissing Files; never present a second modal during its dismissal.
myapps=source/'AltStore/My Apps/MyAppsViewController.swift'
s=myapps.read_text(encoding='utf-8')
anchor='''        guard let fileURL = urls.first else { return }
\x20\x20\x20\x20\x20\x20\x20\x20
        InstallAppDialog.present(ipaURL: fileURL, from: self) { [weak self] in
            self?.sideloadApp(at: fileURL) { (result) in
                debugLog("Sideloaded app at \(fileURL) with result: \(result)")
            }
        }'''
assert s.count(anchor)==1
s=s.replace(anchor,'''        guard let fileURL = urls.first else { return }
        SigningDiagnostics.record("picker.selected", fileURL.lastPathComponent)
        let secured = fileURL.startAccessingSecurityScopedResource()
        Task { @MainActor in
            defer { if secured { fileURL.stopAccessingSecurityScopedResource() } }
            do {
                let owned = try await Task.detached(priority: .userInitiated) {
                    let info = try fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
                    guard info.isRegularFile == true, fileURL.pathExtension.lowercased() == "ipa" else {
                        throw OperationError.invalidParameters("Choose a regular IPA file")
                    }
                    let directory = FileManager.default.uniqueTemporaryURL()
                    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                    let copy = directory.appendingPathComponent(fileURL.lastPathComponent)
                    try FileManager.default.copyItem(at: fileURL, to: copy)
                    return copy
                }.value
                SigningDiagnostics.record("picker.copied", "Local IPA retained for the complete installation")
                controller.dismiss(animated: true) { [weak self] in
                    guard let self else { return }
                    SigningDiagnostics.record("picker.dismissed")
                    InstallAppDialog.present(ipaURL: owned, from: self) { [weak self] in
                        self?.sideloadApp(at: owned) { result in
                            if case .failure(let error) = result { SigningDiagnostics.failure("install.failed", error) }
                            else { SigningDiagnostics.record("install.complete") }
                        }
                    }
                }
            } catch {
                SigningDiagnostics.failure("picker.failed", error)
                controller.dismiss(animated: true) { [weak self] in
                    guard let self else { return }
                    let alert = UIAlertController(title: "Import failed", message: error.localizedDescription, preferredStyle: .alert)
                    alert.addAction(UIAlertAction(title: "OK", style: .default))
                    self.present(alert, animated: true)
                }
            }
        }''')
anchor='    func sideloadApp(at url: URL, completion: @escaping (Result<Void, Error>) -> Void)\n    {'
assert s.count(anchor)==1
s=s.replace(anchor,anchor+'\n        SigningDiagnostics.record("install.requested", url.lastPathComponent)')
myapps.write_text(s,encoding='utf-8')

# Breadcrumbs before unpacking and SideSign's native metadata parser (earlier than pipeline customization).
download=source/'SideStore/Core/Operations/StandaloneOperations/DownloadAppOperation.swift'
s=download.read_text(encoding='utf-8')
anchor='            appBundleURL = try FileManager.default.unzipAppBundle(at: fileURL, toDirectory: self.temporaryDirectory)'
assert s.count(anchor)==1
s=s.replace(anchor,'            SigningDiagnostics.record("ipa.unpack.begin")\n'+anchor+'\n            SigningDiagnostics.record("ipa.unpack.end")')
anchor='        guard let appBundle = ALTApplication(fileURL: appBundleURL) else {'
assert s.count(anchor)==1
s=s.replace(anchor,'        SigningDiagnostics.record("ipa.metadata.begin")\n'+anchor)
anchor='        return appBundle'
assert s.count(anchor)==1
s=s.replace(anchor,'        SigningDiagnostics.record("ipa.metadata.end", appBundle.bundleIdentifier)\n'+anchor)
download.write_text(s,encoding='utf-8')

handler=source/'SideStore/Handlers/PipelineHandler.swift'
s=handler.read_text(encoding='utf-8')
anchor='    let isResignActive: Bool'
assert s.count(anchor)==1
s=s.replace(anchor,'''    @MainActor
    func configureLCOSInjection(identifier: String, appName: String) async throws {
        guard let presenter = self.activePresenter else { return }
        try await LCOSSigningInjectionUI.configure(identifier: identifier, appName: appName, presenter: presenter)
    }

'''+anchor)
handler.write_text(s,encoding='utf-8')
destination=source/'SideStore/Core/LCOSSigningInjection';destination.mkdir(exist_ok=True)
files=[root/'Integrations/SideStore'/name for name in ['LCOSSigningInjection.swift','LCOSSigningInjectionUI.swift']]+[root/'LiveContainerSwiftUI/PackageManager/Core'/name for name in ['SigningMachO.swift','SigningInjectionPreset.swift','SigningBundleIdentifiers.swift','PackageSHA256.swift','SigningDiagnostics.swift']]
for file in files:shutil.copyfile(file,destination/file.name)
manifest={'schema':1,'integration_script_sha256':hashlib.sha256(pathlib.Path(__file__).read_bytes()).hexdigest(),'resign_operation_sha256':hashlib.sha256(operation.read_bytes()).hexdigest(),'repository':'LiveContainer/SideStore','commit':actual,'overlay':{file.name:hashlib.sha256(file.read_bytes()).hexdigest() for file in files},'signing_phase':'after bundle preparation, before ALTSigner.signApp'}
manifest['install_ui']={'executor_sha256':hashlib.sha256(executor.read_bytes()).hexdigest(),'handler_sha256':hashlib.sha256(handler.read_bytes()).hexdigest(),'phase':'advanced configuration in host; no guest framework loading', 'host_ui_only':True, 'pipeline_diagnostics':True, 'picker_owned_copy':True, 'picker_sha256':hashlib.sha256(myapps.read_bytes()).hexdigest(), 'download_sha256':hashlib.sha256(download.read_bytes()).hexdigest()}
manifest['extension_ids']={'prepare_sha256':hashlib.sha256(extension_operation.read_bytes()).hexdigest(),'validate_before_signing':True}
(source/'LCOS_SOURCE.json').write_text(json.dumps(manifest,indent=2)+'\n')
print(json.dumps(manifest,indent=2))
