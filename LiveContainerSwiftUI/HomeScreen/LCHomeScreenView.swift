import SwiftUI
import UniformTypeIdentifiers

struct LCHomeScreenView: View {
    let apps: [LCAppModel]
    let delegate: LCAppBannerDelegate
    let importing: Bool
    let installProgress: Float
    let importIPA: () -> Void
    let importURL: () -> Void
    let openLink: () -> Void
    let openSideStore: (() -> Void)?
    @EnvironmentObject private var shared: SharedModel
    @Environment(\.colorScheme) private var scheme
    @Environment(\.sizeCategory) private var sizeCategory
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("LCOSHomeScreenEnabled", store: LCUtils.appGroupUserDefault) private var gridEnabled = true
    @AppStorage("LCOSHomeLayout", store: LCUtils.appGroupUserDefault) private var layoutJSON = ""
    @AppStorage("LCOSHomeIconScale", store: LCUtils.appGroupUserDefault) private var iconScale = 1.0
    @AppStorage("LCOSHomeShowLabels", store: LCUtils.appGroupUserDefault) private var showLabels = true
    @AppStorage("LCOSHomeScrollIndicator", store: LCUtils.appGroupUserDefault) private var showScrollIndicator = true
    @AppStorage("LCOSHomeEdgeFade", store: LCUtils.appGroupUserDefault) private var edgeFade = true
    @AppStorage("LCOSHomeMotionMode", store: LCUtils.appGroupUserDefault) private var motionMode = "standard"
    @State private var query = ""
    @State private var searching = false
    @State private var editing = false
    @State private var draggedID: String?
    @State private var dragOrigin: LCHomeLayout?
    @State private var folderID: String?
    @State private var folderName = ""
    @State private var folderPage = 0
    @State private var folderCapacity = 9
    @State private var folderProgress: CGFloat = 0
    @State private var folderTargetOpen = true
    @State private var folderAnimating = false
    @State private var folderFrames: [String: CGRect] = [:]
    @State private var folderCloseTask: Task<Void, Never>?
    @State private var folderExitTask: Task<Void, Never>?
    #if DEBUG
    @State private var previewMotionTask: Task<Void, Never>?
    #endif
    @GestureState private var folderPinch: CGFloat = 1
    @State private var hoveredID: String?
    @State private var folderCandidate: String?
    @State private var reorderTarget: String?
    @State private var hoverTask: Task<Void, Never>?
    @State private var edgeTask: Task<Void, Never>?
    @State private var resetConfirmation = false
    @FocusState private var searchFocused: Bool
    private static let dragType = UTType(exportedAs: "org.livecontainer.desktop-app")
    private static let deviceModel: String = {
        var info = utsname(); uname(&info)
        let capacity = MemoryLayout.size(ofValue: info.machine)
        return withUnsafePointer(to: &info.machine) { pointer in
            pointer.withMemoryRebound(to: CChar.self, capacity: capacity) { String(cString: $0) }
        }
    }()

    private var available: [String] { apps.map(identifier) }
    @State private var cachedLayout = LCHomeLayout()
    // Lookup is constant-time while scrolling a large guest library. Retain
    // the real registry models, never synthesize a duplicate app instance.
    @State private var modelsByIdentifier: [String: LCAppModel] = [:]
    private var layout: LCHomeLayout { cachedLayout }
    private func refreshAppIndex() {
        var lookup: [String: LCAppModel] = [:]
        lookup.reserveCapacity(apps.count)
        for app in apps { lookup[identifier(app)] = app }
        modelsByIdentifier = lookup
    }
    private func refreshLayout() {
        guard let data = layoutJSON.data(using: .utf8), let value = try? JSONDecoder().decode(LCHomeLayout.self, from: data),
              (1...2).contains(value.version) else { cachedLayout = LCHomeLayout().reconciled(available); return }
        cachedLayout = value.reconciled(available)
    }
    private func identifier(_ app: LCAppModel) -> String { "\(app.bundleIdentifier):\(app.appInfo.relativeBundlePath ?? app.bundleIdentifier)" }
    private func model(_ id: String) -> LCAppModel? {
        modelsByIdentifier[id] ?? apps.first { identifier($0) == id }
    }
    private func save(_ value: LCHomeLayout) {
        guard let data = try? JSONEncoder().encode(value), let string = String(data: data, encoding: .utf8) else { return }
        cachedLayout = value.reconciled(available)
        layoutJSON = string
    }
    private var motionEnabled: Bool { !reduceMotion && motionMode != "off" }
    private var homeAnimation: Animation? {
        guard motionEnabled else { return nil }
        return motionMode == "gentle"
            ? .easeInOut(duration: 0.22)
            : .spring(response: 0.32, dampingFraction: 0.86)
    }
    private func animate(_ action: () -> Void) { withAnimation(homeAnimation, action) }
    private func animateFolder(_ action: () -> Void) {
        withAnimation(motionEnabled ? (motionMode == "gentle"
            ? .easeInOut(duration: 0.25) : .spring(response: 0.42, dampingFraction: 0.86)) : nil, action)
    }

