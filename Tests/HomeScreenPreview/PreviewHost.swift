// UI component fixture host only. Not part of the production Xcode target or IPA.
// It compiles the actual Home Screen, layout and icon artwork sources against fixture registry models.
import SwiftUI
import UIKit

enum LCTabIdentifier { case apps, tweaks, settings }
enum LCUtils { static let appGroupUserDefault = UserDefaults.standard }
protocol LCAppBannerDelegate {}

final class SharedModel: ObservableObject {
    @Published var selectedTab: LCTabIdentifier = .apps
    let multiLCStatus = 0
}
final class LCAppModel: ObservableObject, Hashable {
    let appInfo: PreviewAppInfo
    let displayName: String
    let bundleIdentifier: String
    let isSigningInProgress = false
    let signProgress = 0.0
    let uiIsLocked = false
    init(url: URL, info: [String: Any]) {
        appInfo = PreviewAppInfo(url: url)
        displayName = info["CFBundleDisplayName"] as? String ?? "Fixture"
        bundleIdentifier = info["CFBundleIdentifier"] as? String ?? "org.example.fixture"
    }
    static func == (lhs: LCAppModel, rhs: LCAppModel) -> Bool { lhs === rhs }
    func hash(into hasher: inout Hasher) { hasher.combine(ObjectIdentifier(self)) }
}
final class PreviewAppInfo {
    let url: URL
    var relativeBundlePath: String? { url.lastPathComponent }
    init(url: URL) { self.url = url }
    func iconIsDarkIcon(_ dark: Bool) -> UIImage? {
        UIImage(contentsOfFile: url.appendingPathComponent(dark ? "LCAppIconDark.png" : "LCAppIconLight.png").path)
    }
}
struct LCAppBanner: View {
    let appModel: LCAppModel
    let delegate: LCAppBannerDelegate
    var homeScreen = false
    var iconSide: CGFloat = 62
    var homeEditing = false
    var showLabel = true
    var isDocked = false
    var onToggleDock: (() -> Void)?
    var body: some View {
        LCHomeIconArtwork(model: appModel, darkIcon: false, side: iconSide, showLabel: showLabel, launch: {}, remove: homeEditing ? {} : nil)
            .contextMenu { Button("Fixture action") {} }
    }
}
final class BuiltInSideStoreAppInfo {
    static let shared = BuiltInSideStoreAppInfo()
    func iconIsDarkIcon(_ dark: Bool) -> UIImage { UIImage(systemName: "app.fill")! }
}
struct IconImageView: View {
    let icon: UIImage
    var body: some View { Image(uiImage: icon).resizable().scaledToFit() }
}
extension String {
    var loc: String { NSLocalizedString(self, comment: "") }
    func localizeWithFormat(_ arguments: CVarArg...) -> String { String(format: loc, arguments: arguments) }
}

struct PreviewDelegate: LCAppBannerDelegate {}
@main
struct PreviewHost: App {
    @StateObject private var shared = SharedModel()
    @State private var jiggleCount = 0
    @State private var blankTrace = ""
    init() {
        // SwiftUI AppStorage may not observe the launch-argument defaults domain.
        // Seed the fixture's persistent domain before constructing production views.
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("preview-config.plist")
        if let data = try? Data(contentsOf: url),
           let values = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] {
            for (key, value) in values { UserDefaults.standard.set(value, forKey: key) }
        }
    }
    private let apps: [LCAppModel] = {
        if UserDefaults.standard.bool(forKey: "LCOSHomeGestureTests") {
            // Native UI tests begin in normal mode and enter editing through real gestures.
            let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("Applications")
            try? FileManager.default.removeItem(at: directory)
            for index in 0..<12 {
                let url = directory.appendingPathComponent("Gesture\(index).app")
                try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
                let info = ["CFBundleIdentifier": "org.example.gesture.\(index)", "CFBundleDisplayName": "App \(index)"]
                try? PropertyListSerialization.data(fromPropertyList: info, format: .binary, options: 0).write(to: url.appendingPathComponent("Info.plist"))
                try? UIImage(systemName: "app.fill")?.pngData()?.write(to: url.appendingPathComponent("LCAppIconLight.png"))
            }
            UserDefaults.standard.set("", forKey: "LCOSHomeLayout")
        }
        let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("Applications")
        let urls = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return urls.sorted { $0.lastPathComponent < $1.lastPathComponent }.compactMap { url in
            guard let data = try? Data(contentsOf: url.appendingPathComponent("Info.plist")),
                  let info = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else { return nil }
            return LCAppModel(url: url, info: info)
        }
    }()
    var body: some Scene {
        WindowGroup {
            LCHomeScreenView(apps: apps, delegate: PreviewDelegate(), importing: false, installProgress: 0,
                             importIPA: {}, importURL: {}, openLink: {}, openSideStore: nil)
                .environmentObject(shared)
                .overlay(alignment: .bottomLeading) {
                    if UserDefaults.standard.bool(forKey: "LCOSHomeGestureTests") {
                        VStack(alignment: .leading) {
                        Text(blankTrace).font(.caption2).accessibilityIdentifier("fixture.blankTrace")
                        Text("\(jiggleCount)").font(.caption2)
                            .accessibilityIdentifier("fixture.jiggleCount")
                            .onReceive(Timer.publish(every: 0.2, on: .main, in: .common).autoconnect()) { _ in
                                func count(_ controller: UIViewController) -> Int {
                                    let active = (controller as? LCHomeDragController).map {
                                        $0.host.view.layer.animation(forKey: "lifecontainer.editJiggle") != nil ? 1 : 0
                                    } ?? 0
                                    return active + controller.children.reduce(0) { $0 + count($1) }
                                }
                                blankTrace = UserDefaults.standard.string(forKey: "LCOSBlankTrace") ?? "no anchor"
                                jiggleCount = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
                                    .flatMap(\.windows).compactMap(\.rootViewController).reduce(0) { $0 + count($1) }
                            }
                        }
                    }
                }
                .task {
                    if #available(iOS 16.0, *) {
                        try? await Task.sleep(nanoseconds: 300_000_000)
                        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene else { return }
                        scene.windows.first?.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
                        scene.requestGeometryUpdate(.iOS(interfaceOrientations:
                            UserDefaults.standard.bool(forKey: "LCOSPreviewLandscape") ? .landscapeRight : .portrait))
                    }
                }
        }
    }
}
