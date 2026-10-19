import SwiftUI

struct LCDiagnosticsView: View {
    @State private var enabled = SigningDiagnostics.enabled
    @State private var entries: [SigningDiagnostics.Entry] = []
    @State private var following = true
    @State private var errorsOnly = false
    @State private var query = ""
    @State private var failure: String?
    @State private var sharing = false
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    private var visible: [SigningDiagnostics.Entry] {
        entries.filter { (!errorsOnly || $0.level == "error") && (query.isEmpty || ($0.stage + $0.detail).localizedCaseInsensitiveContains(query)) }
    }
    private var export: String {
        (["LiveContainer OS · Installation diagnostics · " + Date().ISO8601Format()] + entries.map {
            "\($0.date.ISO8601Format()) [\($0.process)] \($0.level.uppercased()) \($0.stage)\n\($0.detail)"
        }).joined(separator: "\n")
    }
    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    Toggle("lcos.logs.enabled".loc, isOn: $enabled)
                        .onChange(of: enabled) { value in
                            do { try SigningDiagnostics.setEnabled(value); SigningDiagnostics.record("diagnostics.enabled", ProcessInfo.processInfo.operatingSystemVersionString) }
                            catch { failure = error.localizedDescription; enabled = SigningDiagnostics.enabled }
                        }
                } footer: { Text("lcos.logs.description".loc) }
                Section {
                    Toggle("lcos.logs.follow".loc, isOn: $following)
                    Toggle("lcos.logs.errors".loc, isOn: $errorsOnly)
                }
            }.frame(height: 250)
            ScrollViewReader { scroll in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        if visible.isEmpty { Text("lcos.logs.empty".loc).foregroundStyle(.secondary).padding(.vertical, 30) }
                        ForEach(visible) { entry in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(entry.stage).font(.caption.weight(.semibold)).foregroundStyle(entry.level == "error" ? Color.red : .primary)
                                    Spacer()
                                    Text(entry.date, style: .time).font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                                }
                                Text(entry.process).font(.caption2).foregroundStyle(.secondary)
                                if !entry.detail.isEmpty { Text(entry.detail).font(.caption.monospaced()).textSelection(.enabled) }
                            }.id(entry.id)
                            Divider()
                        }
                    }.padding()
                }.lcSoftScrollEdges()
                    .onChange(of: entries.last?.id) { id in if following, let id { scroll.scrollTo(id, anchor: .bottom) } }
            }
        }
        .navigationTitle("lcos.logs.title".loc)
        .searchable(text: $query)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button { sharing = true } label: { Label("lcos.logs.export".loc, systemImage: "square.and.arrow.up") }
                    Button(role: .destructive) {
                        do { try SigningDiagnostics.clear(); entries = [] } catch { failure = error.localizedDescription }
                    } label: { Label("lcos.logs.clear".loc, systemImage: "trash") }
                } label: { Image(systemName: "ellipsis.circle") }
            }
        }
        .task { entries = SigningDiagnostics.entries() }
        .sheet(isPresented: $sharing) { ActivityViewController(activityItems: [export]) }
        .onReceive(timer) { _ in if following { entries = SigningDiagnostics.entries() } }
        .alert("lc.common.error".loc, isPresented: Binding(get: { failure != nil }, set: { if !$0 { failure = nil } })) {
            Button("lc.common.ok".loc) { failure = nil }
        } message: { Text(failure ?? "") }
    }
}
