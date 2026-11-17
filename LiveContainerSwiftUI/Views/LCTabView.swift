//
//  TabView.swift
//  LiveContainerSwiftUI
//
//  Created by s s on 2024/8/21.
//

import Foundation
import SwiftUI

// The iPadOS 26 tab bar occupies the top row. The desktop's actions live
// alongside it instead of reserving a second row inside the Apps page.
extension Notification.Name {
    static let lcosTopBarImportIPA = Notification.Name("lcosTopBarImportIPA")
    static let lcosTopBarImportURL = Notification.Name("lcosTopBarImportURL")
    static let lcosTopBarOpenSideStore = Notification.Name("lcosTopBarOpenSideStore")
    static let lcosTopBarOpenLink = Notification.Name("lcosTopBarOpenLink")
    static let lcosTopBarEdit = Notification.Name("lcosTopBarEdit")
    static let lcosTopBarDone = Notification.Name("lcosTopBarDone")
    static let lcosTopBarReset = Notification.Name("lcosTopBarReset")
    static let lcosTopBarEditingChanged = Notification.Name("lcosTopBarEditingChanged")
}

struct LCTabView: View {
    @AppStorage("LCOSHomeScreenEnabled", store: LCUtils.appGroupUserDefault) private var homeScreenEnabled = true
    @State private var homeScreenEditing = false
    @Environment(\.colorScheme) private var colorScheme
    @State var errorShow = false
    @State var crashReportShow = false
    @State var errorInfo = ""

    @EnvironmentObject var sharedModel : SharedModel
    @EnvironmentObject var sceneDelegate: SceneDelegate
    @State var shouldToggleMainWindowOpen = false
    @Environment(\.scenePhase) var scenePhase
    @StateObject var downloadHelper = DownloadHelper()

    let pub = NotificationCenter.default.publisher(for: UIScene.didDisconnectNotification)

