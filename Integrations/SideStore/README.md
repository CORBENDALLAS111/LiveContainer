# SideStore signing injection

This is a personal LiveContainer fork integration, not an upstream SideStore contribution.
GitHub Actions checks out the revision in SOURCE_COMMIT, adds the shared portable injector and a single
call in ResignAppOperation after bundle preparation and before ALTSigner.signApp, then archives SideStore.
The combined IPA packages this source-built SideStore. Source, overlay and patched-operation hashes are
recorded in SIDESTORE_SOURCE.json and embedded as LCOSSigningIntegration.json in the SideStore framework.
The prebuilt nightly remains an explicit fallback only for callers of the upstream packaging script;
the integrated OS workflow requires its source-built signing implementation.

## Use

During a foreground **Install / Update / Reinstall** in embedded SideStore, the injection sheet opens
after application customization. Its target is the selected IPA's original bundle identifier, before
Apple's provisioning suffix. Import a DEB or dylib, review and enable it, then choose Install.
Continue without files for a normal installation; Cancel aborts the installation. This screen is no
longer in LiveContainer Settings. The libraries are copied into an owned
Frameworks/LCOSInjected directory and added as executable load commands before SideStore signs the result.
Multiple libraries are supported. Re-importing a library with the same filename replaces its earlier version.
Disable or delete the preset and reinstall/sign again to remove owned load commands from modified bundles.
Profile-only refresh does not alter executable contents or show the injection sheet.
Previously installed applications change only after SideStore successfully signs and installs the refreshed copy.

DEB extraction, maintainer-script rejection, bundle filters and Mach-O dependency adaptation reuse the
existing package-manager validator. Direct dylibs require an explicit target. Bundled Substrate is included
when a validated dependency needs it. Encrypted executables, arm64e tweak libraries, unsupported dependencies,
resource packages, insufficient load-command padding and protected host/system targets fail explicitly.
No maintainer scripts are executed. No certificate/account details are stored in presets.

The payload is hash-checked and staged before executable modification; failed staging leaves the app intact.
The normal SideStore certificate/provisioning/signing/install operations run afterward. Header changes
invalidate old signatures and must never be exported as an already-signed app before that step.

Portable tests cover payload corruption, rollback, removal, idempotence and preserved code bytes.
The Xcode-built controlled ARM64 device guest is also injected and ad-hoc signed/verified in macOS CI.
These tests do not establish hook compatibility or a successful Apple-account install/refresh on a phone.

## Native Advanced Install sheet

The **Advanced Install** action in the embedded SideStore's IPA import menu opens a native
SwiftUI sheet implemented in `LCAdvancedInstallView` in the LifeContainer host. The
ordinary LifeContainer+ IPA import and ordinary SideStore install/refresh flows are unchanged.
Users choose an IPA, review its real bundle metadata, optionally change its display name,
bundle ID or icon, and configure supported dylib/DEB injection presets before preparation.

- **Enable File Sharing** edits `UIFileSharingEnabled` in the staged app's `Info.plist`.
  When enabled, `LSSupportsOpeningDocumentsInPlace` is also set so the app's Documents
  directory is available to Files. It does not expose unrelated sandbox directories.
  The original value is displayed on load and preserved by default.
- **Remove App Extensions** is visible only when the IPA contains `.appex` bundles in
  `PlugIns`. It is disabled by default, removes those extension bundles from the
  staged copy and may break extension-dependent features such as widgets and sharing.
  Other embedded resources and executables are retained.
- **Manage injected libraries** opens the existing validated injection preset UI, keyed
  to the effective bundle ID. No unsupported device-limit bypass or fictitious Apple
  account/signing selector is offered.

The advanced editor never signs or installs itself: it creates a prepared IPA from a
private staging directory and hands it back to SideStore. Signing, provisioning,
installation and their errors still belong to the real SideStore pipeline. Empty/invalid
choices fail before handoff. Cancel leaves the original IPA untouched.

## Increased Memory Limit (GetMoreRam workflow)

The **Increased Memory Limit** toggle in Advanced Install is **off by default**. It
prepares a user-requested installation option, not a forged Apple entitlement.
The host adds the internal `LCOSIncreasedMemoryLimitRequested` marker to the
**main application only** in the disposable IPA copy. Clearing the toggle
also clears a pre-existing marker; extensions are unaffected.

During the *real* source-built SideStore install pipeline:
1. SideStore finds or creates the Apple App ID for the **effective signed bundle
   identifier**, using the account already signed in to SideStore.
2. `FetchProvisioningProfilesOperation` requests the
   `INCREASED_MEMORY_LIMIT` capability on that App ID before downloading
   a new provisioning profile. The pinned SideSign patch uses Apple Developer
   Services' v1 `bundleIdCapabilities` PATCH (the mechanism used by
   [GetMoreRam](https://github.com/hugeBlack/GetMoreRam)).
3. The operation checks the **actual profile** contains
   `com.apple.developer.kernel.increased-memory-limit = true`.
   If not, installation **fails with a visible error**, rather than silently
   proceeding with a normal-memory profile. A user-selected override profile
   without the entitlement is rejected as well.
4. The pinned SideSign signer may retain this entitlement **only for an opted-in
   main app whose provisioning profile explicitly grants it**. It never grants
   it to app extensions or to apps installed by the ordinary workflow.

A profile entitlement does not add physical RAM or promise a fixed memory
budget; the memory budget is device- and iOS-dependent. Internet access,
Apple account authentication and Apple's approval are necessary. After
installing, a device test must inspect both the installed app's signature
and its provisioning profile to prove the entitlement actually survived.

The feature does not modify the original input IPA, bypass signature checks,
revoke another App ID, or change the ordinary installation/refresh flow.
Account credentials remain managed exclusively by SideStore. We do **not**
ship or embed GetMoreRam or ask the user to log in to a second service.

### Pinned dependency / safety gate

`scripts/prepare_sidestore_source.py` checks out the existing SideStore
revision and its SideSign `752d1ef` submodule, then cherry-picks the
**exact** SideSign pull request
[SideSign #4](https://github.com/SideStore/SideSign/pull/4) commit
`9d89dac1d391c934e5c69be1fadbb090d9a7f944` *without committing*.
The patch request's HEAD must match the pinned SHA, and the modified file
list is verified. It keeps SideStore's existing 2FA fix. The builder patches
the memory-only signer check, verifies the profile operation, runs the
SideSign `CapabilityTests`, and records the source hashes in the build
manifest. The IPA verifier refuses an artifact lacking this provenance.

This is an experimental feature until real Apple profile/signature verification
on an iPhone. A green Xcode build cannot establish an increased memory budget.

## Extension bundle identifiers

The single-profile path now fetches the profile under the effective target bundle ID and keys its
extension map by the effective extension IDs used during resigning. Previously a custom target could
miss that map and fall back to the parent profile's ID for every extension, causing IXErrorDomain
Code 8 / mismatched bundle IDs. A missing mapping now fails explicitly; prepared PlugIns metadata
is checked for parent-dot prefixes and duplicate IDs before signing. This does not override Apple's
provisioning rules or recover already-corrupted extension IDs; reinstall such an app from a fresh IPA.

## SideBackup entitlement preservation

The source build must run upstream `make build fakesign`, including `fakesign-sidebackup`.
Without the initial entitlement declaration in the embedded SideBackup binary, SideSign drops the
App Groups entitlement even when a profile contains it. The result is the purple “SideBackup could
not start” screen. Both the source IPA and final integrated IPA now reject a missing declaration.
This check does not grant entitlements: the final device installation still needs a valid provisioning
profile granting the shared app group.
