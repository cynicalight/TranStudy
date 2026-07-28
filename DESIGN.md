# Design.md — macOS App Design & Motion Guidelines

> Native-first design system. Liquid Glass where available, graceful degradation where not.
> Target: macOS 26 (Tahoe) as the primary platform, macOS 14–15 as the fallback floor.

---

## 1. Design Philosophy

- **Native over custom.** Prefer system materials, system controls, and system motion curves over hand-rolled equivalents. Custom UI should be the exception, justified by a specific product need. If a native SwiftUI/AppKit component exists for a pattern, use it — see §3 for the current component inventory.
- **Liquid Glass is additive, not required.** The app must look and feel complete on macOS 15 without it — Liquid Glass is a progressive enhancement layer, not a dependency.
- **Motion communicates state, not decoration.** Every animation should answer "where did this come from" or "what changed" — especially the geometry-matched transitions in §5.
- **Respect Reduce Motion.** Every custom animation has a reduced-motion fallback (crossfade or instant state change) — see §7.

---

## 2. Liquid Glass Adoption (macOS 26+)

### 2.1 Where to use it
Use Liquid Glass for **chrome**, not content: toolbars, sidebars, sheets, floating action controls, tab bars, popovers. Do **not** apply it to primary content surfaces (lists, canvases, text views) — it competes with content for attention and hurts legibility.

### 2.2 APIs
```swift
// Preferred: system-provided glass container
if #available(macOS 26, *) {
    content
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
} else {
    content
        .background(.ultraThinMaterial, in: .rect(cornerRadius: 16))
}
```

- `GlassEffectContainer` — group multiple glass elements (e.g. a toolbar cluster) so they morph/merge correctly instead of rendering as separate blurred rectangles.
- `.glassEffectID(_:in:)` + `GlassEffectContainer` — for elements that need to visually merge/split during interaction (e.g. an expanding search field absorbing a nearby button).
- Tint sparingly: `.glassEffect(.regular.tint(accentColor.opacity(0.15)))`. Default to `.regular`, reserve `.clear` for full-bleed media contexts only.

### 2.3 Fallback rule (mandatory)
Every `.glassEffect(...)` call **must** be wrapped in an `#available(macOS 26, *)` branch with a Material-based fallback. Do not ship a Liquid Glass–only code path. Suggested helper:

```swift
extension View {
    @ViewBuilder
    func adaptiveGlass(cornerRadius: CGFloat = 12) -> some View {
        if #available(macOS 26, *) {
            self.glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
        } else {
            self.background(.regularMaterial, in: .rect(cornerRadius: cornerRadius))
        }
    }
}
```

Use this single helper app-wide rather than inlining the availability check at every call site — keeps the design system centralized and makes a future material update a one-file change.

---

## 3. Native Component Inventory (recompile-and-get-it-free)

Per Apple's WWDC 2025 guidance (Sessions 219/323/310), the components below adopt Liquid Glass automatically the moment the app is built against the macOS 26 SDK — **no code changes required**. Always reach for these before building a custom equivalent; a hand-rolled toolbar or sidebar will not pick up system glass, lensing, or future OS-level refinements.

### 3.1 Get Liquid Glass for free on macOS 26 (Tahoe)
- `Toolbar` / `ToolbarItem` — floats on glass, groups adjacent items onto one glass piece automatically (AppKit: override via `NSToolbarItemGroup` or spacers)
- `NavigationSplitView` sidebar — glass background + ambient light reflection from adjacent colorful content
- Menu bar content, `Menu`, context menus
- `Dock` (system-owned, no app code)
- `.sheet`, `.popover` (`NSPopover`) — inset glass background that morphs as the sheet/popover resizes
- Window title bar / traffic-light region, `NSWindow` chrome
- `Alert`, confirmation dialogs
- `Toggle`, `Slider`, `Picker` — glass treatment during active interaction

