import SwiftUI
import UIKit

struct LCAutomationSettingsView: View {
    @EnvironmentObject private var sharedModel: SharedModel
    @State private var file = LCAutomationFile.load()
    @State private var editing: LCAutomation?
    @State private var error: String?
    @State private var lastResult = ""

    var body: some View {
        Form {
            Section {
                Button("lcos.automation.openShortcuts".loc) {
                    UIApplication.shared.open(URL(string: "shortcuts://")!)
                }
                Text("lcos.automation.instructions".loc).foregroundStyle(.secondary)
            } header: { Text("lcos.automation.shortcuts".loc) }
            Section {
                Toggle("lcos.automation.enable".loc, isOn: $file.enabled)
                    .onChange(of: file.enabled) { _ in save() }
            } footer: { Text("lcos.automation.limits".loc) }
            Section {
                ForEach(file.profiles) { profile in
                    Button { editing = profile } label: {
                        HStack {
                            VStack(alignment: .leading) {
                                Text(profile.name).foregroundStyle(.primary)
                                Text(appName(profile.app)).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }.onDelete { offsets in file.profiles.remove(atOffsets: offsets); save() }
                Button { editing = LCAutomation(app: sharedModel.apps.first?.appInfo.relativeBundlePath ?? "") } label: {
                    Label("lcos.automation.new".loc, systemImage: "plus")
                }.disabled(file.profiles.count >= 100 || sharedModel.apps.isEmpty)
            } header: { Text("lcos.automation.scenarios".loc) }
            if !lastResult.isEmpty {
                Section { Text(lastResult).font(.callout).textSelection(.enabled) }
                    header: { Text("lcos.automation.lastResult".loc) }
            }
        }
        .navigationTitle("lcos.automation.title".loc)
        .onAppear {
            file = .load()
            save()
            if let result = UserDefaults.standard.dictionary(forKey: "LCOSAutomationLastResult"),
               let message = result["message"] as? String, let date = result["date"] as? Double {
                lastResult = Date(timeIntervalSince1970: date).formatted() + "\n" + message
            }
        }
        .sheet(item: $editing) { profile in
            NavigationView {
                LCAutomationEditor(profile: profile, apps: sharedModel.apps) { value in
                    if let index = file.profiles.firstIndex(where: { $0.id == value.id }) { file.profiles[index] = value }
                    else { file.profiles.append(value) }
                    save()
                }
            }
        }
        .alert("lc.common.error".loc, isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK") { error = nil }
        } message: { Text(error ?? "") }
    }
    private func appName(_ id: String) -> String {
        sharedModel.apps.first { $0.appInfo.relativeBundlePath == id }?.displayName ?? id
    }
    private func save() {
        file.scheme = LCUtils.appUrlScheme() ?? "livecontainer"
        // Hidden applications are deliberately not advertised to Siri/Shortcuts.
        file.apps = sharedModel.apps.filter { !$0.uiIsLocked && !$0.appInfo.isHidden }.compactMap {
            guard let id = $0.appInfo.relativeBundlePath else { return nil }
            return .init(id: id, name: $0.displayName)
        }
        do { try file.save() } catch { self.error = error.localizedDescription }
    }
}

private struct LCAutomationEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draft: LCAutomation
    let apps: [LCAppModel]
    let save: (LCAutomation) -> Void
    init(profile: LCAutomation, apps: [LCAppModel], save: @escaping (LCAutomation) -> Void) {
        _draft = State(initialValue: profile); self.apps = apps; self.save = save
    }
    var body: some View {
        Form {
            Section {
                TextField("lcos.automation.name".loc, text: $draft.name)
                Picker("lcos.automation.app".loc, selection: $draft.app) {
                    Text("lc.common.none".loc).tag("")
                    ForEach(apps, id: \.self) { app in
                        Text(app.displayName).tag(app.appInfo.relativeBundlePath ?? "")
                    }
                }
            }
            Section {
                ForEach($draft.steps) { $step in
                    VStack(alignment: .leading, spacing: 12) {
                        Picker("lcos.automation.action".loc, selection: $step.kind) {
                            ForEach(LCAutomationStep.Kind.allCases, id: \.self) { kind in
                                Text(("lcos.automation.kind." + kind.rawValue).loc).tag(kind)
                            }
                        }
                        Stepper(value: $step.seconds, in: 0.2...60, step: 0.2) {
                            Text("lcos.automation.delay".loc + ": " + String(format: "%.1f s", step.seconds))
                        }
                        if step.kind == .button {
                            TextField("lcos.automation.target".loc, text: $step.target).autocorrectionDisabled()
                        } else if step.kind == .point {
                            Text("X: \(Int(step.x * 100))%")
                            Slider(value: $step.x, in: 0...1)
                            Text("Y: \(Int(step.y * 100))%")
                            Slider(value: $step.y, in: 0...1)
                        }
                    }.padding(.vertical, 4)
                }.onDelete { draft.steps.remove(atOffsets: $0) }
                    .onMove { draft.steps.move(fromOffsets: $0, toOffset: $1) }
                Button("lcos.automation.addStep".loc) { draft.steps.append(.init()) }.disabled(draft.steps.count >= 60)
            } header: { Text("lcos.automation.steps".loc) }
                footer: { Text("lcos.automation.stepHelp".loc) }
            Section {
                Button("lcos.automation.copyURL".loc) {
                    if let scheme = LCUtils.appUrlScheme() {
                        UIPasteboard.general.url = draft.launchURL(scheme: scheme)
                    }
                }.disabled(!draft.isValid)
            } footer: { Text("lcos.automation.saveHelp".loc) }
        }
        .navigationTitle("lcos.automation.scenario".loc)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("lc.common.cancel".loc) { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("lcos.automation.save".loc) { save(draft); dismiss() }.disabled(!draft.isValid)
            }
            ToolbarItem(placement: .bottomBar) { EditButton() }
        }
    }
}
