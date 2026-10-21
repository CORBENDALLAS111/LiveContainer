import SwiftUI

enum LCTweakDownload {
    static func fetch(_ url: URL, limit: Int) async throws -> Data {
        guard url.scheme == "https" else { throw PackageFailure.invalid("HTTPS is required.") }
        var request = URLRequest(url: url); request.timeoutInterval = 40
        let (stream, response) = try await URLSession.shared.bytes(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode),
              http.url?.scheme == "https", response.expectedContentLength <= Int64(limit) else {
            throw PackageFailure.invalid("Repository download failed or exceeds the size limit.")
        }
        var data = Data()
        for try await byte in stream {
            try Task.checkCancellation()
            guard data.count < limit else { throw PackageFailure.invalid("Repository download exceeds the size limit.") }
            data.append(byte)
        }
        return data
    }
}

@MainActor
struct LCTweakMarketplace: View {
    @AppStorage("LifeTweakSources", store: LCUtils.appGroupUserDefault) private var sourceJSON = "[]"
    @State private var packages: [TweakRepositoryPackage] = []
    @State private var query = ""
    @State private var addSource = false
    @State private var sourceURL = ""
    @State private var working = false
    @State private var failures: [String] = []
    @State private var error = ""
    private var sources: [TweakRepository] { (try? JSONDecoder().decode([TweakRepository].self, from: Data(sourceJSON.utf8))) ?? [] }
    private var results: [TweakRepositoryPackage] {
        packages.filter { query.isEmpty || ($0.name + " " + $0.summary + " " + $0.identifier).localizedCaseInsensitiveContains(query) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
    var body: some View {
        List {
            Section {
                HStack(spacing: 16) {
                    Image(systemName: "shippingbox.fill").font(.largeTitle).foregroundStyle(.tint)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("life.market.title".loc).font(.title2.bold())
                        Text("life.market.subtitle".loc).font(.subheadline).foregroundStyle(.secondary)
                    }
                }.padding(.vertical, 10)
            }
            Section("life.market.sources".loc) {
                ForEach(sources) { source in
                    HStack {
                        Image(systemName: "server.rack").foregroundStyle(.secondary)
                        Text(source.url.absoluteString).font(.subheadline).lineLimit(2)
                    }.swipeActions {
                        Button(role: .destructive) { save(sources.filter { $0.id != source.id }); Task { await refresh() } } label: {
                            Label("lc.common.delete".loc, systemImage: "trash")
                        }
                    }
                }
                Button { sourceURL = ""; addSource = true } label: { Label("life.market.addSource".loc, systemImage: "plus.circle.fill") }
            } footer: { Text("life.market.sourceHelp".loc) }
            if working { Section { ProgressView("life.market.loading".loc) } }
            if !failures.isEmpty { Section { ForEach(failures, id: \.self) { Text($0).font(.footnote).foregroundStyle(.secondary) } } }
            Section("life.market.packages".loc) {
                if sources.isEmpty { Text("life.market.empty".loc).foregroundStyle(.secondary) }
                ForEach(results) { package in
                    NavigationLink {
                        LCDebPackageView(repositoryPackage: package)
                    } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            HStack { Text(package.name).font(.headline); Spacer(); Text(package.version).font(.caption).foregroundStyle(.secondary) }
                            Text(package.summary).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                            Text(package.architecture + " · " + (URL(string: package.source)?.host ?? ""))
                                .font(.caption2).foregroundStyle(.secondary)
                        }.padding(.vertical, 5)
                    }
                }
            } footer: { Text("life.market.compatibility".loc) }
        }
        .navigationTitle("life.market.title".loc)
        .searchable(text: $query, prompt: "life.market.search".loc)
        .refreshable { await refresh() }
        .task { await refresh() }
        .alert("life.market.addSource".loc, isPresented: $addSource) {
            TextField("https://…", text: $sourceURL).textInputAutocapitalization(.never).keyboardType(.URL)
            Button("lc.common.cancel".loc, role: .cancel) {}
            Button("life.market.add".loc) {
                do {
                    let value = try TweakRepository.validated(sourceURL)
                    guard sources.count < 30 else { throw PackageFailure.invalid("Maximum 30 repositories.") }
                    if !sources.contains(value) { save(sources + [value]) }
                    Task { await refresh() }
                } catch { self.error = error.localizedDescription }
            }
        } message: { Text("life.market.sourceHelp".loc) }
        .alert("lc.common.error".loc, isPresented: Binding(get: { !error.isEmpty }, set: { if !$0 { error = "" } })) {
            Button("lc.common.ok".loc) { error = "" }
        } message: { Text(error) }
    }
    private func save(_ values: [TweakRepository]) {
        if let data = try? JSONEncoder().encode(values), let json = String(data: data, encoding: .utf8) { sourceJSON = json }
    }
    private func refresh() async {
        guard !working else { return }; working = true; defer { working = false }
        packages = []; failures = []
        for source in sources {
            do {
                var found: [TweakRepositoryPackage]?
                for path in ["Packages.xz", "Packages.gz", "Packages.bz2", "Packages"] {
                    do {
                        let data = try await LCTweakDownload.fetch(source.url.appendingPathComponent(path), limit: 16 * 1024 * 1024)
                        found = try await Task.detached { try TweakRepositoryIndex.parse(data, repository: source) }.value
                        break
                    } catch is CancellationError { return } catch { continue }
                }
                guard let found else { throw PackageFailure.invalid("life.market.indexError".loc) }
                packages.append(contentsOf: found)
            } catch { failures.append((source.url.host ?? source.id) + ": " + error.localizedDescription) }
        }
    }
}
