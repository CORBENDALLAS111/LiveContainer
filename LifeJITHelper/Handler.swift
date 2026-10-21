import Foundation
import StikJIT

/// Blocking debugger work lives in a process separate from the guest being debugged.
@objc(LifeJITHandler)
final class LifeJITHandler: NSObject, NSExtensionRequestHandling {
    private static let queue = DispatchQueue(label: "lifecontainer.jit")
    func beginRequest(with context: NSExtensionContext) {
        let request = (context.inputItems.first as? NSExtensionItem)?.userInfo ?? [:]
        Self.queue.async {
            var answer: [String: Any] = [:]
            do {
                let root = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0].appendingPathComponent("LifeJIT")
                try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
                let paths = DDIPaths.default(in: root)
                guard let pairing = request["pairing"] as? Data, !pairing.isEmpty, pairing.count <= 1_048_576 else {
                    throw NSError(domain: "LifeJIT", code: 1, userInfo: [NSLocalizedDescriptionKey: "Import this device's remote pairing file first."])
                }
                let file = root.appendingPathComponent(UUID().uuidString + ".plist")
                try pairing.write(to: file, options: [.atomic, .completeFileProtection])
                defer { try? FileManager.default.removeItem(at: file) }
                if request["operation"] as? String == "prepare" {
                    switch StikJIT.prepareDevice(pairingFile: file, paths: paths) {
                    case .ready: answer = ["success": true, "message": "LocalDevVPN and Developer Disk Image are ready."]
                    case .unreachable(let reason), .preparationFailed(let reason): answer = ["success": false, "message": reason]
                    @unknown default: answer = ["success": false, "message": "Unknown device preparation state."]
                    }
                } else {
                    guard let pid = request["pid"] as? NSNumber, pid.int32Value > 0 else {
                        throw NSError(domain: "LifeJIT", code: 2, userInfo: [NSLocalizedDescriptionKey: "Missing guest process."])
                    }
                    let base64 = request["script"] as? String ?? ""
                    try StikJIT.enableJIT(targetPID: pid.int32Value, pairingFile: file, ddiPaths: paths,
                        script: base64.isEmpty ? .universal : .customBase64(base64), forceScript: true)
                    answer = ["success": true, "message": "Debugger session completed. Guest executable memory depends on its JIT allocator."]
                }
            } catch { answer = ["success": false, "message": error.localizedDescription] }
            let item = NSExtensionItem(); item.userInfo = answer
            context.completeRequest(returningItems: [item], completionHandler: nil)
        }
    }
}