    var body: some View {
        tabContent
        // Do not force an edge blur on every nested Form/List or the tab bar.
        // Let UIKit/SwiftUI render each navigation and tab bar natively.
        .overlay(alignment: .topTrailing) { floatingHomeActions }
        .onReceive(NotificationCenter.default.publisher(for: .lcosTopBarEditingChanged)) { note in
            homeScreenEditing = note.object as? Bool ?? false
        }
        .onChange(of: sharedModel.selectedTab) { tab in
            if tab != .apps { homeScreenEditing = false }
        }
        .onChange(of: homeScreenEnabled) { enabled in
            if !enabled { homeScreenEditing = false }
        }
        .downloadAlert(helper: downloadHelper)
        .environmentObject(downloadHelper)
        .alert("lc.common.error".loc, isPresented: $errorShow){
            Button("lc.common.ok".loc, action: {
            })
            Button("lc.common.copy".loc, action: {
                copyError()
            })
        } message: {
            Text(errorInfo)
        }
        .sheet(isPresented: $crashReportShow) {
            NavigationView {
                ScrollView {
                    Text(errorInfo)
                        .font(.system(size: 12).monospaced())
                        .fixedSize(horizontal: false, vertical: false)
                        .textSelection(.enabled)
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        if #available(iOS 16.0, *) {
                            if let log = UserDefaults.lcShared().url(forKey: "LC32BitTranslationLayerLogFile") {
                                ShareLink(item: log)
                            } else {
                                ShareLink(item: errorInfo)
                            }
                        } else {
                            Button("lc.common.copy".loc) {
                                copyError()
                            }
                        }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("lc.common.ok".loc, action: {
                            crashReportShow = false
                        })
                    }
                }
                .navigationTitle("lc.common.error".loc)
                .navigationBarTitleDisplayMode(.inline)
            }
        }
        .task {
            closeDuplicatedWindow()
            checkLastLaunchError()
            checkTeamId()
            checkAndSaveBundleId()
            checkGetTaskAllow()
            checkPrivateContainerBookmark()
        }
        .onReceive(pub) { out in
            if let scene1 = sceneDelegate.window?.windowScene, let scene2 = out.object as? UIWindowScene, scene1 == scene2 {
                if shouldToggleMainWindowOpen {
                    DataManager.shared.model.mainWindowOpened = false
                }
            }
        }
        .onOpenURL { url in
            dispatchURL(url: url)
        }
    }

    private var tabContent: some View {
        TabView(selection: $sharedModel.selectedTab) {
            if DataManager.shared.model.multiLCStatus != 2 {
                LCSourcesView()
                    .tabItem {
                        Label("lc.tabView.sources".loc, systemImage: "books.vertical")
                    }
                    .tag(LCTabIdentifier.sources)
            }
            LCAppListView()
                .tabItem {
                    Label("lc.tabView.apps".loc, systemImage: "square.stack.3d.up.fill")
                }
                .tag(LCTabIdentifier.apps)
            if DataManager.shared.model.multiLCStatus != 2 {
                LCTweaksView()
                    .tabItem{
                        Label("lc.tabView.tweaks".loc, systemImage: "wrench.and.screwdriver")
                    }
                    .tag(LCTabIdentifier.tweaks)
            }

            LCSettingsView()
                .tabItem {
                    Label("lc.tabView.settings".loc, systemImage: "gearshape.fill")
                }
                .tag(LCTabIdentifier.settings)
        }
        .apply { content in
            if #available(iOS 16.0, *) {
                content.toolbar(.visible, for: .tabBar)
            } else { content }
        }
    }

    // On iPadOS 26+ the system draws the centered tab strip at the top.
    // Overlay these actions in the same top safe-area row, keeping all existing
    // install, SideStore and desktop menu behavior in their owning views.
    @ViewBuilder
    private var floatingHomeActions: some View {
        if #available(iOS 26.0, *) {
            if UIDevice.current.userInterfaceIdiom == .pad &&
                homeScreenEnabled && sharedModel.selectedTab == .apps {
                LCGlassGroup {
                    HStack(spacing: 12) {
                        if homeScreenEditing {
                            Button {
                                NotificationCenter.default.post(name: .lcosTopBarDone, object: nil)
                            } label: {
                                Text("lcos.home.done".loc)
                                    .font(.body.weight(.semibold))
                                    .padding(.horizontal, 16)
                                    .frame(height: 44)
                                    .lcGlass(in: Capsule(), interactive: true)
                            }.accessibilityIdentifier("lifecontainer.editDone")
                        } else {
                            if sharedModel.multiLCStatus != 2 {
                                Menu {
                                    Button("lc.appList.installFromIpa".loc) {
                                        NotificationCenter.default.post(name: .lcosTopBarImportIPA, object: nil)
                                    }
                                    Button("lc.appList.installFromUrl".loc) {
                                        NotificationCenter.default.post(name: .lcosTopBarImportURL, object: nil)
                                    }
                                } label: { topActionIcon("plus") }
                                .lcFixedInstallOrder()
                                .accessibilityLabel("lc.appList.installFromIpa".loc)
                            }
                            if UserDefaults.sideStoreExist() {
                                Button {
                                    NotificationCenter.default.post(name: .lcosTopBarOpenSideStore, object: nil)
                                } label: {
                                    IconImageView(icon: BuiltInSideStoreAppInfo.shared.iconIsDarkIcon(colorScheme == .dark))
                                        .frame(width: 22, height: 22)
                                        .frame(width: 44, height: 44)
                                        .lcGlass(in: Circle(), interactive: true)
                                }.accessibilityLabel("SideStore")
                            }
                            Menu {
                                Toggle("lcos.home.enabled".loc, isOn: $homeScreenEnabled)
                                Button("lcos.home.edit".loc) {
                                    NotificationCenter.default.post(name: .lcosTopBarEdit, object: nil)
                                }
                                Button("lcos.home.list".loc) { homeScreenEnabled = false }
                                Button("lc.appList.openLink".loc) {
                                    NotificationCenter.default.post(name: .lcosTopBarOpenLink, object: nil)
                                }
                                if UserDefaults.sideStoreExist() {
                                    Button("SideStore") {
                                        NotificationCenter.default.post(name: .lcosTopBarOpenSideStore, object: nil)
                                    }
                                }
                                Button("lcos.home.reset".loc) {
                                    NotificationCenter.default.post(name: .lcosTopBarReset, object: nil)
                                }
                            } label: { topActionIcon("ellipsis") }
                                .accessibilityLabel("lcos.home.options".loc)
                        }
                    }.buttonStyle(.plain)
                }
                .padding(.trailing, 20)
                .padding(.top, 6)
            }
        }
    }

    private func topActionIcon(_ symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 18, weight: .medium))
            .frame(width: 44, height: 44)
            .lcGlass(in: Circle(), interactive: true)
    }

    func dispatchURL(url: URL) {
        repeat {
            if url.isFileURL {
                sharedModel.selectedTab = .apps
                break
            }
            if url.scheme?.lowercased() == "sidestore" {
                sharedModel.selectedTab = .apps
                break
            }

            guard let host = url.host?.lowercased() else {
                return
            }

            switch host {
            case "livecontainer-launch", "install", "open-web-page", "open-url":
                sharedModel.selectedTab = .apps
            case "certificate":
                sharedModel.selectedTab = .settings
            case "source":
                sharedModel.selectedTab = .sources
            default:
                return
            }

        } while(false)

        sharedModel.deepLink = url
    }

    func closeDuplicatedWindow() {
        if let session = sceneDelegate.window?.windowScene?.session, DataManager.shared.model.mainWindowOpened {
            UIApplication.shared.requestSceneSessionDestruction(session, options: nil) { e in
                print(e)
            }
        } else {
            shouldToggleMainWindowOpen = true
        }
        DataManager.shared.model.mainWindowOpened = true
    }

    func checkLastLaunchError() {
        var errorStr = UserDefaults.standard.string(forKey: "error")

        if errorStr == nil && UserDefaults.standard.bool(forKey: "SigningInProgress") {
            errorStr = "lc.signer.crashDuringSignErr".loc
            UserDefaults.standard.removeObject(forKey: "SigningInProgress")
        }

        guard let errorStr else {
            return
        }
        UserDefaults.standard.removeObject(forKey: "error")
        SigningDiagnostics.record("previousLaunch.exception", errorStr, level: "error")
        errorInfo = errorStr
        crashReportShow = true
    }

    func copyError() {
        UIPasteboard.general.string = errorInfo
    }

    func checkTeamId() {
        if let certificateTeamId = UserDefaults.standard.string(forKey: "LCCertificateTeamId") {
            if DataManager.shared.model.multiLCStatus != 2 {
                return
            }

            guard let primaryLCTeamId = Bundle.main.infoDictionary?["PrimaryLiveContainerTeamId"] as? String else {
                print("Unable to find PrimaryLiveContainerTeamId")
                return
            }
            if certificateTeamId != primaryLCTeamId {
                errorInfo = "lc.settings.multiLC.teamIdMismatch".loc
                errorShow = true
                return
            }
            return
        }

        guard let currentTeamId = LCSharedUtils.teamIdentifier() else {
            print("Failed to determine team id.")
            return
        }

        if DataManager.shared.model.multiLCStatus == 2 {
            guard let primaryLCTeamId = Bundle.main.infoDictionary?["PrimaryLiveContainerTeamId"] as? String else {
                print("Unable to find PrimaryLiveContainerTeamId")
                return
            }
            if currentTeamId != primaryLCTeamId {
                errorInfo = "lc.settings.multiLC.teamIdMismatch".loc
                errorShow = true
                return
            }
        }
        UserDefaults.standard.set(currentTeamId, forKey: "LCCertificateTeamId")
    }

    func checkAndSaveBundleId() {
        if DataManager.shared.model.multiLCStatus == 2 {
            let scheme = UserDefaults.lcAppUrlScheme() ?? ""
            LCUtils.appGroupUserDefault.set(Bundle.main.bundleIdentifier, forKey: "LCBundleID.\(scheme)")
        }

        if UserDefaults.standard.bool(forKey: "LCBundleIdChecked") {
            return
        }

        let task = SecTaskCreateFromSelf(nil)
        guard let value = SecTaskCopyValueForEntitlement(task, "application-identifier" as CFString, nil), let appIdentifier = value.takeRetainedValue() as? String else {
            errorInfo = "Unable to determine application-identifier"
            errorShow = true
            return
        }

        guard let bundleId = Bundle.main.bundleIdentifier else {
            return
        }

        var correctBundleId = ""
        if appIdentifier.count > 11 {
            let startIndex = appIdentifier.index(appIdentifier.startIndex, offsetBy: 11)
            correctBundleId = String(appIdentifier[startIndex...])
        }

        if(bundleId != correctBundleId) {
            errorInfo = "lc.settings.bundleIdMismatch %@ %@".localizeWithFormat(bundleId, correctBundleId)
            errorShow = true
        }
        UserDefaults.standard.set(true, forKey: "LCBundleIdChecked")
    }

    func checkGetTaskAllow() {
        let task = SecTaskCreateFromSelf(nil)
        guard let value = SecTaskCopyValueForEntitlement(task, "get-task-allow" as CFString, nil), (value.takeRetainedValue() as? NSNumber)?.boolValue ?? false else {
            errorInfo = "lc.settings.notDevCert".loc
            errorShow = true
            return
        }
    }

    func checkPrivateContainerBookmark() {
        if sharedModel.multiLCStatus == 2 {
            return
        }
        if LCUtils.appGroupUserDefault.object(forKey: "LCLaunchExtensionPrivateDocBookmark") != nil {
            return
        }

        guard let bookmark = LCUtils.bookmark(for: LCPath.docPath) else {
            errorInfo = "Failed to create bookmark for Documents folder?"
            errorShow = true
            return
        }
        LCUtils.appGroupUserDefault.set(bookmark, forKey: "LCLaunchExtensionPrivateDocBookmark")
    }
}
