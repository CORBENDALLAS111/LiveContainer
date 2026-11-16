# Original guest widgets: installation-time feasibility investigation

**Goal:** Duolingo or another guest app stays inside LifeContainer+, while the **real original WidgetKit widget from that guest IPA** appears in the iOS widget gallery and runs with its own UI and timeline. **No proxy or re-created LifeContainer widget is in scope.**

## What is confirmed

- iOS/WidgetKit discovers a **signed installed app extension**, not a random `.appex` under a guest's Documents or app library.
- Widget timeline code executes in a **separate process**, with its own sandbox and entitlements. A running guest inside LiveContainer is not equivalent to an installed containing app.
- Signing and provisioning must cover each relevant nested bundle/extension. Some guest widgets depend on original app group data, background state, URL schemes, push capabilities or other entitlements that a re-signed host might not possess.
- LiveContainer upstream [explicitly does not support guest app extensions](https://github.com/LiveContainer/LiveContainer#limitations).
- Our SideStore integration demonstrates **one installation-time repackaging path**: `.github/build_github.sh` embeds SideStore's **own** `AltWidgetExtension.appex` as `LiveWidgetExtension.appex` in the final IPA, then signs it. This is *not* evidence that arbitrary guest widgets can operate after the guest IPA is imported.

## Read-only feasibility probe

Run `python3 scripts/inspect_guest_widget_extensions.py /path/to/App.ipa` on a lawfully obtained local IPA. It inventories `Payload/*.app/PlugIns/*.appex`, recognizes `com.apple.widgetkit-extension`, reports bundle IDs, binary presence and whether metadata contains a profile/signature file. It **does not** run binary code, extract the IPA, re-sign anything, or claim the extensions are registered.

Unit tests: `python3 -m unittest discover -s Tests -p 'test_original_guest_widget_probe.py'`.

## Required proof before shipping a guest-widget toggle

1. Obtain a reproducible, permitted sample IPA containing a genuine WidgetKit extension and the exact version/device conditions for testing.
2. Validate its widget's dependencies, entitlement requirements, original App Group data flow and signed App ID availability. If provisioning cannot be obtained, **report unsupported**.
3. In an isolated experimental **build/install-time** path (not runtime app import), test packaging the **original** extension as a properly provisioned nested extension under a new containing app. Do not replace it with a proxy renderer. Never silently modify a production host IPA or consume the user's App IDs.
4. Install the experimental host on a test device. Open the host; check whether the original widget actually appears in the system gallery, renders its own timeline, reads its own app data and opens the correct guest.
5. Validate repeat installations, host upgrades, cold boot, widget refresh, App Group access, device reboot, signing expiration and cleanup. A widget merely appearing in the gallery is insufficient.
6. Only after successful physical device verification, expose a **per-app supported/unsupported** UI. No generic “Enable widgets” control that promises functionality on unsupported IPAs.

## Technical limitations and product decision

A host already installed on iOS cannot register an arbitrary new original widget simply by copying extension files from a guest IPA into a writable directory. Adding a new extension would require a re-packaged/re-installed signed containing app, and may still fail because widget runtimes are independent of the guest's process and storage. Do not ship proxy widgets as a fallback, per product requirements.

Apple references: [Creating a widget extension](https://developer.apple.com/documentation/WidgetKit/Creating-a-Widget-Extension), [WidgetKit foundations](https://developer.apple.com/videos/play/wwdc2026/277/), [Provisioning profiles](https://developer.apple.com/documentation/Technotes/tn3125-inside-code-signing-provisioning-profiles).
