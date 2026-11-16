import SwiftUI

/// A single native List owns the scrolling area. The old fixed-height Form
/// (250pt) competed with the log ScrollView and obscured events on iPhone.
struct LCDiagnosticsView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var enabled = SigningDiagnostics.enabled
    @State private var entries: [SigningDiagnostics.Entry] = []
    @State private var following = true
    @State private var errorsOnly = false
    @State private var query = ""
    @State private var expanded: Set<UUID> = []
    @State private var showInfo = false
    @State private var confirmClear = false
    @State private var failure: String?
    @State private var sharing = false
    @State private var fetching = false
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var visible: [SigningDiagnostics.Entry] {
        entries.filter { (!errorsOnly || $0.level == "error") &&
            (query.isEmpty || ($0.stage + " " + $0.process + " " + $0.detail)
                .localizedCaseInsensitiveContains(query)) }
    }
    private var export: String {
        (["LifeContainer+ · Installation diagnostics · " + Date().ISO8601Format()] + entries.map {
            "\($0.date.ISO8601Format()) [\($0.process)] \($0.level.uppercased()) \($0.stage)\n\($0.detail)"
        }).joined(separator: "\n")
    }
    private var failureCount: Int { entries.filter { $0.level == "error" }.count }

    var body: some View {
        ScrollViewReader { scroll in
            List {
                Section {
                    Toggle("lcos.logs.enabled".loc, isOn: $enabled)
                        .onChange(of: enabled) { value in
                            do {
                                try SigningDiagnostics.setEnabled(value)
                                SigningDiagnostics.record("diagnostics.enabled",
                                    ProcessInfo.processInfo.operatingSystemVersionString)
                            } catch {
                                failure = error.localizedDescription
                                enabled = SigningDiagnostics.enabled
                            }
                        }
                    HStack {
                        Picker("lcos.logs.errors".loc, selection: $errorsOnly) {
                            Text("lcos.logs.all".loc).tag(false)
                            Text("lcos.logs.errors".loc).tag(true)
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        Button { following.toggle() } label: {
                            Image(systemName: following ? "arrow.down.to.line.compact" : "pause.circle")
                                .font(.title3)
                                .frame(width: 44, height: 44)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(following ? Color.accentColor : Color.secondary)
                        .accessibilityLabel("lcos.logs.follow".loc)
                        .accessibilityValue(following ? "On" : "Off")
                    }
                } header: {
                    HStack {
                        Label("lcos.logs.title".loc, systemImage: "waveform.path")
                        Spacer()
                        Text("\(visible.count)")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }
                Section {
                    if visible.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: errorsOnly ? "checkmark.shield" : "text.alignleft")
                                .font(.largeTitle)
                                .foregroundStyle(.secondary)
                            Text("lcos.logs.empty".loc)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, minHeight: 145)
                        .listRowBackground(Color.clear)
                    } else {
                        ForEach(visible) { entry in
                            logRow(entry).id(entry.id)
                        }
                    }
                } header: {
                    HStack {
                        Text("lcos.logs.events".loc)
                        Spacer()
                        if failureCount > 0 {
                            Label("\(failureCount)", systemImage: "exclamationmark.circle.fill")
                                .foregroundStyle(.red)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .onChange(of: entries.last?.id) { id in
                if following, let id, visible.contains(where: { $0.id == id }) {
                    scroll.scrollTo(id, anchor: .bottom)
                }
            }
        }
        .navigationTitle("lcos.logs.title".loc)
        .searchable(text: $query)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button { showInfo = true } label: {
                        Label("lcos.logs.about".loc, systemImage: "info.circle")
                    }
                    Button { sharing = true } label: {
                        Label("lcos.logs.export".loc, systemImage: "square.and.arrow.up")
                    }
                    Button(role: .destructive) { confirmClear = true } label: {
                        Label("lcos.logs.clear".loc, systemImage: "trash")
                    }
                } label: { Image(systemName: "ellipsis.circle") }
                    .accessibilityLabel("lcos.home.options".loc)
            }
        }
        .task { await reloadEntries() }
        .onReceive(timer) { _ in
            // Decoding log files off the main actor keeps 60/120Hz scrolling
            // responsive even when SideStore writes many events.
            Task { await reloadEntries() }
        }
        .sheet(isPresented: $sharing) { ActivityViewController(activityItems: [export]) }
        .sheet(isPresented: $showInfo) {
            NavigationView {
                ScrollView {
                    Text("lcos.logs.description".loc)
                        .font(.body).foregroundStyle(.secondary)
                        .padding()
                }
                .navigationTitle("lcos.logs.about".loc)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("lc.common.ok".loc) { showInfo = false }
                    }
                }
            }.navigationViewStyle(.stack)
        }
        .confirmationDialog("lcos.logs.clear".loc, isPresented: $confirmClear) {
            Button("lcos.logs.clear".loc, role: .destructive) {
                do { try SigningDiagnostics.clear(); entries = []; expanded = [] }
                catch { failure = error.localizedDescription }
            }
        }
        .alert("lc.common.error".loc, isPresented: Binding(
            get: { failure != nil }, set: { if !$0 { failure = nil } })) {
            Button("lc.common.ok".loc) { failure = nil }
        } message: { Text(failure ?? "") }
    }

    @MainActor
    private func reloadEntries() async {
        guard !fetching else { return }
        fetching = true
        defer { fetching = false }
        let latest = await Task.detached(priority: .utility) {
            SigningDiagnostics.entries()
        }.value
        guard !Task.isCancelled else { return }
        if latest.last?.id != entries.last?.id || latest.count != entries.count {
            entries = latest
        }
    }

    private func logRow(_ entry: SigningDiagnostics.Entry) -> some View {
        let isError = entry.level == "error"
        let isExpanded = expanded.contains(entry.id)
        return Button {
            if reduceMotion {
                toggle(entry.id)
            } else {
                withAnimation(.easeInOut(duration: 0.18)) { toggle(entry.id) }
            }
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    Image(systemName: isError ? "exclamationmark.circle.fill" : "checkmark.circle")
                        .foregroundStyle(isError ? Color.red : Color.secondary)
                    Text(entry.stage)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                    Spacer(minLength: 4)
                    Text(entry.date, style: .time)
                        .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption2.weight(.medium)).foregroundStyle(.tertiary)
                }
                Text(entry.process)
                    .font(.caption).foregroundStyle(.secondary)
                if isError && !isExpanded && !entry.detail.isEmpty {
                    Text(entry.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                if isExpanded && entry.detail.contains("InvalidVPN") {
                    Label("lcos.logs.vpnHint".loc, systemImage: "wifi.exclamationmark")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if isExpanded && !entry.detail.isEmpty {
                    Text(entry.detail)
                        .font(.system(.footnote, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 3)
                }
            }
            .padding(.vertical, 5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("lcos.logs.expand".loc)
    }

    private func toggle(_ id: UUID) {
        if expanded.contains(id) { expanded.remove(id) }
        else { expanded.insert(id) }
    }
}
