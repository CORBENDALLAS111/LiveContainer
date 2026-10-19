import SwiftUI
@objc(LCOSSwiftUITestFactory)
final class LCOSSwiftUITestFactory: NSObject {
    @MainActor @objc(controllerWithAction:)
    static func controller(action: @escaping () -> Void) -> UIViewController {
        UIHostingController(rootView: Button(action: action) {
            Text("SwiftUI tap").frame(maxWidth: .infinity, maxHeight: .infinity).contentShape(Rectangle())
        }.buttonStyle(.plain).background(Color.blue.opacity(0.15)))
    }
}
