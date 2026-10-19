import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// Kept as a source compatibility boundary for standalone builds and SDK probes.
/// The embedded guest must not load LiveContainerSwiftUI: its initializers assume host state.
/// Configure dylib/DEB presets in the host Advanced Install screen before handing the IPA over.
@MainActor
enum LCOSSigningInjectionUI {
    static func configure(identifier: String, appName: String, presenter: NSObject) async throws {
        try Task.checkCancellation()
        #if canImport(UIKit)
        guard SigningDiagnostics.enabled, let presenter = presenter as? UIViewController,
              let window = presenter.viewIfLoaded?.window, window.viewWithTag(355812) == nil else { return }
        let button = UIButton(type: .system)
        button.tag = 355812
        button.setImage(UIImage(systemName: "waveform.path.ecg"), for: .normal)
        button.accessibilityLabel = "Live installation logs"
        button.backgroundColor = .secondarySystemBackground
        button.layer.cornerRadius = 22
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addAction(UIAction { [weak window] _ in
            guard let window else { return }
            var top = window.rootViewController
            while let presented = top?.presentedViewController { top = presented }
            guard let top, !(top is UIAlertController) else { return }
            let console = LCOSInstallLogController()
            top.present(UINavigationController(rootViewController: console), animated: true)
        }, for: .touchUpInside)
        window.addSubview(button)
        NSLayoutConstraint.activate([
            button.trailingAnchor.constraint(equalTo: window.safeAreaLayoutGuide.trailingAnchor, constant: -12),
            button.topAnchor.constraint(equalTo: window.safeAreaLayoutGuide.topAnchor, constant: 58),
            button.widthAnchor.constraint(equalToConstant: 44), button.heightAnchor.constraint(equalToConstant: 44)
        ])
        #endif
    }
}

#if canImport(UIKit)
@MainActor
private final class LCOSInstallLogController: UIViewController {
    private let text = UITextView()
    private var timer: Timer?
    private var following = true
    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Live logs"
        view.backgroundColor = .systemBackground
        text.isEditable = false
        text.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        text.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(text)
        NSLayoutConstraint.activate([
            text.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 12),
            text.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -12),
            text.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            text.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)
        ])
        navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .close, target: self, action: #selector(close))
        navigationItem.rightBarButtonItems = [
            UIBarButtonItem(barButtonSystemItem: .action, target: self, action: #selector(share)),
            UIBarButtonItem(title: "Pause", style: .plain, target: self, action: #selector(pause))
        ]
        reload()
    }
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in if self?.following == true { self?.reload() } }
        }
    }
    override func viewDidDisappear(_ animated: Bool) { super.viewDidDisappear(animated); timer?.invalidate(); timer = nil }
    private func reload() {
        text.text = SigningDiagnostics.entries().map { "\($0.date.ISO8601Format()) [\($0.level)] \($0.stage)\n\($0.detail)" }.joined(separator: "\n\n")
        if !text.text.isEmpty { text.scrollRangeToVisible(NSRange(location: (text.text as NSString).length - 1, length: 1)) }
    }
    @objc private func pause() {
        following.toggle()
        navigationItem.rightBarButtonItems?.last?.title = following ? "Pause" : "Resume"
    }
    @objc private func close() { dismiss(animated: true) }
    @objc private func share() {
        let controller = UIActivityViewController(activityItems: [text.text ?? ""], applicationActivities: nil)
        controller.popoverPresentationController?.barButtonItem = navigationItem.rightBarButtonItems?.first
        present(controller, animated: true)
    }
}
#endif
