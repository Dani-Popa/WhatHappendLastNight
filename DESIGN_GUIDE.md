# What Happened Last Night — Design Guide

A specification for the privacy-first, local face-matching app. The product promise is **fast, local, zero-upload, zero-worry**, and every design decision below either reinforces that promise or removes friction from the three core stages: *prove privacy → pick selfie & folder → review matches*.

Scope: native macOS app (SF Pro, AppKit/SwiftUI) and a parallel React web prototype (Inter as fallback). Tokens are named identically across both so the visual language stays in lockstep.

---

## 1. Core UI/UX Improvements

### 1.1 The three-stage flow, rethought

Most local media tools dump the user into a generic "open file" dialog and a results table. That works, but it leaks anxiety — the user is never told *why* it's safe, *what* will happen, or *where* their data is going. The flow below front-loads trust, then disappears.

| Stage | Goal | One sentence the user should be thinking |
|---|---|---|
| 1. Privacy gate | Earn consent in one screen | "Okay — nothing leaves this Mac." |
| 2. Pick reference + folder | Reduce two decisions to one screen | "I just need to point it at my stuff." |
| 3. Results | Find me, fast | "There I am. Show me more." |

Cognitive-load reductions:

- **One primary action per stage.** Privacy gate has *Agree & Continue*. Setup screen has *Find Me*. Results screen has *Open in Photos / Reveal in Finder*. Secondary actions (Clear session, Settings, Re-run) live in a left sidebar or toolbar — never compete for visual weight.
- **Sequential disclosure, not steppers.** No "Step 1 of 3" header. Use a thin progress indicator only on long-running operations (folder scan, embedding compute). Stages are revealed as full-screen replacements, not stacked panels, so the user's eye is never split.
- **Persistent identity strip.** Once the selfie is chosen, a 32 pt circular thumbnail and the folder name pin to the top-left of every subsequent screen. This kills the "did it remember me?" reload reflex.
- **Show, don't tell, the privacy posture.** A small lock-with-checkmark glyph stays in the title bar with the tooltip "Offline — 0 network requests this session." If the OS-level network entitlement is denied (it should be), tint the glyph the success/teal accent. This is the most powerful trust signal in the app — make it visible always.

### 1.2 Component patterns

**A. Privacy-notice gate**

Layout: full-window, centered single column, max width 560 pt. No chrome, no sidebar.

```
┌─────────────────────────────────────────────┐
│              [shield-check icon, 56pt]      │
│                                             │
│   Three things happen on this Mac, only.    │   ← H1 (32/40, semibold)
│                                             │
│   • Photos are scanned locally with Vision  │   ← Body (15/22), one line each
│   • Your selfie never leaves the device     │     bullets are short, parallel
│   • No uploads, ever — network is blocked   │
│                                             │
│   [ Agree & Continue ]                      │   ← Primary CTA, 44 pt tall
│   View privacy details                      │   ← Tertiary link, 13/18
└─────────────────────────────────────────────┘
```

Rules:
- Three bullets, never more. Each is a *fact*, not a marketing claim. Verbs in the present tense ("are scanned", not "will be").
- The shield-check icon uses the secondary teal accent on light and on dark — it's the only color hit on the page, which makes it impossible to miss.
- "View privacy details" expands an inline disclosure (no modal, no new window) showing the App Sandbox entitlements and the data-flow diagram from `PRIVACY.md`. Tabbing once focuses the CTA — keyboard users should not have to traverse the disclosure to commit.
- Show the gate *once per release version*, not once per session — re-prompting reads as nagging. Store a tiny `privacyAccepted = "1.2.0"` in `UserDefaults`, no telemetry.

**B. Two-panel comparison view (selfie vs. matched photo)**

This is where the user spends 80% of their time. Optimize for fast eye-scanning between two faces, not "look how clever the algorithm is."

Layout (desktop, ≥ 900 pt wide):

