//
//  LCTweaksView.swift
//  LiveContainerSwiftUI
//
//  Created by s s on 2024/8/21.
//

import Foundation
import SwiftUI
import UniformTypeIdentifiers

struct LCTweakItem : Hashable {
    let fileUrl: URL
    let isFolder: Bool
    let isFramework: Bool
    let isTweak: Bool
    let isEnabled: Bool

    var displayName: String {
        let name = fileUrl.lastPathComponent
        return isEnabled ? name : String(name.dropLast(LCTweakItem.disabledSuffix.count))
    }

    static let disabledSuffix = ".disabled"
}

struct LCTweakFolderView : View {
    @State var baseUrl : URL
    @State var tweakItems : [LCTweakItem]
    private var isRoot : Bool
    @EnvironmentObject private var sharedModel: SharedModel
    
    @State private var errorShow = false
    @State private var errorInfo = ""
    
    @StateObject private var newFolderInput = InputHelper()
    
    @StateObject private var renameFileInput = InputHelper()
    
    @State private var choosingTweak = false
    
    @State private var isTweakSigning = false
    
    init(baseUrl: URL, isRoot: Bool = false) {
        _baseUrl = State(initialValue: baseUrl)
        self.isRoot = isRoot
        var tmpTweakItems : [LCTweakItem] = []
        let fm = FileManager()
        do {
            let files = try fm.contentsOfDirectory(atPath: baseUrl.path)
            for fileName in files {
                let fileUrl = baseUrl.appendingPathComponent(fileName)
                var isFolder : ObjCBool = false
                fm.fileExists(atPath: fileUrl.path, isDirectory: &isFolder)
                let isEnabled = !fileName.hasSuffix(LCTweakItem.disabledSuffix)
                let baseName = isEnabled ? fileName : String(fileName.dropLast(LCTweakItem.disabledSuffix.count))
                let isFramework = isFolder.boolValue && baseName.hasSuffix(".framework")
                let isTweak = !isFolder.boolValue && baseName.hasSuffix(".dylib")
                tmpTweakItems.append(LCTweakItem(fileUrl: fileUrl, isFolder: isFolder.boolValue, isFramework: isFramework, isTweak: isTweak, isEnabled: isEnabled))
            }
            _tweakItems = State(initialValue: tmpTweakItems)
        } catch {
            NSLog("[LC] failed to load tweaks \(error.localizedDescription)")
            _errorShow = State(initialValue: true)
            _errorInfo = State(initialValue: error.localizedDescription)
            _tweakItems = State(initialValue: [])
        }
    }

