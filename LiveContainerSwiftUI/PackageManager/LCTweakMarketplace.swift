import SwiftUI

enum LCTweakDownload {
    static func fetch(_ url: URL, limit: Int) async throws -> Data {
        try Task.checkCancellation()
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
    @State private var showSources = false
    @State private var selectedSource = ""
    @State private var selectedCategory = ""
    @State private var rootlessOnly = true
    @State private var refreshID = UUID()
    @State private var addSource = false
    @State private var sourceURL = ""
    @State private var working = false
    @State private var failures: [String] = []
    @State private var error = ""
    private var sources: [TweakRepository] { (try? JSONDecoder().decode([TweakRepository].self, from: Data(sourceJSON.utf8))) ?? [] }
    private var results: [TweakRepositoryPackage] {
        packages.filter {
            (!rootlessOnly || $0.architecture != "iphoneos-arm") &&
            (selectedSource.isEmpty || $0.source == selectedSource) &&
            (selectedCategory.isEmpty || $0.section == selectedCategory) &&
            (query.isEmpty || ($0.name + " " + $0.summary + " " + $0.identifier).localizedCaseInsensitiveContains(query))
        }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
    var body: some View {
        List {
            marketplaceHeader
            if showSources { repositorySection } else { catalogFilters }
            if working { Section { ProgressView("life.market.loading".loc) } }
            if !failures.isEmpty { Section { ForEach(failures, id: \.self) { Text($0).font(.footnote).foregroundStyle(.secondary) } } }
            if !showSources { catalogSection }
            Section {
                NavigationLink { LCDebPackageView() } label: { Label("life.market.installed".loc, systemImage: "checkmark.seal") }
            }
        }
        .navigationTitle("life.market.title".loc)
        .searchable(text: $query, prompt: "life.market.search".loc)
        .refreshable { await refresh() }
        .task(id: sourceJSON) { await refresh() }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { sourceURL = ""; addSource = true } label: { Image(systemName: "plus") }
                    .accessibilityLabel("life.market.addSource".loc)
            }
        }
        .alert("life.market.addSource".loc, isPresented: $addSource) {
            TextField("https://…", text: $sourceURL).textInputAutocapitalization(.never).keyboardType(.URL)
            Button("lc.common.cancel".loc, role: .cancel) {}
            Button("life.market.add".loc) {
                do {
                    let value = try TweakRepository.validated(sourceURL)
                    guard sources.count < 30 else { throw PackageFailure.invalid("Maximum 30 repositories.") }
                    if !sources.contains(value) { save(sources + [value]) }
                } catch { self.error = error.localizedDescription }
            }
        } message: { Text("life.market.sourceHelp".loc) }
        .alert("lc.common.error".loc, isPresented: Binding(get: { !error.isEmpty }, set: { if !$0 { error = "" } })) {
            Button("lc.common.ok".loc) { error = "" }
        } message: { Text(error) }
    }
    private var marketplaceHeader: some View {
        Section {
            HStack(spacing: 16) {
                Image(systemName: "shippingbox.fill").font(.largeTitle).foregroundStyle(.tint)
                    .frame(width: 64, height: 64).background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 16))
                VStack(alignment: .leading, spacing: 4) {
                    Text("life.market.title".loc).font(.title2.bold())
                    Text("life.market.subtitle".loc).font(.subheadline).foregroundStyle(.secondary)
                }
            }.padding(.vertical, 8)
            Picker("life.market.title".loc, selection: $showSources) {
                Text("life.market.browse".loc).tag(false)
                Text("life.market.sources".loc).tag(true)
            }.pickerStyle(.segmented)
        }
    }
    private var repositorySection: some View {
        Section {
            ForEach(sources) { source in
                VStack(alignment: .leading, spacing: 5) {
                    Label(source.url.host ?? source.id, systemImage: "server.rack").font(.headline)
                    Text(source.url.absoluteString).font(.caption).foregroundStyle(.secondary)
                    Text("\(packages.filter { $0.source == source.id }.count) " + "life.market.packages".loc)
                        .font(.caption).foregroundStyle(.secondary)
                    Button("life.market.viewSource".loc) { selectedSource = source.id; showSources = false }
                }.padding(.vertical, 5).swipeActions {
                    Button(role: .destructive) {
                        save(sources.filter { $0.id != source.id })
                        packages.removeAll { $0.source == source.id }
                        if selectedSource == source.id { selectedSource = "" }
                    } label: { Label("lc.common.delete".loc, systemImage: "trash") }
                }
            }
            Button { sourceURL = ""; addSource = true } label: { Label("life.market.addSource".loc, systemImage: "plus.circle.fill") }
        } header: { Text("life.market.sources".loc) } footer: { Text("life.market.sourceHelp".loc) }
    }
    private var catalogFilters: some View {
        Section {
            Picker("life.market.sourceFilter".loc, selection: $selectedSource) {
                Text("life.market.allSources".loc).tag("")
                ForEach(sources) { source in Text(source.url.host ?? source.id).tag(source.id) }
            }
            Picker("life.market.category".loc, selection: $selectedCategory) {
                Text("life.market.allCategories".loc).tag("")
                ForEach(Array(Set(packages.map(\.section).filter { !$0.isEmpty })).sorted(), id: \.self) { Text($0).tag($0) }
            }
            Toggle("life.market.rootlessOnly".loc, isOn: $rootlessOnly)
        }
    }
    private var catalogSection: some View {
        Section {
            if sources.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("life.market.empty".loc).foregroundStyle(.secondary)
                    Button { sourceURL = ""; addSource = true } label: { Label("life.market.addSource".loc, systemImage: "plus.circle.fill") }
                }.padding(.vertical, 8)
            } else if results.isEmpty && !working {
                Text("life.market.noResults".loc).foregroundStyle(.secondary)
            }
            ForEach(results) { package in
                NavigationLink { LCDebPackageView(repositoryPackage: package) } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "puzzlepiece.extension.fill").font(.title2).foregroundStyle(.tint)
                            .frame(width: 48, height: 48).background(Color.accentColor.opacity(0.10), in: RoundedRectangle(cornerRadius: 12))
                        VStack(alignment: .leading, spacing: 5) {
                            HStack { Text(package.name).font(.headline); Spacer(); Text(package.version).font(.caption).foregroundStyle(.secondary) }
                            Text(package.summary).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                            Text((package.section.isEmpty ? package.architecture : package.section) + " · " + (URL(string: package.source)?.host ?? ""))
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                    }.padding(.vertical, 5)
                }
            }
        } header: { Text("life.market.packages".loc) } footer: { Text("life.market.compatibility".loc) }
    }
    private func save(_ values: [TweakRepository]) {
        if let data = try? JSONEncoder().encode(values), let json = String(data: data, encoding: .utf8) { sourceJSON = json }
    }
    private func refresh() async {
        let generation = UUID(); refreshID = generation
        working = true
        defer { if refreshID == generation { working = false } }
        var loaded: [TweakRepositoryPackage] = []
        var errors: [String] = []
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
                loaded.append(contentsOf: found)
            } catch is CancellationError { return }
            catch { errors.append((source.url.host ?? source.id) + ": " + error.localizedDescription) }
        }
        guard !Task.isCancelled, refreshID == generation else { return }
        packages = loaded; failures = errors
        if !selectedCategory.isEmpty && !loaded.contains(where: { $0.section == selectedCategory }) { selectedCategory = "" }
    }
}