```
┌──────────────┬──────────────────────────────────────────────┐
│  Reference   │              Match #3 of 47                  │
│              │                                              │
│  [128pt sq   │  [matched photo — fit, max 480 pt height]    │
│   selfie     │                                              │
│   thumb,     │  Similarity 92%  ●●●●●○         High match   │
│   rounded    │                                              │
│   12pt]      │  IMG_4471.HEIC  ·  3.2 MB  ·  Sat 9:42 PM    │
│              │                                              │
│  Sarah       │  [ ← ]  [ → ]   [ Reveal in Finder ]         │
│  selfie.jpg  │                                              │
└──────────────┴──────────────────────────────────────────────┘
```

Rules:
- The reference column is **fixed width (200 pt)** and visually quieter (muted surface). The match column gets the visual real estate and the brighter surface — eye lands on the match first.
- **Identical aspect-ratio crop on both face thumbnails** when overlay/face-detection is available. Mismatched crops make humans worse at comparing faces.
- Score and quality label sit immediately under the photo, *not* in a sidebar. Reading order: photo → score → metadata → actions. Top-to-bottom.
- Keyboard: `←/→` for prev/next match, `Space` to reveal in Finder, `Esc` to return to grid. Show these once as a coach-mark on first entry, then hide.
- Never auto-advance. Users want to dwell on each face.

**C. Similarity score indicator**

Three tiers, never a raw percentage alone (raw percentages without a reference frame trigger "is 73% good?" anxiety).

```
●●●●●●    92%    High match     ← teal/success token, filled dots
●●●●○○    71%    Medium match   ← amber/warning token
●●○○○○    34%    Low match      ← muted gray, treated as "unlikely"
```

Rules:
- **Color + dot count + word label.** Three redundant channels so colorblind users and accessibility-tree readers all get the same answer (rule `color-not-only`).
- Dot indicator is six segments — humans estimate 6-segment fills faster than 10. Round to nearest 1/6th visually; show exact % numerically.
- Tier thresholds: High ≥ 0.82, Medium ≥ 0.55, Low < 0.55 (tune to your embedding distribution; surface as a Settings slider later).
- In the results grid, the score indicator becomes a thin colored stripe along the bottom 3 pt of each tile — instantly scannable without numerals.

**D. Results grid / list**

Default to grid for speed-scanning, list for metadata-heavy review. Toggle in the toolbar; remember per-folder.

Grid:
- Square tiles, 160 pt on desktop (4-up at 720 pt, scales to 6/8-up wider). Padding 12 pt between tiles.
- Each tile: photo (fit-fill, centered face if Vision face-rect available) → 3 pt similarity stripe → 1-line filename below tile (truncate middle, not end — "IMG…4471.HEIC" beats "IMG_447…").
- Hover/focus: 1.5 pt focus ring in `--accent-primary`, subtle 1.02 scale (respect `prefers-reduced-motion`).
- Header row pinned: total count, current sort ("By similarity ▾"), filter chips ("High only", "Has faces").
- Empty state for "no matches above threshold": large muted illustration + "No strong matches above 55%. [Lower threshold] [Try a different selfie]" — give two recoveries, not a dead end.

List:
- Single-row tiles, 64 pt tall: thumb · filename · score chip · date · size · actions on hover.
- Sortable columns with `aria-sort`. `j/k` to move row focus (power-user feature, not advertised).

### 1.3 Spacing & hierarchy rules (apply everywhere)

- **4/8 pt grid.** Spacing tokens: `2, 4, 8, 12, 16, 24, 32, 48`. Pick one, never invent.
- **One primary CTA per screen.** Primary is filled with `--accent-primary`. Secondary is bordered. Tertiary is link-style.
- **Cards never nest more than 2 deep.** A surface inside a surface is fine; a third level is clutter.
- **Whitespace > dividers.** Use spacing to group; reach for a 1 pt divider only when the spacing alone is ambiguous.

---

## 2. Typography & Font Strategy

### 2.1 Font stack

