# LifeContainer+

The display name is LifeContainer+. Bundle identifiers and executables stay compatible with existing installations and data.

## Desktop

Phone portrait uses 4 columns and 6 rows. Mini-sized iPad windows use 5×6; larger iPads use 5×5 portrait and 6×5 landscape. Compact windows and landscape phones reflow. Small screens and accessibility sizes retain scrolling. Metrics use the actual window dimensions; rotating does not rewrite the stored app order. The existing tab bar is retained.

The desktop title is centered independently of trailing controls. IPA is the first installation action; SideStore is next to the plus button. Desktop scrolling has no material veil or soft edge blur. App icon variants follow the system appearance when the guest supplies them.

Icon jiggle uses an isolated Core Animation layer. Folder placement/drop frames do not participate in that animation. Done commits placement immediately. During folder transitions the background accepts reversal taps while the Done control remains available.

## Tweak repositories

Tweaks → Tweak Marketplace accepts HTTPS flat Sileo/APT repositories (Packages, Packages.gz, Packages.xz and Packages.bz2). Index expansion and download sizes are bounded. Paid/authenticated store downloads, full Debian dependency resolution, APT release-signature verification and distributions with only dists/ indexes are not implemented. Users must trust their chosen HTTPS repository; SHA-256 verifies consistency with its index, not publisher authenticity.

Open **Tweaks → Tweak Marketplace**. The **Browse / Repositories** selector separates the catalog from source management. Add an HTTPS source using **+**, browse its packages, search by name or bundle package ID, and filter by category or repository. The rootless filter shows arm64 and architecture-independent candidates. Removing a repository removes its listings, not already installed tweaks.

A package page shows its description, version, architecture, size and repository website. Choose a guest, download and inspect, then install the validated plan. **Installed Tweaks & Local DEB** opens per-app enable/disable and removal controls and the local DEB importer. Repository changes cancel stale refreshes; an old request cannot put deleted-source listings back into the catalog.

Listings are not compatibility claims. Download and inspect against a selected, stopped guest before installation. The existing package inspector rejects system targets, maintainer actions, unsupported resources/dependencies, non-arm64 code and mismatched bundle filters. Rootless layout is supported but alone is insufficient. No package scripts are run.

## Built-in JIT

Settings → JIT → Set Up Built-in JIT imports a remote pairing plist and checks LocalDevVPN / the Developer Disk Image. The separate LifeJITHelper extension links StikJIT 1.9.0, built from pinned source commit 32287268fa5824f9edce4cb359f5833ce0cf7b00. Source and license provenance are bundled in the IPA. Keep extensions while signing, retain get-task-allow and enable Developer Mode.

JIT-required arm64 guests use LiveProcess when the built-in method is selected: the host must survive while its helper debugs the guest. The guest's bundled custom script is used when present; otherwise the StikJIT universal script is used. TXM devices still require a compatible executable-memory allocator in the guest; debugger attachment alone does not guarantee usable JIT. The extension session is bounded to five minutes. Pairing creation on the phone is not implemented; import a pairing file. Device-only behavior cannot be established by Simulator tests.

## Recording

The Record alert now starts recording after UIKit dismisses it automatically. It no longer waits on a second dismissal completion that may never run. Event observation performs no file reads on every touch/move. Runtime tests exercise the actual alert button, then capture/save/replay.

Regular guest mode supports tap scenarios. LiveProcess, keyboard input, system screens and scroll/swipe recording remain unsupported.

## Third-party widgets

Unmodified WidgetKit extensions from dynamically imported guests cannot be registered or hosted as ordinary views through the public iOS WidgetKit API. They need installed, signed extensions and their original app-group/intent environment. LifeContainer+ does not advertise imitation cards as working native widgets. Existing system-side LiveWidget integration remains available.

## Localization

New marketplace/JIT interfaces and core DEB actions include English/Russian. Desktop labels also include German, French and Spanish, in addition to the existing application localizations.