    var body: some View {
        GeometryReader { geometry in
            homeCanvas(geometry)
        }
        .onReceive(NotificationCenter.default.publisher(for: .lcosTopBarEdit)) { _ in
            guard gridEnabled else { return }
            startEditing()
        }
        .onReceive(NotificationCenter.default.publisher(for: .lcosTopBarDone)) { _ in
            if editing { finishEditing() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .lcosTopBarReset)) { _ in
            resetConfirmation = true
        }
        .onChange(of: editing) { isEditing in
            NotificationCenter.default.post(name: .lcosTopBarEditingChanged, object: isEditing)
        }
        .confirmationDialog("lcos.home.reset".loc, isPresented: $resetConfirmation) {
            Button("lcos.home.reset".loc, role: .destructive) { save(LCHomeLayout()); folderID = nil; folderProgress = 0 }
        }
        .onChange(of: layoutJSON) { _ in refreshLayout() }
        .onChange(of: available) { _ in
            refreshAppIndex()
            refreshLayout()
        }
        .onChange(of: layout.folders) { folders in
            guard let id = folderID else { return }
            guard let folder = folders.first(where: { $0.id == id }) else {
                folderCloseTask?.cancel(); animateFolder { folderID = nil; folderProgress = 0 }; return
            }
            folderPage = min(folderPage, max(0, (folder.apps.count - 1) / folderCapacity))
        }
        .onAppear {
            refreshAppIndex()
            refreshLayout()
            NotificationCenter.default.post(name: .lcosTopBarEditingChanged, object: editing)
            #if DEBUG
            // Screenshot fixtures are explicitly gated and compiled out of distribution builds.
            if UserDefaults.standard.bool(forKey: "LCOSPreviewEnabled") {
                if UserDefaults.standard.bool(forKey: "LCOSPreviewEditing") { startEditing() }
                let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("preview-config.plist")
                if let data = try? Data(contentsOf: url),
                   let values = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
                   let json = values["LCOSHomeLayout"] as? String { layoutJSON = json }
                if let id = UserDefaults.standard.string(forKey: "LCOSPreviewFolder"),
                   let folder = layout.folders.first(where: { $0.id == id }) { folderID = id; folderName = folder.name }
                if UserDefaults.standard.bool(forKey: "LCOSPreviewMotion"), let folder = layout.folders.first {
                    startEditing()
                    previewMotionTask = Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 4_000_000_000)
                        guard !Task.isCancelled else { return }
                        openFolder(folder)
                        try? await Task.sleep(nanoseconds: 120_000_000)
                        guard !Task.isCancelled else { return }
                        closeFolder()
                        try? await Task.sleep(nanoseconds: 120_000_000)
                        guard !Task.isCancelled else { return }
                        reverseFolder()
                        try? await Task.sleep(nanoseconds: 1_760_000_000)
                        guard !Task.isCancelled else { return }
                        closeFolder()
                        try? await Task.sleep(nanoseconds: 2_000_000_000)
                        guard !Task.isCancelled else { return }
                        openFolder(folder)
                        try? await Task.sleep(nanoseconds: 2_000_000_000)
                        guard !Task.isCancelled else { return }
                        closeFolder()
                        try? await Task.sleep(nanoseconds: 1_000_000_000)
                        guard !Task.isCancelled else { return }
                    }
                }
            }
            #endif
        }
        .onDisappear {
            cancelDrag(); folderCloseTask?.cancel()
            #if DEBUG
            previewMotionTask?.cancel()
            #endif
        }
    }

    /// Isolate the grid layout from the event/notification modifiers. In
    /// addition to simpler ownership, this avoids SwiftUI's simulator
    /// compiler timeout when type-checking an oversized GeometryReader body.
    private func homeCanvas(_ geometry: GeometryProxy) -> some View {
        // Window height is not used to paginate the root grid.
        // Folder layout keeps its own available-height calculation.
        let reservedHeight: CGFloat = searching ? 206 : 162
        let metrics = LCHomeMetrics(
            width: geometry.size.width,
            height: max(0, geometry.size.height - reservedHeight),
            tablet: UIDevice.current.userInterfaceIdiom == .pad,
            mini: LCHomeMetrics.isMini(
                model: Self.deviceModel,
                shortSide: min(UIScreen.main.bounds.width, UIScreen.main.bounds.height)
            ),
            accessibility: sizeCategory.isAccessibilityCategory,
            isLandscape: geometry.size.width > geometry.size.height
        )
        let cellWidth = max(1, (geometry.size.width - 2 * CGFloat(metrics.horizontalInset)
                                - CGFloat(max(0, metrics.columns - 1)) * 10)
                                / CGFloat(metrics.columns))
        let side = min(max(24, cellWidth - 4),
                       CGFloat(metrics.iconSide) * CGFloat(min(1.1, max(0.85, iconScale))))
        let ids = query.isEmpty
            ? layout.rootItems(available)
            : layout.ordered(available).filter { id in
                guard let app = model(id) else { return false }
                return app.displayName.localizedCaseInsensitiveContains(query) ||
                    app.bundleIdentifier.localizedCaseInsensitiveContains(query)
            }

        return ZStack {
            // The system owns the region under the floating tab bar. Do
            // not cover it with a full-screen opaque background rectangle.
            Color(uiColor: .systemBackground)
                .contentShape(Rectangle())
                .onLongPressGesture { startEditing() }

            homeChrome(homeGridItems(ids, columns: metrics.columns, side: side, metrics: metrics))
                .frame(maxWidth: .infinity)
                .scaleEffect(motionEnabled ? 1 + 0.045 * folderProgress : 1)
                .blur(radius: motionEnabled ? 8 * folderProgress : 0)
                .allowsHitTesting(folderID == nil)
                .accessibilityHidden(folderID != nil)

            if let id = folderID,
               let folder = layout.folders.first(where: { $0.id == id }) {
                folderOverlay(folder, frame: geometry.frame(in: .global), side: side)
                    .zIndex(2)
            }
        }
        .onPreferenceChange(LCHomeFolderFrames.self) {
            if folderID == nil { folderFrames = $0 }
        }
    }

    @ViewBuilder
    private func homeGridItems(_ ids: [String], columns: Int, side: CGFloat,
                               metrics: LCHomeMetrics) -> some View {
        if apps.isEmpty {
            emptyState
        } else if ids.isEmpty {
            Text("lcos.home.noResults".loc)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            continuousGrid(ids, columns: columns, side: side, metrics: metrics)
        }
    }

    /// iOS 26's safeAreaBar extends the native scroll edge effect through
    /// pinned controls. The older safeAreaInset path remains functional without
    /// adding a custom blur/gradient rectangle over the icon grid.
    @ViewBuilder
    private func homeChrome<Content: View>(_ content: Content) -> some View {
        if #available(iOS 26.0, *) {
            // This screen, not a window-wide overlay, owns all app actions.
            // Compact iPad windows and iPhones get the same safe-area behavior.
            content
                .safeAreaBar(edge: .top, spacing: 0) { pinnedControls }
                .safeAreaInset(edge: .top, spacing: 0) { pinnedTitle }
                .safeAreaBar(edge: .bottom, spacing: 0) { pinnedSearch }
        } else {
            content
                .safeAreaInset(edge: .top, spacing: 0) { pinnedHeader }
                .safeAreaInset(edge: .bottom, spacing: 0) { pinnedSearch }
        }
    }

    private var pinnedHeader: some View {
        VStack(spacing: 8) {
            header
            if searching { searchField }
            if importing {
                ProgressView(value: Double(installProgress))
                    .padding(.horizontal, 24)
            }
        }
        .padding(.bottom, 8)
    }

    /// Search and installation progress remain in the pinned control region.
    /// The title is deliberately excluded so blur begins at the button row.
    private var pinnedControls: some View {
        VStack(spacing: 8) {
            pinnedActionBar
            if searching { searchField }
            if importing {
                ProgressView(value: Double(installProgress))
                    .padding(.horizontal, 24)
            }
        }
        .padding(.bottom, 8)
    }

    @ViewBuilder private var pinnedSearch: some View {
        if !searching {
            Button { animate { searching = true }; searchFocused = true } label: {
                Label("lcos.home.search".loc, systemImage: "magnifyingglass")
                    .font(.caption.weight(.medium))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .lcGlass(in: Capsule(), interactive: true)
            }
            .buttonStyle(.plain)
            .padding(.bottom, 12)
        }
    }

    /// Outside the glass boundary: keeps the iPhone page title crisp even
    /// when a long grid scrolls underneath the action row.
    private var pinnedTitle: some View {
        Text("lc.appList.myApps".loc)
            .font(.title2.weight(.bold))
            .frame(maxWidth: .infinity)
            .accessibilityAddTraits(.isHeader)
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 8)
            .background(Color(uiColor: .systemBackground))
    }

    /// The pinned top actions, and only the actions, receive the iOS 26
    /// native soft edge effect. No material rectangle or custom fade.
    private var pinnedActionBar: some View {
        LCGlassGroup {
                HStack(spacing: 12) {
                    Spacer(minLength: 0)
                    if editing {
                        Button("lcos.home.done".loc) { finishEditing() }
                            .accessibilityIdentifier("lifecontainer.editDone")
                            .font(.body.weight(.semibold))
                            .padding(.horizontal, 16)
                            .frame(minHeight: 44)
                            .lcGlass(in: Capsule(), interactive: true)
                    } else {
                        if shared.multiLCStatus != 2 {
                            Menu {
                                Button("lc.appList.installFromIpa".loc, action: importIPA)
                                Button("lc.appList.installFromUrl".loc, action: importURL)
                            } label: { chromeIcon("plus") }
                                .lcFixedInstallOrder()
                                .disabled(importing)
                                .accessibilityLabel("lc.appList.installFromIpa".loc)
                        }
                        if let openSideStore {
                            Button(action: openSideStore) {
                                IconImageView(icon: BuiltInSideStoreAppInfo.shared.iconIsDarkIcon(scheme == .dark))
                                    .frame(width: 22, height: 22)
                                    .frame(width: 44, height: 44)
                                    .lcGlass(in: Circle(), interactive: true)
                            }.accessibilityLabel("SideStore")
                        }
                        Menu {
                            Toggle("lcos.home.enabled".loc, isOn: $gridEnabled)
                            Button("lcos.home.edit".loc) { startEditing() }
                            Button("lcos.home.list".loc) { gridEnabled = false }
                            Button("lc.appList.openLink".loc, action: openLink)
                            if let openSideStore { Button("SideStore", action: openSideStore) }
                            Button("lcos.home.reset".loc) { resetConfirmation = true }
                        } label: { chromeIcon("ellipsis") }
                            .accessibilityLabel("lcos.home.options".loc)
                    }
                }.buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 8)
    }

    /// Reuse the exact same controls in legacy iOS and on iPad. No duplicate
    /// button implementations that can diverge when actions are added.
    private var header: some View {
        VStack(spacing: 0) {
            pinnedTitle
            pinnedActionBar
        }
    }
    private func chromeIcon(_ name: String) -> some View {
        Image(systemName: name).font(.system(size: 18, weight: .medium)).frame(width: 44, height: 44)
            .lcGlass(in: Circle(), interactive: true)
    }
    private var searchField: some View {
        HStack {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("lcos.home.search".loc, text: $query)
                .textInputAutocapitalization(.never)
                .disableAutocorrection(true)
                .focused($searchFocused)
                // The pinned search bar enters the hierarchy after the
                // initial tap. Focus it on insertion, not in the same
                // transaction as the button that creates the TextField.
                .onAppear { searchFocused = true }
            Button { query = ""; animate { searching = false }; searchFocused = false } label: {
                Image(systemName: "xmark.circle.fill")
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }.accessibilityLabel("lc.common.cancel".loc)
        }.padding(.leading, 16).padding(.trailing, 4).padding(.vertical, 4)
            .lcGlass(in: RoundedRectangle(cornerRadius: 20)).padding(.horizontal, 20)
    }
    private var emptyState: some View {
        VStack(spacing: 18) {
            Image(systemName: "square.grid.2x2").font(.system(size: 40, weight: .light))
            Text("lcos.home.emptyTitle".loc).font(.title2.weight(.semibold))
            Text("lcos.home.emptyBody".loc).foregroundStyle(.secondary).multilineTextAlignment(.center)
            if shared.multiLCStatus != 2 { Button("lc.appList.installFromIpa".loc, action: importIPA).buttonStyle(.borderedProminent) }
        }.padding(32).frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func finishEditing() {
        commitDrag()
        var transaction = Transaction(animation: nil); transaction.disablesAnimations = true
        withTransaction(transaction) { editing = false }
        clearHover(); edgeTask?.cancel()
    }
    private func startEditing() {
        guard !editing else { return }
        animate { editing = true }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }
    private func clearHover() { hoverTask?.cancel(); hoveredID = nil; folderCandidate = nil }
    private func cancelDrag() {
        if draggedID != nil, let origin = dragOrigin { animate { save(origin.reconciled(available)) } }
        draggedID = nil; dragOrigin = nil
        reorderTarget = nil
        clearHover(); edgeTask?.cancel(); folderExitTask?.cancel()
    }
    private func commitDrag() {
        draggedID = nil; dragOrigin = nil
        reorderTarget = nil
        clearHover(); edgeTask?.cancel(); folderExitTask?.cancel()
    }
    private func blankArea(drop: @escaping () -> Void) -> some View {
        Color.clear.contentShape(Rectangle())
            .onDrop(of: [Self.dragType], delegate: LCHomeEdgeDrop(enter: {}, exit: {}, finish: drop))
    }
    /// One continuous, lazily loaded iPhone/iPad home grid. Root app placement
    /// has no pages; folders retain their own familiar paging interaction.
    private func continuousGrid(_ ids: [String], columns: Int, side: CGFloat,
                                metrics: LCHomeMetrics) -> some View {
        GeometryReader { proxy in
            ScrollView(.vertical, showsIndicators: showScrollIndicator) {
                VStack(spacing: 0) {
                    LazyVGrid(
                        columns: Array(repeating: GridItem(.flexible(), spacing: 10, alignment: .top),
                                       count: columns),
                        spacing: CGFloat(metrics.rowSpacing)
                    ) {
                        ForEach(ids, id: \.self) { id in
                            tile(id, side: side, container: nil)
                        }
                    }
                    .padding(.horizontal, CGFloat(metrics.horizontalInset))
                    // The first/last icon shadow has breathing room: do not
                    // draw a material rectangle over an abruptly clipped row.
                    .padding(.top, 20)
                    .padding(.bottom, 24)
                    blankArea { dropAtGridEnd() }
                        .frame(minHeight: 48, maxHeight: .infinity)
                }
                .frame(minHeight: proxy.size.height, alignment: .top)
                .background(LCHomeBlankPress(
                    perform: { startEditing() },
                    tapped: { if editing { finishEditing() } },
                    enabled: folderID == nil
                ))
            }
            .lcNativeHomeScrollEdges(enabled: edgeFade)
            .accessibilityIdentifier("lifecontainer.homeContinuousGrid")
        }
    }

    private func dropAtGridEnd() {
        guard let source = draggedID else { return }
        var value = layout
        value.moveItem(source, before: nil, available: available)
        animate { save(value) }
        commitDrag()
    }

    /// Existing folder pages use this helper; the root grid does not.
    private func dropAtPageEnd(_ index: Int, perPage: Int, folder: String) {
        guard let source = draggedID,
              let items = layout.folders.first(where: { $0.id == folder })?.apps else { return }
        let destination = items.dropFirst((index + 1) * perPage).first
        var value = layout
        value.moveItem(source, before: destination, in: folder, available: available)
        animate { save(value) }
        commitDrag()
    }
    private func hover(source: String, target: String, center: Bool, container: String?) {
        guard source != target else { return }
        if center, container == nil, available.contains(source) {
            if hoveredID != target {
                clearHover(); hoveredID = target
                hoverTask = Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 650_000_000)
                    guard !Task.isCancelled, draggedID == source, hoveredID == target else { return }
                    animate { folderCandidate = target }
                    if let folder = layout.folders.first(where: { $0.id == target }) { openFolder(folder) }
                    UISelectionFeedbackGenerator().selectionChanged()
                }
            }
        } else {
            clearHover()
            guard reorderTarget != target else { return }
            reorderTarget = target
            var value = layout
            value.moveItem(source, toSlotOf: target, in: container, available: available)
            if value != layout { animate { save(value) } }
        }
    }
    private func completeDrop(target: String, container: String?) {
        guard let source = draggedID else { return }
        var value = layout
        if folderCandidate == target, container == nil {
            _ = value.combine(source, with: target, name: "lcos.home.folder".loc, available: available)
        } else if reorderTarget != target { value.moveItem(source, toSlotOf: target, in: container, available: available) }
        animate { save(value) }; commitDrag()
    }

    private func tile(_ id: String, side: CGFloat, container: String?) -> some View {
        LCHomeDragSource(id: id, iconSide: side, jiggle: editing && !reduceMotion && draggedID != id, content: tileArtwork(id, side: side), begin: {
            startEditing(); dragOrigin = layout; draggedID = id; reorderTarget = nil; clearHover()
        }, end: {
            if draggedID == id { cancelDrag() }
        })
            .frame(height: side + 30)
            .scaleEffect(folderCandidate == id ? 1.13 : 1)
            .opacity(draggedID == id ? 0.28 : 1)
            .contentShape(Rectangle())
            .background {
                if id.hasPrefix("folder:") {
                    GeometryReader { proxy in
                        Color.clear.preference(key: LCHomeFolderFrames.self,
                            value: [id: CGRect(x: proxy.frame(in: .global).midX - side / 2,
                                               y: proxy.frame(in: .global).minY, width: side, height: side)])
                    }
                }
            }
            .onDrop(of: [Self.dragType], delegate: LCHomeDrop(
                dragged: draggedID, target: id, iconSide: side,
                hover: { source, center in hover(source: source, target: id, center: center, container: container) },
                exit: {
                    if hoveredID == id { clearHover() }
                    if reorderTarget == id { reorderTarget = nil }
                },
                finish: { completeDrop(target: id, container: container) }))
            .accessibilityAction(named: Text("lcos.home.edit".loc)) { startEditing() }
            .accessibilityAction(named: Text("lcos.home.moveOut".loc)) {
                guard container != nil else { return }
                var value = layout; value.moveItem(id, before: nil, available: available); save(value)
            }
    }
    @ViewBuilder private func tileArtwork(_ id: String, side: CGFloat) -> some View {
        if let folder = layout.folders.first(where: { $0.id == id }) {
            Button {
                openFolder(folder)
            } label: {
                VStack(spacing: 6) {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 3), count: 3), spacing: 3) {
                        ForEach(Array(folder.apps.prefix(9)), id: \.self) { member in
                            if let app = model(member) {
                                Image(uiImage: app.appInfo.iconIsDarkIcon(scheme == .dark) ?? UIImage()).resizable().scaledToFit()
                                    .clipShape(RoundedRectangle(cornerRadius: 3))
                            }
                        }
                    }.padding(7).frame(width: side, height: side, alignment: .top)
                        .lcGlass(in: RoundedRectangle(cornerRadius: side * 0.235))
                    if showLabels {
                        Text(folder.name).font(.caption2).lineLimit(1).foregroundStyle(.primary)
                    }
                }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }.buttonStyle(.plain)
        } else if let app = model(id) {
            LCAppBanner(appModel: app, delegate: delegate, homeScreen: true,
                        iconSide: side, homeEditing: editing, showLabel: showLabels)
        }
    }

    private func folderOverlay(_ folder: LCHomeLayout.Folder, frame: CGRect, side: CGFloat) -> some View {
        let size = frame.size
        let metrics = LCHomeFolderMetrics(width: size.width, height: size.height, iconSide: side)
        let capacity = metrics.capacity
        let count = max(1, (folder.apps.count + capacity - 1) / capacity)
        let panelWidth = CGFloat(metrics.width)
        let panelHeight = CGFloat(metrics.height)
        let panelCenterY = CGFloat(metrics.centerY)
        let memberSide = CGFloat(metrics.side)
        let origin = folderFrames[folder.id]?.offsetBy(dx: -frame.minX, dy: -frame.minY)
            ?? CGRect(x: size.width / 2 - side / 2, y: size.height / 2 - side / 2, width: side, height: side)
        let progress = reduceMotion ? 1 : folderProgress
        return ZStack {
            Rectangle().fill(.regularMaterial).ignoresSafeArea()
                .opacity(folderProgress).onTapGesture { reverseFolder() }
                .accessibilityLabel("lcos.home.done".loc).accessibilityAddTraits(.isButton)
                .onDrop(of: [Self.dragType], delegate: LCHomeEdgeDrop(enter: {
                    folderExitTask?.cancel()
                    folderExitTask = Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 550_000_000)
                        guard !Task.isCancelled, let id = draggedID, folder.apps.contains(id) else { return }
                        closeFolder()
                    }
                }, exit: { folderExitTask?.cancel() }, finish: {
                    folderExitTask?.cancel()
                    guard let id = draggedID, folder.apps.contains(id) else { return }
                    var value = layout; value.moveItem(id, before: nil, available: available)
                    animate { save(value) }; closeFolder(); commitDrag()
                }))
            TextField("lcos.home.folder".loc, text: $folderName).font(metrics.compact ? .title2.weight(.semibold) : .largeTitle.weight(.semibold))
                .multilineTextAlignment(.center).submitLabel(.done).onSubmit { rename(folder.id) }
                .frame(width: panelWidth).position(x: size.width / 2, y: metrics.compact ? 22 : panelCenterY - panelHeight / 2 - 46)
                .opacity(folderProgress)
            if editing {
                Button("lcos.home.done".loc) { finishEditing() }
                        .accessibilityIdentifier("lifecontainer.editDone")
                    .font(.body.weight(.semibold)).padding(.horizontal, 16).frame(height: 44)
                    .lcGlass(in: Capsule(), interactive: true)
                    .position(x: size.width - 68, y: 28).opacity(folderProgress)
            }
                TabView(selection: $folderPage) {
                    ForEach(0..<count, id: \.self) { index in
                        VStack(spacing: 0) {
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: metrics.columns), spacing: CGFloat(metrics.spacing)) {
                            ForEach(Array(folder.apps.dropFirst(index * capacity).prefix(capacity)), id: \.self) { id in
                                tile(id, side: memberSide, container: folder.id)
                                    .contextMenu {
                                        if !editing {
                                        Button("lcos.home.moveOut".loc) {
                                            var value = layout; value.moveItem(id, before: nil, available: available)
                                            animate { save(value) }
                                        }
                                        }
                                    }
                            }
                        }.padding(.horizontal, 24).padding(.top, CGFloat(metrics.inset))
                        blankArea { dropAtPageEnd(index, perPage: capacity, folder: folder.id) }
                            .frame(minHeight: 24, maxHeight: .infinity)
                        }.frame(maxHeight: .infinity, alignment: .top)
                            .background(LCHomeBlankPress(perform: { startEditing() }, tapped: { if editing { finishEditing() } })).tag(index)
                    }
                }.tabViewStyle(.page(indexDisplayMode: .never))
                .overlay(alignment: .leading) { pageEdge(-1, count: count, perPage: capacity, folder: folder.id) }
                .overlay(alignment: .trailing) { pageEdge(1, count: count, perPage: capacity, folder: folder.id) }
                .frame(width: panelWidth, height: panelHeight)
                .lcGlass(in: RoundedRectangle(cornerRadius: 38))
                .allowsHitTesting(!folderAnimating || draggedID != nil)
                .onDrop(of: [Self.dragType], delegate: LCHomeEdgeDrop(enter: {}, exit: {}, finish: {
                    dropAtPageEnd(folderPage, perPage: capacity, folder: folder.id)
                }))
                .scaleEffect(x: (side / panelWidth + (1 - side / panelWidth) * progress) * folderPinch,
                             y: (side / panelHeight + (1 - side / panelHeight) * progress) * folderPinch)
                .position(x: size.width / 2 + (origin.midX - size.width / 2) * (1 - progress),
                          y: panelCenterY + (origin.midY - panelCenterY) * (1 - progress))
                .opacity(folderProgress)
                .animation(reduceMotion ? nil : .interactiveSpring(response: 0.3, dampingFraction: 0.86), value: folderPinch)
                if count > 1 {
                    pageDots(count, selection: $folderPage)
                        .position(x: size.width / 2, y: panelCenterY + panelHeight / 2 + (metrics.compact ? 16 : 32)).opacity(folderProgress)
                }
                if editing && !metrics.compact {
                    Text("lcos.home.folderDragHint".loc).font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                        .frame(width: panelWidth).position(x: size.width / 2, y: panelCenterY + panelHeight / 2 + 70).opacity(folderProgress)
                }
        }
        .frame(width: size.width, height: size.height)
        .onAppear { folderCapacity = capacity; transitionFolder(open: true) }
        .onChange(of: capacity) { value in folderCapacity = value; folderPage = min(folderPage, count - 1) }
        .onChange(of: count) { folderPage = min(folderPage, $0 - 1) }
        .accessibilityAction(.escape) { closeFolder() }
        .simultaneousGesture(MagnificationGesture()
            .updating($folderPinch) { value, state, _ in state = reduceMotion ? 1 : min(1, max(0.7, value)) }
            .onEnded { if $0 < 0.85 { closeFolder() } })
    }
    private func rename(_ id: String) { var value = layout; value.renameFolder(id, name: folderName); save(value) }
    private func openFolder(_ folder: LCHomeLayout.Folder) {
        folderCloseTask?.cancel()
        folderName = folder.name; folderPage = 0; folderProgress = 0
        folderTargetOpen = true; folderAnimating = true
        folderID = folder.id
    }
    private func closeFolder() {
        guard let id = folderID else { return }
        rename(id); clearHover(); folderExitTask?.cancel(); folderCloseTask?.cancel()
        transitionFolder(open: false)
    }
    private func reverseFolder() {
        if folderTargetOpen { closeFolder() } else { transitionFolder(open: true) }
    }
    private func transitionFolder(open: Bool) {
        guard let id = folderID else { return }
        folderCloseTask?.cancel()
        folderTargetOpen = open; folderAnimating = true
        animateFolder { folderProgress = open ? 1 : 0 }
        folderCloseTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: reduceMotion ? 150_000_000 : 420_000_000)
            guard !Task.isCancelled, folderID == id else { return }
            folderAnimating = false
            if !open { folderID = nil }
        }
    }
    private func pageDots(_ count: Int, selection: Binding<Int>) -> some View {
        HStack(spacing: 8) {
            ForEach(0..<count, id: \.self) { index in
                Button { withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.32)) { selection.wrappedValue = index } } label: {
                    Circle()
                        .fill(Color.primary.opacity(selection.wrappedValue == index ? 0.8 : 0.22))
                        .frame(width: 6, height: 6)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }.accessibilityLabel("lcos.home.page".localizeWithFormat(index + 1))
            }
        }.buttonStyle(.plain)
    }
    private func pageEdge(_ direction: Int, count: Int, perPage: Int, folder: String) -> some View {
        Color.clear.frame(width: 24).contentShape(Rectangle())
            .allowsHitTesting(draggedID != nil)
            .onDrop(of: [Self.dragType], delegate: LCHomeEdgeDrop(enter: {
                edgeTask?.cancel()
                edgeTask = Task { @MainActor in
                    while !Task.isCancelled, draggedID != nil {
                        try? await Task.sleep(nanoseconds: 700_000_000)
                        guard !Task.isCancelled else { return }
                        let next = min(max(folderPage + direction, 0), count - 1)
                        guard next != folderPage else { return }
                        withAnimation(homeAnimation) { folderPage = next }
                        UISelectionFeedbackGenerator().selectionChanged()
                    }
                }
            }, exit: { edgeTask?.cancel() }, finish: {
                dropAtPageEnd(folderPage, perPage: perPage, folder: folder)
            }))
    }

}

private struct LCHomeFolderFrames: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, latest in latest })
    }
}

private struct LCHomeDrop: DropDelegate {
    let dragged: String?
    let target: String
    let iconSide: CGFloat
    let hover: (String, Bool) -> Void
    let exit: () -> Void
    let finish: () -> Void
    func validateDrop(info: DropInfo) -> Bool { dragged != nil }
    func dropUpdated(info: DropInfo) -> DropProposal? {
        if let dragged, dragged != target {
            hover(dragged, info.location.y > 8 && info.location.y < iconSide - 8 && info.location.x > 20 && info.location.x < iconSide - 4)
        }
        return DropProposal(operation: .move)
    }
    func dropExited(info: DropInfo) { exit() }
    func performDrop(info: DropInfo) -> Bool { guard dragged != nil else { return false }; finish(); return true }
}
private struct LCHomeEdgeDrop: DropDelegate {
    let enter: () -> Void
    let exit: () -> Void
    let finish: () -> Void
    func dropEntered(info: DropInfo) { enter() }
    func dropExited(info: DropInfo) { exit() }
    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }
    func performDrop(info: DropInfo) -> Bool { finish(); return true }
}