| Platform | Heading | Body | Monospace (filenames, scores) |
|---|---|---|---|
| macOS (native) | **SF Pro Display** | **SF Pro Text** | **SF Mono** |
| Web prototype | `-apple-system, BlinkMacSystemFont, "Inter", "Segoe UI", system-ui, sans-serif` | same | `"SF Mono", "JetBrains Mono", ui-monospace, monospace` |

Why this pairing:
- SF Pro is engineered for macOS rendering, supports Dynamic Type / "Larger Text", and ships free with every Mac — there is no font swap for native users.
- Inter is metrically close enough to SF Pro that the web prototype reads identically on Macs that haven't installed `-apple-system`. Avoid Atkinson Hyperlegible here; it reads as "accessibility-themed" rather than calm/native, which conflicts with the trust posture you want.
- SF Mono / JetBrains Mono only for *tabular numerals* — filenames, similarity percentages, file sizes, timestamps. This prevents the 1 pt jitter that proportional digits cause as scores tick by during a scan.

Load Inter on the web prototype with `font-display: swap` and preload only the two weights you actually ship (500 and 600).

### 2.2 Type scale

A modular scale at ratio ~1.20 (musical minor third), anchored at 15 pt body to match SF Pro Text's optimum.

| Role | Size / Line height | Weight | Tracking | Used for |
|---|---|---|---|---|
| Display | 34 / 40 | 600 Semibold | -0.4 | Privacy gate H1, empty-state hero |
| H1 (Title) | 26 / 32 | 600 Semibold | -0.3 | Stage titles ("Pick your reference selfie") |
| H2 (Section) | 20 / 26 | 600 Semibold | -0.2 | "Recent folders", "Match details" |
| H3 (Subhead) | 17 / 22 | 600 Semibold | -0.1 | Card titles, modal titles |
| Body Large | 17 / 24 | 400 Regular | 0 | Privacy bullets, primary descriptive text |
| Body | 15 / 22 | 400 Regular | 0 | Default body, list rows |
| Body Strong | 15 / 22 | 600 Semibold | 0 | Filenames, key values inline |
| Label | 13 / 18 | 500 Medium | +0.1 | Form labels, score tier word ("High match") |
| Caption | 12 / 16 | 400 Regular | +0.2 | Metadata (date, size), helper text |
| Micro | 11 / 14 | 500 Medium | +0.4 ALL-CAPS | Section eyebrows only — use sparingly |
| Score numeral | 15–28 / 1.0× | 500 Medium **tabular-nums** | 0 | The "%" indicator. Use `font-feature-settings: "tnum"` on web. |

