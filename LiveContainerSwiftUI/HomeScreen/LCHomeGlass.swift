import SwiftUI

extension View {
    @ViewBuilder func lcFixedInstallOrder() -> some View {
        if #available(iOS 16.0, *) { self.menuOrder(.fixed) }
        else { self }
    }
    /// Use the real iOS/iPadOS 26 scroll-edge rendering, not custom
    /// ultraThinMaterial rectangles that create a visible dark/bright stripe.
    /// Earlier systems keep native ScrollView clipping/scroll appearance.
    @ViewBuilder func lcNativeHomeScrollEdges(enabled: Bool) -> some View {
        if #available(iOS 26.0, *) {
            if enabled {
                self.scrollEdgeEffectStyle(.soft, for: .vertical)
            } else {
                self.scrollEdgeEffectHidden(true, for: .all)
            }
        } else {
            self
        }
    }
    @ViewBuilder func lcSoftScrollEdges() -> some View {
        if #available(iOS 26.0, *) { self.scrollEdgeEffectStyle(.soft, for: .all) }
        else { self }
    }
    @ViewBuilder func lcGlass<S: InsettableShape>(in shape: S, interactive: Bool = false) -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(interactive ? .regular.interactive() : .regular, in: shape)
        } else {
            self.background(.regularMaterial, in: shape)
        }
    }
}

struct LCHomeJiggle: ViewModifier {
    let active: Bool
    let id: String
    @State private var rocking = false
    private var seed: Int { id.utf8.reduce(0) { ($0 + Int($1)) % 7 } }
    func body(content: Content) -> some View {
        content.rotationEffect(.degrees(active ? (rocking ? 1 : -1) * (seed % 2 == 0 ? 1.2 : -1.4) : 0))
            .offset(y: active && rocking ? 0.35 : 0)
            .animation(active ? .easeInOut(duration: 0.13 + Double(seed) * 0.008)
                .delay(Double(seed) * 0.015).repeatForever(autoreverses: true) : .easeOut(duration: 0.15), value: rocking)
            .onAppear { rocking = active }
            .onChange(of: active) { rocking = $0 }
    }
}
struct LCGlassGroup<Content: View>: View {
    @ViewBuilder var content: () -> Content
    var body: some View {
        if #available(iOS 26.0, *) { GlassEffectContainer(spacing: 16, content: content) }
        else { content() }
    }
}
