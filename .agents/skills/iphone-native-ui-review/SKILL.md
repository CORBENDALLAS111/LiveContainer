---
name: iphone-native-ui-review
description: Review and repair LifeContainer+ iPhone/iPad SwiftUI UI bugs, native Liquid Glass, scroll-edge clipping, continuous app grid, tab/navigation bars, and screenshot regressions. Use when changing or auditing the visual design, animations, Home, Settings, Tweaks, Logs or SideStore installation screens.
---

# LifeContainer+ native iPhone/iPad UI skill

Use this **as an implementation and verification workflow**, not as a decorative style guide. The UI must feel native to iOS and continue working as an actual application. Do not blindly import third-party component libraries or web designs.

## First read

- Project-specific source of truth: `AGENTS.md`, `HOME_SCREEN.md`, `CODEX_IPHONE_UI_AUDIT.md`.
- [Apple iOS UI Review](https://github.com/rshankras/claude-code-apple-skills/blob/main/skills/ios/ui-review/SKILL.md)
- [Apple Liquid Glass](https://github.com/rshankras/claude-code-apple-skills/blob/main/skills/design/liquid-glass/SKILL.md)
- [SwiftUI Layout](https://github.com/rshankras/claude-code-apple-skills/blob/main/skills/swiftui/layout/SKILL.md)
- [Navigation](https://github.com/rshankras/claude-code-apple-skills/blob/main/skills/ios/navigation-patterns/SKILL.md), [Toolbars](https://github.com/rshankras/claude-code-apple-skills/blob/main/skills/swiftui/toolbars/SKILL.md)
- [Animation Patterns](https://github.com/rshankras/claude-code-apple-skills/blob/main/skills/design/animation-patterns/SKILL.md), [Accessibility Audit](https://github.com/rshankras/claude-code-apple-skills/blob/main/skills/ios/accessibility-audit/SKILL.md), [Run Simulator](https://github.com/rshankras/claude-code-apple-skills/blob/main/skills/ios/run-simulator/SKILL.md)
- [oil-ui](https://github.com/oil-oil/oil-ui/blob/main/SKILL.md) and [UI/UX Pro Max](https://github.com/nextlevelbuilder/ui-ux-pro-max-skill/blob/main/.claude/skills/ui-ux-pro-max/SKILL.md) as visual review checklists, **not** literal CSS/web recipes.
- Official [iOS HIG](https://developer.apple.com/design/human-interface-guidelines/designing-for-ios) and [scroll effects](https://developer.apple.com/design/human-interface-guidelines/scroll-views).

## Workflow

1. Inspect changed views plus `LCTabView` and their scroll/nav containers. Identify which view owns each scroll axis, title, toolbar, safe area and material.
2. Reproduce the issue in an **actual iPhone Simulator or device**, not a static SwiftUI Preview. Review the screenshot and accessibility tree.
3. For the root Apps home use **one vertical ScrollView/LazyVGrid** that never truncates to `LCHomeMetrics.capacity`; preserve folders, drag/drop, search, live inventory, rename and edit mode. Pages are allowed only inside open folders.
4. For iOS 26+ use actual system Liquid Glass on **interactive chrome** and `scrollEdgeEffectStyle(.soft)` only at the appropriate scroll/control boundary. Before iOS 26 leave native scroll rendering intact. Never create a fake `ultraThinMaterial` rectangle/gradient strip across app icons. Never apply scroll-edge modifiers globally to all tabs/forms.
5. Fix the smallest responsible layout or state issue. Respect Dynamic Type, keyboard, system appearance, safe areas, iPad mini width and window resizing; prefer semantic typography, 44pt hit areas, SF Symbols, native `List`/`Form` and system tab/navigation bars. Never use fixed heights to artificially reserve nav bars.
6. Preserve native functionality: SideStore signing/install, tweak injection, data, JIT, Logs and all existing app actions; do not reintroduce widget proxies, notifications or Automations.
7. Run Swift package tests and Xcode build. Review **top, middle, bottom** of a 100+ item continuous grid, open folder, edit/drag, Settings, Tweaks and Log screens. Repeat light/dark, portrait/landscape, Reduce Motion and accessibility tests.
8. Submit a small PR with precise before/after findings, screenshots, CI results and any device-only checks not yet validated.

## Failure checks

- Horizontal stripes across scrolling icons -> remove custom blur overlays; inspect native scroll/safe-area layout.
- First/last icon clipped or shadow cut -> inspect grid insets, scroll containment and pinned controls; don't disable all clipping blindly.
- Settings/tab bar appears double-blurred -> remove repeated materials or root `scrollEdgeEffectStyle` modifiers; let the system own tab and navigation chrome.
- Apps require page dots/swipes -> root is still paginated; replace with one lazy vertical grid.
- Xcode builds but screenshot still wrong -> task is **not complete**. Compare running app screenshots, fix and rerun.

Stop if required runtime verification is unavailable and label those findings **unverified**, not successful.
