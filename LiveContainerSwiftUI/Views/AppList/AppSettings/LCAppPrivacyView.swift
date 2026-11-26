import SwiftUI
import UIKit

/// These switches request guest-level API restrictions, not system TCC
/// permissions. The guest must be fully stopped and launched again.
struct LCAppPrivacyView: View {
    let appInfo: LCAppInfo
    @ObservedObject var model: LCAppModel
    @State private var enabled: Set<String> = []
    @State private var saveFailed = false
    @State private var confirmReset = false

    private struct Restriction: Identifiable {
        let id: String
        let icon: String
        var title: String { ("lcos.privacy." + id).loc }
        var detail: String { ("lcos.privacy." + id + ".detail").loc }
    }

    private let media = [
        Restriction(id: "camera", icon: "camera"),
        Restriction(id: "microphone", icon: "mic")
    ]
    private let device = [
        Restriction(id: "battery", icon: "battery.75percent"),
        Restriction(id: "proximity", icon: "sensor")
    ]
    private let events = [
        Restriction(id: "screenshotEvents", icon: "camera.viewfinder")
    ]

    private var all: [Restriction] { media + device + events }

    var body: some View {
        Form {
            Section {
                Label("lcos.privacy.explanation".loc, systemImage: "info.circle")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if model.isAppRunning {
                    Label("lcos.privacy.running".loc, systemImage: "arrow.clockwise")
                        .font(.subheadline)
                }
            }
            Section {
                ForEach(media) { restrictionRow($0) }
            } header: {
                Text("lcos.privacy.media".loc)
            }
            Section {
                ForEach(device) { restrictionRow($0) }
            } header: {
                Text("lcos.privacy.device".loc)
            }
            Section {
                ForEach(events) { restrictionRow($0) }
            } header: {
                Text("lcos.privacy.events".loc)
            }
            Section {
                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                } label: {
                    Label("lcos.access.systemSettings".loc, systemImage: "gear")
                }
            } footer: {
                Text("lcos.privacy.systemHelp".loc)
            }
            Section {
                Button("lcos.privacy.reset".loc, role: .destructive) {
                    confirmReset = true
                }
                .disabled(enabled.isEmpty)
            }
        }
        .navigationTitle("lcos.privacy.title".loc)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: reload)
        .alert("lc.common.error".loc, isPresented: $saveFailed) {
            Button("lc.common.ok".loc, role: .cancel) {}
        } message: {
            Text("lcos.privacy.saveFailed".loc)
        }
        .confirmationDialog("lcos.privacy.reset".loc, isPresented: $confirmReset, titleVisibility: .visible) {
            Button("lcos.privacy.reset".loc, role: .destructive) {
                for restriction in all where enabled.contains(restriction.id) {
                    if !appInfo.setPrivacyRestriction(restriction.id, enabled: false) {
                        saveFailed = true
                    }
                }
                reload()
            }
            Button("lc.common.cancel".loc, role: .cancel) {}
        }
    }

    private func reload() {
        enabled = Set(all.filter { appInfo.privacyRestrictionEnabled($0.id) }.map(\.id))
    }

    private func restrictionRow(_ restriction: Restriction) -> some View {
        Toggle(isOn: Binding(
            get: { enabled.contains(restriction.id) },
            set: { value in
                if appInfo.setPrivacyRestriction(restriction.id, enabled: value) {
                    if value { enabled.insert(restriction.id) }
                    else { enabled.remove(restriction.id) }
                } else {
                    saveFailed = true
                    reload()
                }
            }
        )) {
            Label {
                VStack(alignment: .leading, spacing: 4) {
                    Text(restriction.title)
                    Text(restriction.detail)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } icon: {
                Image(systemName: restriction.icon)
            }
        }
        .accessibilityIdentifier("lifecontainer.privacy." + restriction.id)
    }
}