Rules:
- **Minimum 12 pt for any text the user must read** to comply with macOS HIG and avoid the iOS-style auto-zoom on the web prototype. Anything below 12 pt is decoration, not content.
- **Line-height 1.4–1.5 for body, 1.2–1.25 for headings.** Tight headings, breathable body.
- **Tabular numerals for all scores, percentages, timestamps, and file sizes.** Non-negotiable — it keeps the results column from juddering.
- **Never use SF Pro Display below 20 pt** (it's optimized for ≥ 20 pt) — switch to SF Pro Text automatically. SwiftUI's `Font.system` does this for you; on the web, this is what makes a system-font stack indistinguishable from real SF Pro.

### 2.3 Voice & copy

Micro-copy is part of the design. Lock these patterns into the codebase:

| Surface | Pattern | Example |
|---|---|---|
| Privacy bullets | Factual present tense, ≤ 8 words | "Your selfie never leaves the device." |
| CTAs | Verb + outcome, never "Submit" | "Find Me", "Choose folder", "Reveal in Finder" |
| Empty states | What's missing → one suggestion | "No matches above 55%. Lower the threshold or try a clearer selfie." |
| Errors | What happened → what to do | "Couldn't read 3 photos. They may be in HEIF Live Photo format — try exporting as JPEG." |
| Score labels | One word | "High match", "Medium match", "Low match" — never "85.4% confidence" alone |

---

## 3. Contrast & WCAG 2.1 AA

Every color pair below was computed and verified against WCAG 2.1 AA (4.5:1 normal text, 3:1 large text / non-text UI). The verification script is included at the end of section 4 so future palette tweaks can be re-checked in one command.

### 3.1 Verified ratios (text on its background)

| Token pair | Light | Dark |
|---|---|---|
| Text Primary on Background | **16.46:1** | **17.91:1** |
| Text Primary on Surface | 17.01:1 | 16.92:1 |
| Text Secondary on Background | 5.80:1 | 9.79:1 |
| Text Tertiary on Background *(large/UI only — 3:1)* | 4.15:1 | 6.34:1 |
| Primary Accent on Background | 8.57:1 | 8.52:1 |
| White on Primary Accent button | 8.86:1 | 8.52:1 *(dark text on light accent)* |
| Secondary Accent (teal) on Background | 5.30:1 | 10.29:1 |
| Score: High on Background | 5.10:1 | 10.29:1 |
| Score: Medium on Background | 5.25:1 | 10.22:1 |
| Score: Low on Background | 5.80:1 | 6.34:1 |
| Success / Warning / Error labels on Background | 5.49 / 5.25 / 6.36:1 | 10.29 / 10.22 / 8.47:1 |

All pass AA. Tertiary text is reserved for *large* (≥ 18 pt) or non-body UI (timestamps, captions ≥ 13 pt). Decorative borders (1.21:1 light, 1.48:1 dark) are intentionally below 3:1 because they don't carry meaning — but the **focus ring** uses Primary Accent which clears 3:1 by a wide margin in both themes.

### 3.2 Using contrast to guide the eye through the flow

- **Privacy gate**: one high-contrast accent hit (the shield-check, ~8:1) anchors the eye. Body text is high-contrast. Tertiary "View privacy details" link is the *only* lower-emphasis element — this is intentional: it's a side door, not the main door.
- **Setup screen**: the two big dropzones for selfie and folder use 1 pt accent borders at rest (3:1+), thicken to 2 pt on hover, and fill with a translucent accent wash when a file is being dragged. The CTA stays disabled (38% opacity, satisfies AA-large-only — it should not look tappable) until both inputs are valid.
- **Results screen**: the *background* of the score chip carries the tier color, not just the text. A high match has a filled teal pill (10:1 on dark, 5.6:1 on light when using white text). Low match has muted gray surface with the standard text color — *no* color, signaling "skip". This makes the entire results grid scannable in a single eye-saccade.

### 3.3 Score legibility specifics

- Always show the **numerical %**, the **dot indicator**, and the **word label**. Three redundant channels.
- Score colors are never the *only* difference between tiers — also vary saturation and dot fill.
- Run with macOS *Increase Contrast* setting: switch border opacity from `0.08` to `0.20`, and bump tertiary text to secondary. Read `NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast`.

---

## 4. Light & Dark Mode Palettes

Both palettes are tuned for a privacy/trust posture — desaturated, cool, with restrained color hits. They share token names so consumers don't care which mode is active.

### 4.1 Light Mode

| Token | Hex | Notes |
|---|---|---|
| `--bg` | `#FBFBFD` | Apple off-white. Pure white reads clinical and tiring. |
| `--surface` | `#FFFFFF` | Cards, panels. |
| `--surface-sunken` | `#F2F2F7` | Sidebar, secondary panel, inactive area. |
| `--border` | `#E5E5EA` | Decorative 1 pt dividers. |
| `--border-strong` | `#C7CDD4` | Use only when a border must signal state (validation, focus container). |
| `--text-primary` | `#1C1C1E` | Body and headings. 16.5:1 on `--bg`. |
| `--text-secondary` | `#5B6470` | Captions, helper text. 5.8:1. |
| `--text-tertiary` | `#737B85` | Metadata, disabled labels — large/UI only. 4.15:1. |
| `--accent-primary` | `#0F4C81` | Trust navy. Primary CTAs, links, focus rings. 8.57:1. |
| `--accent-primary-hover` | `#0A3A66` | Pressed/hover. |
| `--accent-secondary` | `#0F766E` | Calm teal. Privacy posture glyph, success surfaces. 5.3:1. |
| `--score-high` | `#067A66` | "High match" tier. 5.10:1. |
| `--score-high-bg` | `#E6F5F1` | Filled chip background. |
| `--score-medium` | `#9A5B07` | "Medium match" tier. 5.25:1. |
| `--score-medium-bg` | `#FBF1DF` | |
| `--score-low` | `#5B6470` | Cool gray, signals "unlikely". 5.8:1. |
| `--score-low-bg` | `#F2F2F7` | Same as `--surface-sunken`. |
| `--success` | `#04764C` | 5.49:1. |
| `--warning` | `#9A5B07` | 5.25:1. |
| `--error` | `#B42318` | 6.36:1. |
| `--on-accent` | `#FFFFFF` | Text on filled accent buttons. |
| `--focus-ring` | `#0F4C81` @ 50% outer, solid inner | 2 pt, 2 pt offset from the element. |

### 4.2 Dark Mode

| Token | Hex | Notes |
|---|---|---|
| `--bg` | `#0B0F14` | Near-black with a hint of blue. Not pure black — pure black + bright text causes halation. |
| `--surface` | `#11161D` | Cards, panels. |
| `--surface-elevated` | `#181F28` | Modal, popover, hovered card. |
| `--border` | `rgba(255,255,255,0.08)` | Decorative. |
| `--border-strong` | `#586374` | State-carrying borders. 3.16:1. |
| `--text-primary` | `#F5F7FA` | Slightly warm-white. 17.9:1. |
| `--text-secondary` | `#B0BAC7` | 9.79:1. |
| `--text-tertiary` | `#8B95A3` | 6.34:1. |
| `--accent-primary` | `#7BB0F0` | Brightened trust navy. 8.52:1. |
| `--accent-primary-hover` | `#A4C7F4` | |
| `--accent-secondary` | `#5AD1B8` | Brightened teal. 10.29:1. |
| `--score-high` | `#5AD1B8` | 10.29:1. |
| `--score-high-bg` | `#143028` | Dark filled chip. |
| `--score-medium` | `#F2B14A` | 10.22:1. |
| `--score-medium-bg` | `#2A2014` | |
| `--score-low` | `#8B95A3` | 6.34:1. |
| `--score-low-bg` | `#181F28` | |
| `--success` | `#5AD1B8` | Reuses high-match teal. |
| `--warning` | `#F2B14A` | |
| `--error` | `#FF8A8A` | 8.47:1. |
| `--on-accent` | `#0B0F14` | Dark text on light accent buttons — flips polarity for AA. |
| `--focus-ring` | `#7BB0F0` | 2 pt, 2 pt offset. |

### 4.3 Color philosophy

- **Two accents, three tiers, four states.** That's the entire vocabulary. Resist adding more.
- Navy primary = trust/lock/identity. Teal secondary = "this worked, you are safe". Never use red for matches — even a poor match is not a failure, and red here would create false negative anxiety.
- Status colors (success/warning/error) sit in their own band and never compete with the score tier colors. A "match success" toast uses `--accent-secondary` (teal); only a *system* error (couldn't read file, model failed to load) uses `--error`.

### 4.4 Contrast verification script

Save to `scripts/verify-contrast.py`. Run on any palette change.

```python
def lum(hex_color):
    h = hex_color.lstrip('#')
    r, g, b = (int(h[i:i+2], 16) / 255 for i in (0, 2, 4))
    def ch(c): return c/12.92 if c <= 0.03928 else ((c + 0.055)/1.055) ** 2.4
    return 0.2126*ch(r) + 0.7152*ch(g) + 0.0722*ch(b)

def ratio(fg, bg):
    L1, L2 = lum(fg), lum(bg)
    if L1 < L2: L1, L2 = L2, L1
    return (L1 + 0.05) / (L2 + 0.05)
```

---

## 5. Theme Toggle

### 5.1 Default behavior

**Follow the system.** macOS users set their global appearance in System Settings; an app that ignores that comes across as arrogant. SwiftUI honors this for free if you don't override `colorScheme`. On the web prototype, mirror via `@media (prefers-color-scheme: dark)` and CSS custom properties.

Allow a manual override with three options, in this order: **System (default) · Light · Dark**. Persist to `UserDefaults` on macOS, `localStorage` on web.

### 5.2 Placement

Best (macOS-native): hidden by default. Put it in the **View menu** (`View → Appearance → System / Light / Dark`), matching how Mail and Safari handle this. A toolbar toggle clutters the chrome of an app most users will never want to switch.

Acceptable: a compact segmented control in **Settings → Appearance**. Three pills: ☀ Light · ◐ System · ☾ Dark. Selected pill gets `--accent-primary` background; ARIA `radiogroup`.

Avoid: a permanently-visible toolbar moon/sun. It's a 50 ms decision the user makes once per year — it shouldn't live in their peripheral vision forever.

### 5.3 Visual state

- 16 pt icon, 1.5 pt stroke, Lucide `sun` / `moon` / `monitor` (or SF Symbols `sun.max`, `moon`, `desktopcomputer` on macOS).
- On hover, icon rotates 30° with a 180 ms ease-out and inherits `--text-primary` color. Cross-fade between sun and moon (180 ms opacity) — never use a "slide" or "wipe" transition; it draws the eye away from the actual content.
- Honor `prefers-reduced-motion` — when true, drop both the rotation and the cross-fade and just swap the icon.

### 5.4 Avoiding jarring repaints mid-session

The risk is the user switching themes while a 47-photo scan is rendering. Two safeguards:

1. **Theme tokens at the root, never inline.** Define all colors as CSS custom properties on `:root` (web) or as `Color` extensions reading from a `ThemeManager` `@EnvironmentObject` (SwiftUI). Switching theme then becomes a single attribute swap and the GPU recomposites — no React re-render, no SwiftUI view-tree rebuild.
2. **Cross-fade the window contents** when the change is user-initiated. macOS: `NSAnimationContext` with 0.2 s duration around the appearance change. Web: a `body { transition: background-color 200ms, color 200ms }` plus the same transition on `--surface`. Disable this transition during async work that touches the same node (e.g., grid layout settle) to prevent stacking transitions, and disable it entirely under `prefers-reduced-motion`.
3. **In-flight matches keep their thumbnails.** Cached image data is theme-agnostic; only the chrome around them re-tints. Never re-decode photos on theme change.

A user switching from Light → Dark while staring at the results grid should see: chrome and chips fade through 200 ms, photos themselves stay identical, focus ring stays on the same tile. No layout shift, no scroll jump, no list re-virtualization.

### 5.5 OS appearance API summary

| Platform | Read system | Override |
|---|---|---|
| macOS / SwiftUI | `@Environment(\.colorScheme)` | `.preferredColorScheme(.dark)` on the root scene |
| macOS / AppKit | `NSApp.effectiveAppearance` | `NSApp.appearance = NSAppearance(named: .darkAqua)` |
| Web | `window.matchMedia('(prefers-color-scheme: dark)')` | `data-theme="dark"` attribute on `<html>` driving custom-property overrides |

---

## Appendix: Pre-ship checklist for this app

- [ ] Privacy gate shown once per release version, not per session.
- [ ] Network entitlement disabled at the Xcode target level and verified in-app via the title-bar lock glyph.
- [ ] Selfie thumbnail visible on every screen after capture.
- [ ] All score chips render the numeral, the dot indicator, and the word label.
- [ ] Tabular numerals on every score, %, timestamp, file size.
- [ ] Focus ring visible on every interactive element (CTAs, tiles, list rows, segmented controls).
- [ ] `prefers-reduced-motion` and `Increase Contrast` both tested.
- [ ] Theme switches cross-fade in 200 ms with no layout shift.
- [ ] Verified contrast ratios after any palette change using the script in §4.4.
- [ ] No emojis as icons. SF Symbols on native, Lucide on web.
- [ ] No text below 12 pt for content. No SF Pro Display below 20 pt.
