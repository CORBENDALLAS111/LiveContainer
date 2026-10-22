import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// UIKit owns the lift/drop/cancellation lifecycle, so a cancelled drag cannot leave a dimmed icon.
struct LCHomeDragSource<Content: View>: UIViewControllerRepresentable {
    let id: String
    let iconSide: CGFloat
    let jiggle: Bool
    let content: Content
    let begin: () -> Void
    let end: () -> Void
    func makeUIViewController(context: Context) -> LCHomeDragController {
        LCHomeDragController(id: id, iconSide: iconSide, content: AnyView(content), begin: begin, end: end)
    }
    func updateUIViewController(_ controller: LCHomeDragController, context: Context) {
        controller.host.rootView = AnyView(content)
        controller.setJiggle(jiggle)
        controller.id = id; controller.iconSide = iconSide; controller.begin = begin; controller.end = end
    }
    @available(iOS 16.0, *)
    func sizeThatFits(_ proposal: ProposedViewSize, uiViewController: LCHomeDragController, context: Context) -> CGSize? {
        guard let width = proposal.width, let height = proposal.height else { return nil }
        return CGSize(width: width, height: height)
    }
}
final class LCHomeDragController: UIViewController, UIDragInteractionDelegate {
    let host: UIHostingController<AnyView>
    var id: String
    var iconSide: CGFloat
    var begin: () -> Void
    var end: () -> Void
    // Paging or closing a folder can remove the source view before UIKit ends the drag.
    // Keep its delegate alive for that session so the same lifted icon can enter another folder.
    private var activeSessionOwner: LCHomeDragController?
    private weak var dragWindow: UIWindow?
    private var liftLocation = CGPoint.zero
    private var activated = false
    private var wantsJiggle = false
    init(id: String, iconSide: CGFloat, content: AnyView, begin: @escaping () -> Void, end: @escaping () -> Void) {
        self.id = id; self.iconSide = iconSide; self.begin = begin; self.end = end
        host = UIHostingController(rootView: content)
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unsupported") }
    private func previewDustIfRequested() {
        #if DEBUG
        guard UserDefaults.standard.bool(forKey: "LCOSPreviewEnabled"),
              UserDefaults.standard.bool(forKey: "LCOSPreviewDust"),
              id.hasPrefix("org.example.homepreview.10:") else { return }
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard let self, self.view.window != nil, let snapshot = LCHomeDustAnimator.capture(self.view) else { return }
            await LCHomeDustAnimator.dissolve(snapshot, hiding: self.view)
            self.view.alpha = 1 // Fixture only: no real app or data is removed.
        }
        #endif
    }
    override func loadView() {
        view = UIView(); view.backgroundColor = .clear
        view.accessibilityIdentifier = "lifecontainer.homeIcon"
        addChild(host); host.view.backgroundColor = .clear; host.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(host.view)
        NSLayoutConstraint.activate([host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor), host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)])
        host.didMove(toParent: self)
        let interaction = UIDragInteraction(delegate: self); interaction.isEnabled = true; view.addInteraction(interaction)
    }
    func dragInteraction(_ interaction: UIDragInteraction, itemsForBeginning session: UIDragSession) -> [UIDragItem] {
        activeSessionOwner = self
        dragWindow = view.window
        liftLocation = session.location(in: view)
        if let window = dragWindow { liftLocation = view.convert(liftLocation, to: window) }
        activated = false
        let provider = NSItemProvider()
        let data = Data(id.utf8)
        provider.registerDataRepresentation(forTypeIdentifier: "org.livecontainer.desktop-app", visibility: .ownProcess) { completion in
            completion(data, nil); return nil
        }
        let item = UIDragItem(itemProvider: provider); item.localObject = id; return [item]
    }
    func dragInteraction(_ interaction: UIDragInteraction, sessionDidEnd session: UIDragSession) {
        defer { activeSessionOwner = nil }
        if activated { end() }
        activated = false
    }
    func dragInteraction(_ interaction: UIDragInteraction, sessionDidMove session: UIDragSession) {
        guard !activated, let window = dragWindow else { return }
        let point = session.location(in: window)
        let dx = point.x - liftLocation.x, dy = point.y - liftLocation.y
        guard dx * dx + dy * dy > 64 else { return }
        activated = true
        begin()
    }
    func dragInteraction(_ interaction: UIDragInteraction, sessionAllowsMoveOperation session: UIDragSession) -> Bool { true }
    func dragInteraction(_ interaction: UIDragInteraction, sessionIsRestrictedToDraggingApplication session: UIDragSession) -> Bool { true }
    func dragInteraction(_ interaction: UIDragInteraction, previewForLifting item: UIDragItem, session: UIDragSession) -> UITargetedDragPreview? {
        iconPreview()
    }
    func dragInteraction(_ interaction: UIDragInteraction, previewForCancelling item: UIDragItem, withDefault defaultPreview: UITargetedDragPreview) -> UITargetedDragPreview? {
        // The old folder/page may no longer be in a window. UIKit's fallback remains valid.
        host.view.window == nil ? defaultPreview : iconPreview()
    }
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        setJiggle(wantsJiggle)
        previewDustIfRequested()
    }
    func setJiggle(_ active: Bool) {
        wantsJiggle = active
        let key = "lifecontainer.editJiggle"
        guard active else { host.view.layer.removeAnimation(forKey: key); return }
        guard host.view.layer.animation(forKey: key) == nil else { return }
        let seed = id.utf8.reduce(0) { ($0 + Int($1)) % 7 }
        let motion = CAKeyframeAnimation(keyPath: "transform.rotation.z")
        motion.values = [-0.018, 0.018, -0.018]
        motion.duration = 0.26 + Double(seed) * 0.012
        motion.repeatCount = .infinity
        motion.timeOffset = Double(seed) * 0.023
        motion.isRemovedOnCompletion = true
        host.view.layer.add(motion, forKey: key)
    }
    private func iconPreview() -> UITargetedDragPreview {
        let parameters = UIDragPreviewParameters(); parameters.backgroundColor = .clear
        let icon = CGRect(x: (host.view.bounds.width - iconSide) / 2, y: 0, width: iconSide, height: iconSide)
        parameters.visiblePath = UIBezierPath(roundedRect: icon, cornerRadius: iconSide * 0.235)
        return UITargetedDragPreview(view: host.view, parameters: parameters)
    }
}


