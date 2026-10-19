# Advanced Install and installation diagnostics

Open **Applications → + → Advanced Install**. Select an original IPA, change its display name,
bundle identifier or icon, and configure a per-identifier dylib/DEB preset. Choose LiveContainer
to import into the container, or SideStore to sign and install a separate system application.
This does not add signing entitlements, kernel privileges or extra Apple account app slots.

The editor streams ZIP contents to a unique shared workspace, preserves executable permissions,
rejects traversal, links, duplicate files, encrypted entries and excessive archive expansion.
It edits a disposable copy and rewrites app/extension identifiers together. The original IPA
is preserved. Injection uses the existing validated Mach-O/DEB pipeline, without maintainer
scripts. Reconfigure injection after changing the bundle identifier. A conflicting identifier
can update an existing installation; use a distinct identifier to create a clone.
Prepared workspaces expire after seven days, on the next import.

Enable **Settings → Live logs → Detailed installation logs**, then repeat the failing install.
The settings console offers live updates/pause, error filtering, search, export and clearing.
SideStore shows a floating log button once its install pipeline starts. Earlier picker events
remain readable from LiveContainer after a crash. Each process writes its own bounded JSONL
file to `LiveContainer/Diagnostics` in the shared app group, synchronizing every event. Up to
eight 512 KB files are retained (plus at most one event of rollover slack per file).
Logs redact URLs, email addresses and common credential formats; they never intentionally
dump authentication payloads or entire error userInfo dictionaries. Review exports before sharing.
Turning logging off stops new recording and preserves prior logs until cleared.

Recorded boundaries include picker selection/copy/dismissal, install request, IPA unpacking,
native metadata parsing, every pipeline stage, injection validation, elapsed time and NSError
cause chains. Host-caught previous-launch exceptions are imported on the next launch.
An unmatched `.begin` pinpoints the last started stage but cannot distinguish a crash,
memory-pressure termination or a forced quit; it is not an iOS crash report.

The picker now retains an owned copy while its security scope is valid, dismisses Files before
showing confirmation, and reports copy failures instead of passing an unstable URL downstream.
The guest no longer dynamically loads LiveContainerSwiftUI for every manual installation.
These are concrete hardening changes; the user's physical-device crash still requires retesting.