    // A single vertical scroll container owns the wide iPad layout. Two sibling
    // Lists each reserve their own navigation-title inset, which caused the title
    // to draw on top of the first card on iPad mini landscape.
    // Use window width (not orientation) so Split View / Stage Manager reflow.
    var body: some View {
        GeometryReader { geometry in
            if isRoot && UIDevice.current.userInterfaceIdiom == .pad &&
                geometry.size.width >= 900 {
                wideRoot(availableWidth: geometry.size.width)
                    .navigationTitle("")
                    .navigationBarTitleDisplayMode(.inline)
            } else {
                List {
                    if isRoot { marketplaceLinks }
                    tweakFiles
                }
                .listStyle(.insetGrouped)
                .navigationTitle(isRoot ? "lc.tabView.tweaks".loc : baseUrl.lastPathComponent)
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if !isTweakSigning && LCSharedUtils.certificatePassword() != nil {
                    Button {
                        Task { await signAllTweaks() }
                    } label: {
                        Label("sign".loc, systemImage: "signature")
                    }
                }

            }
            ToolbarItem(placement: .topBarTrailing) {
                if !isTweakSigning {
                    Menu {
                        Button {
                            if choosingTweak {
                                choosingTweak = false
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: {
                                    choosingTweak = true
                                })
                            } else {
                                choosingTweak = true
                            }
                        } label: {
                            Label("lc.tweakView.importTweak".loc, systemImage: "square.and.arrow.down")
                        }
                        
                        Button {
                            Task { await createNewFolder() }
                        } label: {
                            Label("lc.tweakView.newFolder".loc, systemImage: "folder.badge.plus")
                        }
                    } label: {
                        Label("add", systemImage: "plus")
                    }
                } else {
                    ProgressView().progressViewStyle(.circular)
                }

            }
        }
        .alert("lc.common.error".loc, isPresented: $errorShow) {
            Button("lc.common.ok".loc, action: {
            })
        } message: {
            Text(errorInfo)
        }
        .textFieldAlert(
            isPresented: $newFolderInput.show,
            title: "lc.common.enterNewFolderName".loc,
            text: $newFolderInput.initVal,
            placeholder: "",
            action: { newText in
                newFolderInput.close(result: newText)
            },
            actionCancel: {_ in
                newFolderInput.close(result: "")
            }
        )
        .textFieldAlert(
            isPresented: $renameFileInput.show,
            title: "lc.common.enterNewName".loc,
            text: $renameFileInput.initVal,
            placeholder: "",
            action: { newText in
                renameFileInput.close(result: newText)
            },
            actionCancel: {_ in
                renameFileInput.close(result: "")
            }
        )
        .betterFileImporter(isPresented: $choosingTweak, types: [.dylib, .lcFramework, /*.deb*/], multiple: true, callback: { fileUrls in
            Task { await startInstallTweak(fileUrls) }
        }, onDismiss: {
            choosingTweak = false
        })
    }
    
    // Keep the title in the same scroll coordinate space as both columns.
    // Both card groups begin on one horizontal baseline.
    private func wideRoot(availableWidth: CGFloat) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("lc.tabView.tweaks".loc)
                    .font(.largeTitle.weight(.bold))
                    .frame(maxWidth: .infinity, alignment: .leading)

                HStack(alignment: .top, spacing: 20) {
                    wideMarketplaceLinks
                        .frame(width: min(392, (availableWidth - 68) * 0.39))
                    wideTweakFiles
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 16)
            .padding(.bottom, 30)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .accessibilityIdentifier("lifecontainer.tweaks.adaptive")
    }

    // Navigation and file controls are intentionally independent of the scroll
    // container, not of the navigation title or the safe area.
    private var wideMarketplaceLinks: some View {
        VStack(spacing: 0) {
            NavigationLink {
                LCTweakMarketplace()
            } label: {
                HStack(spacing: 14) {
                    Image(systemName: "shippingbox.fill")
                        .font(.title2)
                        .foregroundStyle(.tint)
                        .frame(width: 34)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("life.market.title".loc).font(.headline)
                        Text("life.market.subtitle".loc)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .frame(minHeight: 80)
                .padding(.horizontal, 18)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Divider().padding(.leading, 66).padding(.trailing, 18)

            NavigationLink {
                LCDebPackageView()
            } label: {
                HStack(spacing: 14) {
                    Image(systemName: "shippingbox")
                        .font(.title2)
                        .foregroundStyle(.tint)
                        .frame(width: 34)
                    Text("life.deb.title".loc).font(.body)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .frame(minHeight: 58)
                .padding(.horizontal, 18)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .background(Color(uiColor: .secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 22))
    }

    private var wideTweakFiles: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(spacing: 0) {
                ForEach(tweakItems.indices, id: \.self) { index in
                    if index > 0 {
                        Divider().padding(.leading, 58).padding(.trailing, 18)
                    }
                    tweakRow(tweakItems[index])
                        .frame(minHeight: 58)
                        .padding(.horizontal, 18)
                        .contentShape(Rectangle())
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(uiColor: .secondarySystemGroupedBackground),
                        in: RoundedRectangle(cornerRadius: 22))

            Text("lc.tweakView.globalFolderDesc".loc)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 16)
        }
    }

    // Reuse the same file row in the native List and in the wide iPad card.
    // Its toggle, folder navigation, rename and delete actions stay identical.
    private func tweakRow(_ tweakItem: LCTweakItem) -> some View {
                HStack {
                    Group {
                        if tweakItem.isFolder && !tweakItem.isFramework {
                            // An explicit link works both in native Lists and
                            // in the wide ScrollView card. The separate Toggle
                            // remains independently tappable.
                            NavigationLink {
                                LCTweakFolderView(baseUrl: tweakItem.fileUrl, isRoot: false)
                            } label: {
                                HStack {
                                    Label(tweakItem.displayName, systemImage: "folder.fill")
                                    Spacer()
                                    Image(systemName: "chevron.forward")
                                        .font(.footnote.weight(.semibold))
                                        .foregroundColor(.secondary)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        } else if tweakItem.isFramework {
                            Label(tweakItem.displayName, systemImage: "shippingbox.fill")
                            Spacer()
                        } else if tweakItem.isTweak {
                            Label(tweakItem.displayName, systemImage: "building.columns.fill")
                            Spacer()
                        } else {
                            Label(tweakItem.displayName, systemImage: "document.fill")
                            Spacer()
                        }
                    }
                    .opacity(tweakItem.isEnabled ? 1 : 0.4)
                    if tweakItem.displayName != "TweakLoader.dylib" {
                        Toggle("", isOn: Binding(
                            get: { tweakItem.isEnabled },
                            set: { setTweakEnabled(tweakItem: tweakItem, enabled: $0) }
                        ))
                        .labelsHidden()
                    }
                }
                .contextMenu {
                    Button {
                        Task { await renameTweakItem(tweakItem: tweakItem)}
                    } label: {
                        Label("lc.common.rename".loc, systemImage: "pencil")
                    }
        
                    Button(role: .destructive) {
                        deleteTweakItem(tweakItem: tweakItem)
                    } label: {
                        Label("lc.common.delete".loc, systemImage: "trash")
                    }
                }
    }

    @ViewBuilder
    private var marketplaceLinks: some View {
        Section {
            NavigationLink {
                LCTweakMarketplace()
            } label: {
                HStack(spacing: 14) {
                    Image(systemName: "shippingbox.fill").font(.title).foregroundStyle(.tint)
                        .frame(width: 52, height: 52)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("life.market.title".loc).font(.headline)
                        Text("life.market.subtitle".loc).font(.caption).foregroundStyle(.secondary)
                    }
                }.padding(.vertical, 8)
            }
            NavigationLink {
                LCDebPackageView()
            } label: {
                Label("life.deb.title".loc, systemImage: "shippingbox")
            }
        }
    }

    @ViewBuilder
    private var tweakFiles: some View {
        Section {
            ForEach(tweakItems, id: \.self) { tweakItem in
                tweakRow(tweakItem)
            }.onDelete { indexSet in
                deleteTweakItem(indexSet: indexSet)
            }
        } footer: {
            if isRoot {
                Text("lc.tweakView.globalFolderDesc".loc)
                    .foregroundStyle(.gray)
                    .font(.system(size: 12))
            } else {
                Text("lc.tweakView.appFolderDesc".loc)
                    .foregroundStyle(.gray)
                    .font(.system(size: 12))
            }
        }
    }

    func setTweakEnabled(tweakItem: LCTweakItem, enabled: Bool) {
        if tweakItem.isEnabled == enabled {
            return
        }
        let displayName = tweakItem.displayName
        let newName = enabled ? displayName : displayName + LCTweakItem.disabledSuffix
        let newUrl = baseUrl.appendingPathComponent(newName)
        let fm = FileManager()
        do {
            try fm.moveItem(at: tweakItem.fileUrl, to: newUrl)
        } catch {
            errorShow = true
            errorInfo = error.localizedDescription
            return
        }
        guard let index = tweakItems.firstIndex(of: tweakItem) else {
            return
        }
        tweakItems[index] = LCTweakItem(fileUrl: newUrl, isFolder: tweakItem.isFolder, isFramework: tweakItem.isFramework, isTweak: tweakItem.isTweak, isEnabled: enabled)
    }

    func deleteTweakItem(indexSet: IndexSet) {
        var indexToRemove : [Int] = []
        let fm = FileManager()
        do {
            for i in indexSet {
                let tweakItem = tweakItems[i]
                try fm.removeItem(at: tweakItem.fileUrl)
                indexToRemove.append(i)
            }
        } catch {
            errorShow = true
            errorInfo = error.localizedDescription
            return
        }
        if isRoot {
            for iToRemove in indexToRemove {
                sharedModel.tweakFolderNames.removeAll(where: { s in
                    return s == tweakItems[iToRemove].displayName
                })
            }
        }

        tweakItems.remove(atOffsets: IndexSet(indexToRemove))
    }

    func deleteTweakItem(tweakItem: LCTweakItem) {
        var indexToRemove : Int?
        let fm = FileManager()
        do {

            try fm.removeItem(at: tweakItem.fileUrl)
            indexToRemove = tweakItems.firstIndex(where: { s in
                return s == tweakItem
            })
        } catch {
            errorShow = true
            errorInfo = error.localizedDescription
            return
        }

        guard let indexToRemove = indexToRemove else {
            return
        }
        tweakItems.remove(at: indexToRemove)
        if isRoot {
            sharedModel.tweakFolderNames.removeAll(where: { s in
                return s == tweakItem.displayName
            })
        }
    }
    
    func renameTweakItem(tweakItem: LCTweakItem) async {
        guard let newName = await renameFileInput.open(initVal: tweakItem.displayName), newName != "" else {
            return
        }

        let indexToRename = tweakItems.firstIndex(where: { s in
            return s == tweakItem
        })
        guard let indexToRename = indexToRename else {
            return
        }
        let newFileName = tweakItem.isEnabled ? newName : newName + LCTweakItem.disabledSuffix
        let newUrl = self.baseUrl.appendingPathComponent(newFileName)

        let fm = FileManager()
        do {
            try fm.moveItem(at: tweakItem.fileUrl, to: newUrl)
        } catch {
            errorShow = true
            errorInfo = error.localizedDescription
            return
        }
        tweakItems.remove(at: indexToRename)
        let newTweakItem = LCTweakItem(fileUrl: newUrl, isFolder: tweakItem.isFolder, isFramework: tweakItem.isFramework, isTweak: tweakItem.isTweak, isEnabled: tweakItem.isEnabled)
        tweakItems.insert(newTweakItem, at: indexToRename)

        if isRoot {
            let indexToRename2 = sharedModel.tweakFolderNames.firstIndex(of: tweakItem.displayName)
            guard let indexToRename2 = indexToRename2 else {
                return
            }
            sharedModel.tweakFolderNames.remove(at: indexToRename2)
            sharedModel.tweakFolderNames.insert(newName, at: indexToRename2)

        }
    }
    
    func signAllTweaks() async {
        do {
            defer {
                isTweakSigning = false
            }
            
            try await LCUtils.signTweaks(tweakFolderUrl: self.baseUrl, force: true) { p in
                isTweakSigning = true
            }

        } catch {
            errorInfo = error.localizedDescription
            errorShow = true
            return
        }
    }
    
    func createNewFolder() async {
        guard let newName = await renameFileInput.open(), newName != "" else {
            return
        }
        let fm = FileManager()
        let dest = baseUrl.appendingPathComponent(newName)
        do {
            try fm.createDirectory(at: dest, withIntermediateDirectories: false)
        } catch {
            errorShow = true
            errorInfo = error.localizedDescription
            return
        }
        tweakItems.append(LCTweakItem(fileUrl: dest, isFolder: true, isFramework: false, isTweak: false, isEnabled: true))
        if isRoot {
            sharedModel.tweakFolderNames.append(newName)
        }
    }
    
    func startInstallTweak(_ urls: [URL]) async {
        do {
            let fm = FileManager()
            // we will sign later before app launch
            
            for fileUrl in urls {
                // handle deb file
                if(!fileUrl.isFileURL) {
                    throw "lc.tweakView.notFileError %@".localizeWithFormat(fileUrl.lastPathComponent)
                }
                let toPath = self.baseUrl.appendingPathComponent(fileUrl.lastPathComponent)
                try fm.moveItem(at: fileUrl, to: toPath)
                LCParseMachO((toPath.path as NSString).utf8String, false) { path, header, _, _ in
                    LCPatchAddRPath(path, header);
                }

                let isFramework = toPath.lastPathComponent.hasSuffix(".framework")
                let isTweak = toPath.lastPathComponent.hasSuffix(".dylib")
                self.tweakItems.append(LCTweakItem(fileUrl: toPath, isFolder: false, isFramework: isFramework, isTweak: isTweak, isEnabled: true))
            }
        } catch {
            errorInfo = error.localizedDescription
            errorShow = true            
            return
        }
    }
}

struct LCTweaksView: View {
    var body: some View {
        NavigationView {
            LCTweakFolderView(baseUrl: LCPath.tweakPath, isRoot: true)
        }
        .navigationViewStyle(StackNavigationViewStyle())

    }
}