### 3.2 Explicit glass APIs (opt-in, for custom chrome)
- `.glassEffect(_:in:isEnabled:)` — `Glass` variants: `.regular` (default, most surfaces), `.clear` (media-rich content only), `.identity` (accessibility escape hatch)
- `Glass.tint(_:)`, `Glass.interactive()` — interactive is iOS touch-feedback only; has no effect on macOS pointer input, so don't rely on it there
- `GlassEffectContainer(spacing:)` — **required** whenever more than one `.glassEffect()` view sits near another; glass cannot sample other glass without a shared container
- `.glassEffectID(_:in:)` + `@Namespace` — morphing between glass states (e.g. a `+` button expanding into a row of actions)
- `.glassEffectUnion(id:namespace:)` — merges multiple distinct shapes into one glass region without a full morph
- Shape parameter: `.capsule` (default), `.circle`, `.ellipse`, `RoundedRectangle(cornerRadius:)`, `.rect(cornerRadius: .containerConcentric)` (auto-aligns corner radius to the parent container/window — use this over a hardcoded radius wherever the glass shape sits inside another rounded container)
- `.buttonStyle(.glass)` — secondary actions, translucent
- `.buttonStyle(.glassProminent)` — primary actions, opaque, pair with `.tint(_:)`
- AppKit equivalent: `NSButton.bezelStyle = .glass`, `NSButton.bezelColor`

### 3.3 Hard rules from Apple's own guidance
- **Navigation layer only.** Glass belongs on toolbars, sidebars, floating controls, sheets, popovers, menus — never on content (lists, cards, tables, scrollable regions) or full-screen backgrounds.
- **Never stack glass on glass.** A glass view's content should not itself contain another `.glassEffect()` view; group siblings in one `GlassEffectContainer` instead of nesting.
- **Never mix `.regular` and `.clear`** within the same visual group — pick one per container.
- **Tint sparingly** — reserve it for the single primary action in a group; tinting everything defeats the purpose.
- Known rendering quirk (as of macOS 26 / 26.1): `.glassEffect(.regular.interactive(), in: RoundedRectangle())` can render as a capsule regardless of the shape argument — use `.buttonStyle(.glass)` instead of a manual `.glassEffect()` on custom buttons where this matters.

### 3.4 Native motion / interaction components worth defaulting to
- `matchedGeometryEffect` (§5) — geometry-based transitions, all macOS versions in scope
- `.symbolEffect(.bounce, value:)`, `.contentTransition(.symbolEffect)` — native SF Symbol state-change animation, macOS 14+, no fallback needed
- `.transition(.opacity)`, `.transition(.scale)`, `.transition(.asymmetric)` — system transition primitives, prefer over custom `AnyTransition`
- `ScrollTransition` (`.scrollTransition`) — scroll-linked native animation for content entering/leaving a scroll view's visible region
- `PhaseAnimator` / `KeyframeAnimator` — native declarative multi-step animation, preferred over manual `Timer`-driven state machines

---

## 4. Materials Fallback Matrix

| Liquid Glass (26+) | Pre-26 fallback | Use case |
|---|---|---|
| `.glassEffect(.regular)` | `.regularMaterial` | toolbars, sidebars |
| `.glassEffect(.regular.tint(_))` | `.regularMaterial` + `.overlay(color.opacity(0.12))` | accented chrome |
| `.glassEffect(.clear)` | `.ultraThinMaterial` | over media/photos |
| `GlassEffectContainer` morphing | `matchedGeometryEffect` cross-fade group | merging toolbar clusters |

---

## 5. Geometry-Matched Animation (required)

**This is the one non-negotiable motion primitive in the app.** Any element that moves between two distinct layouts/views (e.g. a card expanding into a detail view, a list row becoming a sheet header, a thumbnail becoming a full preview) must animate **from its actual prior frame/position**, not fade or slide in from a fixed offset.

### 4.1 Primary tool: `matchedGeometryEffect`
```swift
@Namespace private var heroNamespace

// Source (e.g. grid thumbnail)
ThumbnailView(item: item)
    .matchedGeometryEffect(id: item.id, in: heroNamespace)

// Destination (e.g. detail view)
DetailHeaderView(item: item)
    .matchedGeometryEffect(id: item.id, in: heroNamespace)
```

