# Codex handoff — iPhone UI QA and native Apple styling

## Scope and prerequisites

Read `AGENTS.md`, `HOME_SCREEN.md`, and the screenshots supplied in the November 16, 2026 LifeContainer+ UI report. This document is a **follow-on QA/repair brief** for Codex after the continuous-scroll/native-edge implementation in `feature/ios-native-continuous-app-grid`. **Do not replace the design with a web-style screen, mock widget, or custom fake blur.**

### Required iPhone / SwiftUI design skills

Read these skill files (online references, not project dependencies) **before editing the UI**:

1. [Apple iOS UI Review](https://github.com/rshankras/claude-code-apple-skills/blob/main/skills/ios/ui-review/SKILL.md) — exact HIG, typography, interaction/accessibility review.
2. [Apple Liquid Glass](https://github.com/rshankras/claude-code-apple-skills/blob/main/skills/design/liquid-glass/SKILL.md) — actual system glass, correct material layering and scroll effects.
3. [SwiftUI Layout](https://github.com/rshankras/claude-code-apple-skills/blob/main/skills/swiftui/layout/SKILL.md) — adaptive layout, safe areas, intrinsic sizing, responsive grids.
4. [iOS Navigation Patterns](https://github.com/rshankras/claude-code-apple-skills/blob/main/skills/ios/navigation-patterns/SKILL.md) and [SwiftUI Toolbars](https://github.com/rshankras/claude-code-apple-skills/blob/main/skills/swiftui/toolbars/SKILL.md) — real tabs/navigation, no overlay toolbar collisions.
5. [Apple Animation Patterns](https://github.com/rshankras/claude-code-apple-skills/blob/main/skills/design/animation-patterns/SKILL.md) — interaction transitions and Reduce Motion.
6. [iOS Accessibility Audit](https://github.com/rshankras/claude-code-apple-skills/blob/main/skills/ios/accessibility-audit/SKILL.md) — VoiceOver, Dynamic Type, minimum hit areas.
7. [Run in iOS Simulator](https://github.com/rshankras/claude-code-apple-skills/blob/main/skills/ios/run-simulator/SKILL.md) — launch real views and verify screenshots against the bug report.
8. [oil-ui](https://github.com/oil-oil/oil-ui/blob/main/SKILL.md) — compare visual hierarchy, contrast, density and screenshots; use as review guidance only.
9. [UI/UX Pro Max skill](https://github.com/nextlevelbuilder/ui-ux-pro-max-skill/blob/main/.claude/skills/ui-ux-pro-max/SKILL.md) — checklist and `swiftui` recommendations, not Tailwind/CSS components.

Authoritative Apple design guidance: [iOS HIG](https://developer.apple.com/design/human-interface-guidelines/designing-for-ios), [Apple scroll views/scroll edge effects](https://developer.apple.com/design/human-interface-guidelines/scroll-views), [ScrollEdgeEffectStyle](https://developer.apple.com/documentation/swiftui/scrolledgeeffectstyle).

## Known visual failures visible on device

- **Apps home screen (iPhone portrait):** the old `LCHomeScrollVeil` draws opaque-looking, sharp horizontal translucent bands that cut through icons and labels. Do not restore `.overlay(Rectangle().fill(.ultraThinMaterial).frame(...))`. Use native iOS 26 `scrollEdgeEffectStyle(.soft, for: ...)` **only when content actually scrolls beneath floating controls**; use native defaults on older iOS. Never stack material on material.
- **Apps navigation:** old `TabView(selection: $page)` splits applications into pages; user requires **ONE long, vertically scrolling `LazyVGrid`**. No home page dots or horizontal page swipes; folders can keep their internal paging. Keep stable identifiers, folder actions, long press, reorder, drag-to-folder, drag-out, search and dynamic app updates.
- **Settings:** the entire section near the top and bottom of the screen has overpowering gray/dark glass. Inspect `LCTabView`, `LCSettingsView` and nested `Form` navigation. Do not apply `scrollEdgeEffectStyle` or `ultraThinMaterial` globally to all tab content. Prefer system TabView, toolbar and Form.
- **iPad mini:** portrait/landscape: no overlapping Tweaks title, no cut-off icons, no duplicated controls; support window resizing/Stage Manager.
- **Other screens:** Sources, Apps, Tweaks, Settings, Live Logs, SideStore Advanced Install, Extension Manager, Injection Manager, folder overlay, search and context menus. Inspect all for safe-area, duplicated glass, clipped text, lost tap targets and mismatched rows.

## Required implementation and QA

1. Pull the latest PR chain (upstream integration PR #3 → SideStore Advanced Install PR #4 → UX polish PR #6 → continuous grid). Preserve all functional fixes; **do not silently remove installer, injection, drag/drop, search or JIT logic**.
2. Build with the actual Xcode scheme. Run Swift Package tests, native Xcode build, integration IPA workflow if available. No compile errors, no new warnings introduced.
3. Run on an available current iPhone Simulator and iPad mini (do not invent device destinations). Capture real screenshots of **Home at rest, halfway scrolled, bottom of a long 100+ app grid, edit/drag, open folder, Settings at top and scrolled, Tweaks, Logs, Advanced Install**. Compare with the user-provided bug screenshots.
4. Verify at 200% Dynamic Type, with VoiceOver, Increase Contrast, Reduce Motion, dark and light appearance, iPhone portrait/landscape, iPad mini portrait/landscape, split window. Maintain 44pt touch targets and text wrapping.
5. Ensure `ScrollView` is the only root Apps vertical scroll owner. If top/bottom controls are pinned, place them using native safe-area mechanisms and inspect scroll behavior underneath. Do not fake App Library blur with overlays, custom opacity gradients or screenshots.
6. Check performance with large inventories; record whether rendering remains responsive while dragging, renaming a folder, opening search and rotating. Use stable identity, lazy grid, no new expensive geometry effects.
7. Fix **all visually reproducible UI bugs** in scope, not just the reported bars. Report remaining limitations honestly, and link evidence. One green compilation is **not** evidence the interface has been visually verified.
8. Do not reintroduce Automations, widget proxies, notification passthrough, unsupported device-limit bypass, or fake guest App Intents.

## Evidence / definition of done

PR contains an itemized **Before → Change → After** checklist, file/line references, CI status and screenshots from actual simulator/device. The screenshot of a partially scrolled grid must show **no hard horizontal material band** crossing any icons or labels. The root app list must scroll continuously from first to last installed item and preserve folder/drag behavior. Real system tab bar and navigation must remain readable and visually native.

If Codex lacks a simulator or connection to a device, leave screenshot QA explicitly **unverified** and do not claim completion.
