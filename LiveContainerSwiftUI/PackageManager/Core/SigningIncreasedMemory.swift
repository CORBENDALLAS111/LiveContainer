import Foundation

/// Opt-in metadata for the Apple Developer Portal capability requested by
/// GetMoreRam. This is an installation request, not an entitlement by itself.
/// SideStore must enable the App ID capability, download a profile granting it
/// and sign the executable with the matching entitlement.
enum SigningIncreasedMemory {
    static let entitlement = "com.apple.developer.kernel.increased-memory-limit"
    static let fileName = "LCOSIncreasedMemoryRequest.plist"

    static func writeRequest(in app: URL, bundleIdentifier: String) throws {
        try SigningInjectionPreset.validateTarget(bundleIdentifier)
        let payload: [String: Any] = [
            "schema": 1,
            "requested": true,
            "bundleIdentifier": bundleIdentifier
        ]
        let data = try PropertyListSerialization.data(
            fromPropertyList: payload, format: .xml, options: 0)
        try data.write(to: app.appendingPathComponent(fileName), options: .atomic)
    }

    static func removeRequest(in app: URL) throws {
        let url = app.appendingPathComponent(fileName)
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }

    /// Throws on malformed or mismatched requests rather than silently
    /// activating a capability for an unrelated app.
    static func requested(in app: URL, bundleIdentifier: String) throws -> Bool {
        let url = app.appendingPathComponent(fileName)
        guard FileManager.default.fileExists(atPath: url.path) else { return false }
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? Int.max
        guard size <= 4096,
              let data = try? Data(contentsOf: url),
              let dictionary = try? PropertyListSerialization.propertyList(
                  from: data, format: nil) as? [String: Any],
              dictionary["schema"] as? Int == 1,
              dictionary["requested"] as? Bool == true,
              dictionary["bundleIdentifier"] as? String == bundleIdentifier else {
            throw SigningInjectionFailure.invalid(
                "Invalid Increased Memory Limit request. Select the IPA and try again.")
        }
        return true
    }
}