Rules for using it correctly:
- Both source and destination views must exist in the **same view hierarchy** at the transition moment (typically via a `ZStack` + conditional, or `NavigationStack` with an overlay technique — plain `NavigationLink` push breaks the shared namespace).
- Wrap the state change that triggers the transition in `withAnimation(.spring(response: 0.45, dampingFraction: 0.85))` — do not use `.easeInOut`; spring curves are what make it read as "physical" rather than "sliding."
- Tag geometry with a **stable, unique `id`** (the model's identifier, not an index) so items don't cross-match during list reordering/filtering.
- Pair with `.zIndex(1)` on the actively-transitioning element to avoid it being clipped by sibling views mid-animation.

### 4.2 macOS 26+ alternative: `GlassEffectContainer` + `.glassEffectID`
When the morphing elements are themselves glass surfaces (e.g. a toolbar button expanding into a search bar), prefer the native glass-merge API over `matchedGeometryEffect`, since it also interpolates the material/blur correctly:
```swift
GlassEffectContainer {
    if isExpanded {
        SearchField().glassEffectID("control", in: namespace)
    } else {
        SearchButton().glassEffectID("control", in: namespace)
    }
}
```
Fallback for pre-26: standard `matchedGeometryEffect` with a Material background, no morph — a clean cross-fade between the two material shapes is acceptable here since glass-merge has no real equivalent pre-26.

### 4.3 Never fall back to a fixed-origin animation
If `matchedGeometryEffect` genuinely can't be used (e.g. crossing window boundaries), the acceptable fallback is `.transition(.scale.combined(with: .opacity))` anchored with `.transition(.asymmetric(...))` — never a hardcoded slide-from-edge, since that discards the "where did this come from" cue entirely.

---

## 6. Motion Timing Reference

| Interaction | Curve | Notes |
|---|---|---|
| Geometry-matched transitions | `.spring(response: 0.45, dampingFraction: 0.85)` | §5 |
| Sheet/popover presentation | system default (do not override) | inherits Liquid Glass timing on 26+ |
| Micro-interactions (toggle, checkbox) | `.spring(response: 0.3, dampingFraction: 0.7)` | |
| List insert/remove | `.easeInOut(duration: 0.25)` combined with `.transition(.opacity.combined(with: .move))` | |
| Symbol state changes | `.symbolEffect(.bounce, value: state)` (macOS 14+) | native SF Symbols animation, no fallback needed |

---

## 7. Accessibility & Degradation

- Check `@Environment(\.accessibilityReduceMotion)`. When `true`, replace `matchedGeometryEffect` transitions with a plain crossfade (`.transition(.opacity)`) and skip spring bounce entirely (use `.linear(duration: 0.15)`).
- `@available(macOS 26, *)` gates every Liquid Glass call — see §2.3's `adaptiveGlass()` helper. No feature should be *exclusively* available on 26; only its rendering should differ.
- Verify all custom materials/glass maintain WCAG-equivalent contrast for text placed on top — Liquid Glass's dynamic light-source response can reduce contrast more than static Materials did; test in both light and dark system appearance.
- Increase Contrast / Reduce Transparency system settings: fall back all glass and material surfaces to solid `windowBackgroundColor` when `.accessibilityReduceTransparency` is `true`.

---

## 8. Implementation Checklist

- [ ] `adaptiveGlass()` helper implemented and used everywhere instead of inline `#available` checks
- [ ] Toolbar/sidebar chrome uses Liquid Glass (26+) / Material (pre-26)
- [ ] At least one hero geometry transition implemented via `matchedGeometryEffect` (or `GlassEffectContainer` morph on 26+)
- [ ] All custom animations gated behind `accessibilityReduceMotion` check
- [ ] All glass/material surfaces gated behind `accessibilityReduceTransparency` check
- [ ] Manual QA pass on macOS 14/15 (no Liquid Glass) to confirm no functional regressions, only visual fallback
- [ ] Audit custom-built UI against §3's native component inventory — replace any hand-rolled toolbar/sidebar/sheet/popover with the native equivalent
