"""Patch pinned SideSign's signer to honor an *explicit* authorized RAM request.

GetMoreRam enables a developer-portal App ID capability. SideSign also filters
profile entitlements against the original executable, so we must preserve the
approved entitlement when this single request exists in the prepared IPA.
Never synthesize a code-signing entitlement if the Apple profile lacks it.
"""
import hashlib
import pathlib
import subprocess
import sys

PINNED_SIDESIGN = "752d1ef602aa792a432ffa1e71646dc1ecf7363c"
MEMORY_KEY = "com.apple.developer.kernel.increased-memory-limit"


def patch(sidesign: pathlib.Path) -> dict:
    sha = subprocess.check_output(["git", "-C", str(sidesign), "rev-parse", "HEAD"], text=True).strip()
    if sha != PINNED_SIDESIGN:
        raise ValueError("SideSign source revision changed; review Increased Memory Limit integration")
    file = sidesign / "Sources/CodeSigning/CodeSignerAPI.swift"
    original = file.read_text(encoding="utf-8")
    a = "            let applicationEntitlements = app.entitlements\n"
    b = r'''            // LCOS: Preserve Increased Memory Limit only for an explicitly
            // selected Advanced Install IPA *and* a real Apple-granted profile.
            // Unlike other profile-only entitlements, this request originates
            // after the original executable was signed. Never apply it to
            // extensions or unrelated app IDs.
            let memoryKey = "com.apple.developer.kernel.increased-memory-limit"
            let requestURL = app.fileURL.appendingPathComponent("LCOSIncreasedMemoryRequest.plist")
            var increasedMemoryRequested = false
            if !app.isExtension && FileManager.default.fileExists(atPath: requestURL.path) {
                let size = try requestURL.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? Int.max
                guard size <= 4096,
                      let data = try? Data(contentsOf: requestURL),
                      let metadata = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
                      metadata["schema"] as? Int == 1,
                      metadata["requested"] as? Bool == true,
                      let requestBundle = metadata["bundleIdentifier"] as? String,
                      requestBundle == app.bundleIdentifier ||
                          app.bundleIdentifier == requestBundle + "." + matchedProfile.teamIdentifier else {
                    throw SignerError.invalidApp(cause: "Invalid Increased Memory Limit install request")
                }
                guard matchedProfile.entitlements[memoryKey] as? Bool == true else {
                    throw SignerError.invalidApp(cause: "Apple provisioning profile does not grant Increased Memory Limit")
                }
                increasedMemoryRequested = true
                // The request is transport metadata, not a persistent app
                // resource. Strip it before the final code signature so
                // refreshes only rely on the real signed entitlement.
                try FileManager.default.removeItem(at: requestURL)
            }

            let applicationEntitlements = app.entitlements
'''
    if original.count(a) != 1:
        raise ValueError("SideSign entitlement anchor changed")
    updated = original.replace(a, b)
    a = '''                } else if key != "application-identifier"               &&
                          key != "com.apple.developer.team-identifier"  &&
                          key != "get-task-allow" 
                {
                    filteredEntitlements.removeValue(forKey: key)
                }'''
    b = '''                } else if key != "application-identifier"               &&
                          key != "com.apple.developer.team-identifier"  &&
                          key != "get-task-allow" &&
                          !(key == memoryKey && increasedMemoryRequested)
                {
                    filteredEntitlements.removeValue(forKey: key)
                }'''
    if updated.count(a) != 1:
        raise ValueError("SideSign signer entitlement filter changed")
    updated = updated.replace(a, b)
    file.write_text(updated, encoding="utf-8")
    return {
        "submodule": sha,
        "source_sha256": hashlib.sha256(original.encode()).hexdigest(),
        "patched_sha256": hashlib.sha256(updated.encode()).hexdigest(),
    }


if __name__ == "__main__":
    import json
    print(json.dumps(patch(pathlib.Path(sys.argv[1]).resolve()), indent=2))