/// SwiftUI may flatten a background outside its UIScrollView hierarchy. Observe
/// its window, accepting only touches inside this page's visible rectangle and
/// outside icon cells. This also covers the empty space added by minHeight.
struct LCHomeBlankPress: UIViewRepresentable {
    var perform: () -> Void
    var tapped: () -> Void
    var enabled = true
    func makeUIView(context: Context) -> LCHomeBlankPressAnchor { LCHomeBlankPressAnchor(perform: perform, tapped: tapped) }
    func updateUIView(_ view: LCHomeBlankPressAnchor, context: Context) {
        view.perform = perform; view.tapped = tapped; view.canEdit = enabled
    }
    static func dismantleUIView(_ view: LCHomeBlankPressAnchor, coordinator: ()) { view.detach() }
    @available(iOS 16.0, *)
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: LCHomeBlankPressAnchor, context: Context) -> CGSize? {
        guard let width = proposal.width, let height = proposal.height else { return nil }
        return CGSize(width: width, height: height)
    }
}
final class LCHomeBlankPressAnchor: UIView, UIGestureRecognizerDelegate {
    var perform: () -> Void
    var tapped: () -> Void
    var canEdit = true
    private weak var observedWindow: UIWindow?
    private lazy var press: UILongPressGestureRecognizer = {
        let value = UILongPressGestureRecognizer(target: self, action: #selector(held(_:)))
        value.minimumPressDuration = 0.45
        value.allowableMovement = 10
        value.delegate = self
        return value
    }()
    private lazy var tap: UITapGestureRecognizer = {
        let value = UITapGestureRecognizer(target: self, action: #selector(touched(_:)))
        value.require(toFail: press)
        value.delegate = self
        return value
    }()
    init(perform: @escaping () -> Void, tapped: @escaping () -> Void) {
        self.perform = perform; self.tapped = tapped
        super.init(frame: .zero)
        isUserInteractionEnabled = false
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unsupported") }
    override func didMoveToWindow() {
        super.didMoveToWindow()
        detach()
        guard window != nil else { return }
        observedWindow = window
        window?.addGestureRecognizer(press)
        window?.addGestureRecognizer(tap)
    }
    func detach() {
        observedWindow?.removeGestureRecognizer(tap)
        observedWindow?.removeGestureRecognizer(press)
        observedWindow = nil
    }
    private func trace(_ reason: String) {
        #if DEBUG
        guard UserDefaults.standard.bool(forKey: "LCOSHomeGestureTests") else { return }
        let value = reason + " bounds=" + String(describing: bounds)
        if UserDefaults.standard.string(forKey: "LCOSBlankTrace") != value {
            UserDefaults.standard.set(value, forKey: "LCOSBlankTrace")
        }
        #endif
    }
    override func layoutSubviews() {
        super.layoutSubviews()
        trace("layout window=\(window != nil)")
    }
    @objc private func touched(_ sender: UITapGestureRecognizer) {
        if sender.state == .ended { tapped() }
    }
    @objc private func held(_ sender: UILongPressGestureRecognizer) {
        trace("state=\(sender.state.rawValue)")
        if sender.state == .began { perform() }
    }
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        guard canEdit else { return false }
        guard let window = observedWindow, bounds.contains(touch.location(in: self)) else { trace("outside \(touch.location(in: self))"); return false }
        // Offscreen pages, clipped scroll content and presented sheets must not
        // turn editing on behind the currently visible interface.
        var ancestor = superview
        while let view = ancestor {
            if view.isHidden || view.alpha < 0.01 { trace("hidden \(type(of: view))"); return false }
            if view.clipsToBounds && !view.bounds.contains(touch.location(in: view)) { trace("clipped \(type(of: view))"); return false }
            ancestor = view.superview
        }
        if window.rootViewController?.presentedViewController != nil { trace("presented"); return false }
        var hit = touch.view
        while let view = hit {
            if view is UIControl || view is UITextView { trace("control \(type(of: view))"); return false }
            hit = view.superview
        }
        let point = touch.location(in: window)
        // Include the cell's label and badge area, not only the image bounds.
        func containsIcon(_ view: UIView) -> Bool {
            guard !view.isHidden, view.alpha > 0.01 else { return false }
            if view.accessibilityIdentifier == "lifecontainer.homeIcon",
               view.bounds.contains(view.convert(point, from: window)) { return true }
            return view.subviews.contains(where: containsIcon)
        }
        let accepted = !containsIcon(window)
        trace(accepted ? "accepted" : "icon")
        return accepted
    }
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool { true }
}
