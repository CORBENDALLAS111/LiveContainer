# LifeContainer+ — Native Apple UI Rules

For all iPhone / iOS 26+ visual fixes, first read **[CODEX_IPHONE_UI_AUDIT.md](CODEX_IPHONE_UI_AUDIT.md)** and its exact links to Apple UI Review, Liquid Glass, SwiftUI Layout, iOS Navigation, Animation, Accessibility, and Simulator QA skills. The November 2026 iPhone screenshots are a regression baseline: hard horizontal scroll blur bands and root grid pagination must not return. A green Xcode build is insufficient to mark UI defects fixed.

This repository is an **iOS/iPadOS app**, implemented in **Swift, SwiftUI and existing UIKit bridges**. Every UI change must look and behave like a first-party Apple app. Native Apple Human Interface Guidelines and the project's existing appearance take precedence over generic web/mobile design advice.

## External design references (guidance, not runtime dependencies)

For UI tasks, consult the relevant sections of these public skill sources before editing:
- [oil-ui](https://github.com/oil-oil/oil-ui/blob/main/SKILL.md): establish one clear screen purpose and primary action; assess hierarchy/spacing in screenshots; offer multiple directions only when requested; compare rendered results against the actual device screenshot.
- [Apple platform skills](https://github.com/rshankras/claude-code-apple-skills): prefer `skills/ios/ipad-patterns`, `skills/ios/navigation-patterns`, `skills/swiftui/layout`, `skills/swiftui/toolbars`, `skills/design/liquid-glass`, and `skills/ios/ui-review` when relevant.
- [UI/UX Pro Max](https://github.com/nextlevelbuilder/ui-ux-pro-max-skill/blob/main/.claude/skills/ui-ux-pro-max/SKILL.md): use native-app UX review rules, accessibility, touch-target size, spacing and responsive checks. Consult its `references/pro-rules.md`; use the **swiftui** stack, never its web-oriented components or CSS design tokens as a literal implementation.

These are inspiration and checklists, not permission to copy third-party components, add web frontend frameworks, or bypass the app's working behavior. Do not claim a skill was installed locally unless it actually was.

## Native implementation decisions

1. **System navigation first:** `TabView`, `NavigationStack` / `NavigationSplitView` where architecturally appropriate, `NavigationLink`, native `.toolbar`, `.searchable`, `Menu`, `confirmationDialog` and `sheet`. Preserve the app's existing navigation state and toolbar handlers. Avoid manually positioned floating toolbars, tab overlays and ad-hoc safe-area offsets.
2. **Native surfaces:** `List`, `Form`, `Section`, `Picker`, `Toggle`, `Button`, `Label`, SF Symbols, system colors/materials, semantic text styles and Dynamic Type. Respect existing reusable components. Avoid hardcoded black/white, constant pixel font sizes, or a web-like dashboard treatment.
3. **Liquid Glass correctly:** on iPadOS/iOS 26+ use the system style for navigation, toolbars and floating interactive controls. Do **not** apply glass to every content card, row or nested panel; never glass-on-glass. Earlier OS versions must remain functional with system fallbacks. See `HOME_SCREEN.md` for current UI behavior.
4. **Adaptive layouts:** choose available **window/container width** and size classes, not orientation or model IDs alone. Support iPad mini portrait/landscape, larger iPads, iPhone, Stage Manager and resized windows. Only use a split layout when the content hierarchy warrants it; choose `NavigationSplitView` for a real sidebar/detail navigation model, not simply to place two unrelated lists next to one another. Prefer native `List` for large collections and a common top-level scroll owner when building a custom two-column card composition.
5. **Alignment and hierarchy:** titles have one owner; they must not overlap row content or be repeated by both a custom header and `.navigationTitle`. Align the top edges of related columns, icon centers, row heights, card insets and divider starts. Use a consistent 4/8pt spacing rhythm and appropriate readable maximum text widths. Leave enough space for dynamic text and localized strings.
6. **Interaction preservation:** refactors must keep IPA/DEB installs, sources, SideStore integration, signing, context menus, toggles, folder navigation, rename/delete, errors and async loading intact. Reuse a single row implementation when displaying the same item in different layouts. Avoid state reset and gesture conflicts during rotation/window resizing.
7. **Accessibility:** minimum 44×44pt tap targets; clear `.accessibilityLabel` for icon buttons; VoiceOver reading order, keyboard focus, pointer/hover, accessibility contrast, Reduce Motion, Dynamic Type, dark/light mode and non-color status feedback. Use semantic `.font(.headline)`, `.foregroundStyle(.secondary)` etc. rather than arbitrary values.
8. **Performance:** keep identities stable in `ForEach`, avoid duplicate state owned by alternative layouts, don't nest independently scrolling lists without a strong reason, and prefer lazy containers only when the content volume justifies them.

## Acceptance criteria for UI PRs

- Specify the before/after screenshot and the intended user action; make the smallest architecture change that fixes the problem.
- Compare **iPad mini portrait and landscape**, compact window, and full-width iPad. Check navigation bars, status bar, home indicator, keyboard and any sheets.
- Verify standard operations with real UI: navigation, toggle, edit, import, cancel, error, reload and state persistence; don't treat successful compilation as visual QA.
- Test light and dark mode, largest practical Dynamic Type, VoiceOver, pointer/keyboard and Reduce Motion where applicable.
- Run Xcode/CI and inspect the newest commit's results. State clearly when an actual simulator/physical-device screenshot or interaction test wasn't available.
- Preserve the project-specific visual language from `HOME_SCREEN.md` and `LIFECONTAINER_PLUS.md`. Do not import React, Tailwind, custom web-based components or aesthetic patterns that conflict with Apple's native controls.
