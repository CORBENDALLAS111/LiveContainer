# Guest Privacy & Permissions

Open a guest app's settings, then Privacy & Permissions. Each preference belongs
to that app's LCAppInfo.plist, not a global user default. Defaults are off.
Completely stop the guest and relaunch it before testing changes. The embedded
SideStore is excluded; guest extension bootstrap reads the supplied guest info.

| Setting | Implemented scope | Limits |
| --- | --- | --- |
| Camera | AVFoundation authorization/request, device input factory, session canAddInput/addInput, UIImagePickerController availability | Other media APIs, direct initializers and system services are not guaranteed |
| Microphone | AVFoundation audio input, permission callbacks, AVAudioRecorder methods | Other engines, audio units and system services are not guaranteed |
| Battery | UIDevice monitoring, level/state and explicit notifications | Other APIs may expose information |
| Proximity | UIDevice monitoring and explicit notifications | Other sensors and APIs unaffected |
| Screenshot notifications | Named UIKit screenshot subscriptions | Does not change OS capture protection, screen recording state or other detection paths |

These are in-process API restrictions, not security boundaries. System location,
photos, contacts, Bluetooth, local network, tracking and other permissions remain
shared with LC+. No invented hardware/profile values, fake system permissions,
or guarantees against hostile guests. For strict hardware permission denial use
the iOS Settings for LC+, affecting all its guests.

## Adaptive UI changes
- Apps actions now belong to the Home safe-area layout rather than a global
  iPad overlay, avoiding overlap with pushed settings and narrow windows.
- Home retains a continuous vertical grid and native scroll-edge rendering.
- Columns adapt to available width and accessibility text sizes; scaled icons
  are clamped to cell width. Titles use semantic system backgrounds.
- App settings no longer nest a List inside Form. Long identifiers wrap.
- Native Privacy Form, localized in English/Russian, includes errors and reset.

## Verification
Source review and CI are not screenshot verification. On physical devices check
camera and microphone authorization and media input denial; battery/proximity
unknown state; opt-in named screenshot event filtering; disabled-policy behavior;
one guest's settings do not affect another. Check restart and reset; ensure SideStore
still works. Review iPhone SE/standard/Max, iPad mini, 11/13-inch iPad, portrait,
landscape, compact windows, light/dark, accessibility Dynamic Type, VoiceOver,
and Reduce Motion. Open and close app settings to verify the Apps toolbar does
not remain over the child view. A full visual review requires actual screenshots.
