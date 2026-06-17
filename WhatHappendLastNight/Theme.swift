import SwiftUI
import AppKit
import Combine

// MARK: - Appearance preference

/// User-facing appearance preference. Defaults to following the macOS system setting.
/// Persisted in UserDefaults under `appearancePreference`. No telemetry — value is local only.
enum AppearancePreference: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: return "System"
        case .light:  return "Light"
        case .dark:   return "Dark"
        }
    }

    var sfSymbol: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light:  return "sun.max"
        case .dark:   return "moon"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light:  return .light
        case .dark:   return .dark
        }
    }
}

final class ThemeManager: ObservableObject {
    /// Explicitly declared so `ObservableObject` conformance is unambiguous under
    /// Swift 6 / strict concurrency. SwiftUI synthesizes this when it can, but
    /// declaring it ourselves removes the dependency on synthesis ordering.
    let objectWillChange = ObservableObjectPublisher()

    var preference: AppearancePreference {
        willSet { objectWillChange.send() }
        didSet  { UserDefaults.standard.set(preference.rawValue, forKey: Self.key) }
    }

    private static let key = "appearancePreference"

    init() {
        // Default to .dark — preserves the original "premium midnight" feel
        // the app shipped with. Users can switch in View → Appearance.
        let raw = UserDefaults.standard.string(forKey: Self.key) ?? AppearancePreference.dark.rawValue
        self.preference = AppearancePreference(rawValue: raw) ?? .dark
    }
}

// MARK: - Design tokens

/// Semantic color tokens. Every consumer reads from here so a single
/// preference change repaints the whole app via SwiftUI's appearance system.
/// All foreground/background pairs verified to WCAG 2.1 AA (see DESIGN_GUIDE.md §3).
enum Tokens {

    // ---- Backgrounds & surfaces ----------------------------------------
    //
    // Dark mode keeps the original premium "midnight black" feel from v1
    // (near-black, warm cream text, gold accent) — verified to WCAG 2.1 AA.

    // Light mode keeps a soft slate cast — never pure white, never clinical.
    // The setup column uses the deeper sunken tint to look like a sidebar.
    static let bg = Color(
        light: NSColor(srgbRed: 0.969, green: 0.976, blue: 0.984, alpha: 1.0),   // #F7F9FB
        dark:  NSColor(srgbRed: 0.020, green: 0.020, blue: 0.020, alpha: 1.0)    // #050505 — true black
    )

    static let surface = Color(
        light: .white,                                                            // #FFFFFF — cards pop
        dark:  NSColor(srgbRed: 0.055, green: 0.055, blue: 0.055, alpha: 1.0)    // #0E0E0E
    )

    static let surfaceSunken = Color(
        light: NSColor(srgbRed: 0.882, green: 0.906, blue: 0.933, alpha: 1.0),   // #E1E7EE — deeper sidebar
        dark:  NSColor(srgbRed: 0.078, green: 0.078, blue: 0.078, alpha: 1.0)    // #141414
    )

    static let surfaceElevated = Color(
        light: NSColor(srgbRed: 0.969, green: 0.976, blue: 0.988, alpha: 1.0),   // #F7F9FC
        dark:  NSColor(srgbRed: 0.110, green: 0.110, blue: 0.110, alpha: 1.0)    // #1C1C1C
    )

    // ---- Borders -------------------------------------------------------

    static let border = Color(
        light: NSColor(srgbRed: 0.745, green: 0.804, blue: 0.867, alpha: 1.0),   // #BECDDD — stronger card borders
        dark:  NSColor(white: 1.0, alpha: 0.06)
    )

    static let borderStrong = Color(
        light: NSColor(srgbRed: 0.580, green: 0.639, blue: 0.722, alpha: 1.0),   // #94A3B8
        dark:  NSColor(srgbRed: 0.290, green: 0.290, blue: 0.290, alpha: 1.0)    // #4A4A4A
    )

    // ---- Text ----------------------------------------------------------

    static let textPrimary = Color(
        light: NSColor(srgbRed: 0.059, green: 0.090, blue: 0.165, alpha: 1.0),   // #0F172A — deep navy ink
        dark:  NSColor(srgbRed: 0.949, green: 0.933, blue: 0.910, alpha: 1.0)    // #F2EEE8 — warm cream
    )

    static let textSecondary = Color(
        light: NSColor(srgbRed: 0.278, green: 0.333, blue: 0.412, alpha: 1.0),   // #475569 — slate
        dark:  NSColor(srgbRed: 0.659, green: 0.635, blue: 0.612, alpha: 1.0)    // #A8A29C
    )

    /// Tertiary text is for large/UI only (labels ≥ 13pt, captions). 3:1 contrast.
    static let textTertiary = Color(
        light: NSColor(srgbRed: 0.392, green: 0.455, blue: 0.545, alpha: 1.0),   // #64748B
        dark:  NSColor(srgbRed: 0.541, green: 0.518, blue: 0.494, alpha: 1.0)    // #8A847E
    )

    // ---- Accents -------------------------------------------------------
    //
    // Two roles:
    //   accentPrimary   — brand chrome (logo, slider, percentages, links).
    //                     Emerald in light, premium lemon-gold in dark.
    //   accentSecondary — "go" / "you're safe" action color. Emerald in both
    //                     modes, used for Find Me, score chips, privacy card,
    //                     and the offline badge. Reads identically in light
    //                     and dark so the trust signal is unambiguous.

    static let accentPrimary = Color(
        light: NSColor(srgbRed: 0.706, green: 0.325, blue: 0.035, alpha: 1.0),   // #B45309 — deep amber (5.2:1 on white ✓ AA)
        dark:  NSColor(srgbRed: 0.918, green: 0.702, blue: 0.031, alpha: 1.0)    // #EAB308 — lemon gold
    )

    static let accentPrimaryHover = Color(
        light: NSColor(srgbRed: 0.565, green: 0.251, blue: 0.020, alpha: 1.0),   // #904005 — darker amber
        dark:  NSColor(srgbRed: 0.984, green: 0.800, blue: 0.220, alpha: 1.0)    // #FBCC38
    )

    /// "Action" green — used for privacy accent, offline pill, score-high, checkmarks.
    static let accentSecondary = Color(
        light: NSColor(srgbRed: 0.082, green: 0.502, blue: 0.239, alpha: 1.0),   // #15803D — vibrant green (5.0:1 on white ✓ AA)
        dark:  NSColor(srgbRed: 0.133, green: 0.773, blue: 0.369, alpha: 1.0)    // #22C55E — bright emerald
    )

    /// Text on top of a filled accent button. White in light, black in dark
    /// (both gold and emerald have very high luminance in dark mode).
    /// Text/icon on a filled accent button. White works on both amber and green at AA contrast.
    static let onAccent = Color(
        light: .white,
        dark:  NSColor(srgbRed: 0.020, green: 0.020, blue: 0.020, alpha: 1.0)    // #050505
    )

    // ---- Similarity score tiers ---------------------------------------

    static let scoreHigh = Color(
        light: NSColor(srgbRed: 0.082, green: 0.502, blue: 0.239, alpha: 1.0),   // #15803D — aligns with accentSecondary
        dark:  NSColor(srgbRed: 0.133, green: 0.773, blue: 0.369, alpha: 1.0)    // #22C55E
    )
    static let scoreHighBg = Color(
        light: NSColor(srgbRed: 0.863, green: 0.969, blue: 0.906, alpha: 1.0),   // #DCF7E7 — vivid mint tint
        dark:  NSColor(srgbRed: 0.039, green: 0.110, blue: 0.071, alpha: 1.0)    // #0A1C12
    )

    static let scoreMedium = Color(
        light: NSColor(srgbRed: 0.604, green: 0.357, blue: 0.027, alpha: 1.0),   // #9A5B07
        dark:  NSColor(srgbRed: 0.949, green: 0.694, blue: 0.290, alpha: 1.0)    // #F2B14A
    )
    static let scoreMediumBg = Color(
        light: NSColor(srgbRed: 0.984, green: 0.945, blue: 0.875, alpha: 1.0),   // #FBF1DF
        dark:  NSColor(srgbRed: 0.110, green: 0.082, blue: 0.039, alpha: 1.0)    // #1C150A
    )

    static let scoreLow = Color(
        light: NSColor(srgbRed: 0.357, green: 0.392, blue: 0.439, alpha: 1.0),   // #5B6470
        dark:  NSColor(srgbRed: 0.541, green: 0.518, blue: 0.494, alpha: 1.0)    // #8A847E
    )
    static let scoreLowBg = Color(
        light: NSColor(srgbRed: 0.949, green: 0.949, blue: 0.969, alpha: 1.0),   // #F2F2F7
        dark:  NSColor(srgbRed: 0.078, green: 0.078, blue: 0.078, alpha: 1.0)    // #141414
    )

    // ---- Status -------------------------------------------------------

    static let success = Color(
        light: NSColor(srgbRed: 0.016, green: 0.463, blue: 0.298, alpha: 1.0),   // #04764C
        dark:  NSColor(srgbRed: 0.353, green: 0.820, blue: 0.722, alpha: 1.0)    // #5AD1B8
    )

    static let warning = Color(
        light: NSColor(srgbRed: 0.604, green: 0.357, blue: 0.027, alpha: 1.0),   // #9A5B07
        dark:  NSColor(srgbRed: 0.949, green: 0.694, blue: 0.290, alpha: 1.0)    // #F2B14A
    )

    static let error = Color(
        light: NSColor(srgbRed: 0.706, green: 0.137, blue: 0.094, alpha: 1.0),   // #B42318
        dark:  NSColor(srgbRed: 1.000, green: 0.541, blue: 0.541, alpha: 1.0)    // #FF8A8A
    )
}

// MARK: - Typography

enum Typography {
    // Display & headings — SF Pro (system) handles Display/Text switchover automatically above 20pt.
    static let display       = Font.system(size: 34, weight: .semibold)
    static let h1            = Font.system(size: 26, weight: .semibold)
    static let h2            = Font.system(size: 20, weight: .semibold)
    static let h3            = Font.system(size: 17, weight: .semibold)

    static let bodyLarge     = Font.system(size: 17, weight: .regular)
    static let body          = Font.system(size: 15, weight: .regular)
    static let bodyStrong    = Font.system(size: 15, weight: .semibold)

    static let label         = Font.system(size: 13, weight: .medium)
    static let caption       = Font.system(size: 12, weight: .regular)

    /// Tabular numerals — use for scores, sizes, timestamps so they don't jitter.
    static let scoreNumeral  = Font.system(size: 15, weight: .medium).monospacedDigit()
    static let scoreNumeralL = Font.system(size: 22, weight: .medium).monospacedDigit()
    static let mono          = Font.system(size: 12, weight: .regular, design: .monospaced)
}

// MARK: - Spacing & radius

enum Space {
    static let xs: CGFloat = 4
    static let s:  CGFloat = 8
    static let m:  CGFloat = 12
    static let l:  CGFloat = 16
    static let xl: CGFloat = 24
    static let xxl: CGFloat = 32
    static let xxxl: CGFloat = 48
}

enum Radius {
    static let s:  CGFloat = 6
    static let m:  CGFloat = 10
    static let l:  CGFloat = 14
    static let xl: CGFloat = 20
}

// MARK: - Color helper (light/dark pair → dynamic NSColor)

extension Color {
    /// Build a SwiftUI `Color` that switches between two NSColors as the system
    /// appearance changes. Works with `.preferredColorScheme` overrides because
    /// SwiftUI re-resolves the NSColor through the active appearance.
    init(light: NSColor, dark: NSColor) {
        let dynamic = NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .vibrantDark, .accessibilityHighContrastDarkAqua, .accessibilityHighContrastVibrantDark]) != nil
            return isDark ? dark : light
        }
        self.init(nsColor: dynamic)
    }
}

// MARK: - Score tier

enum ScoreTier {
    case high
    case medium
    case low

    static func from(_ similarity: Double) -> ScoreTier {
        if similarity >= 0.82 { return .high }
        if similarity >= 0.55 { return .medium }
        return .low
    }

    var label: String {
        switch self {
        case .high:   return "High match"
        case .medium: return "Medium match"
        case .low:    return "Low match"
        }
    }

    var color: Color {
        switch self {
        case .high:   return Tokens.scoreHigh
        case .medium: return Tokens.scoreMedium
        case .low:    return Tokens.scoreLow
        }
    }

    var bgColor: Color {
        switch self {
        case .high:   return Tokens.scoreHighBg
        case .medium: return Tokens.scoreMediumBg
        case .low:    return Tokens.scoreLowBg
        }
    }
}

// MARK: - Score chip view

/// Six-dot + percentage + word label score chip.
/// Three redundant channels so colorblind / screen-reader users get the same info.
struct ScoreChip: View {
    let similarity: Double          // 0…1
    var compact: Bool = false       // when true, drops the word label (grid tiles)

    private var tier: ScoreTier { ScoreTier.from(similarity) }
    private var percent: Int { Int((similarity * 100).rounded()) }
    private var filled: Int { max(0, min(6, Int((similarity * 6).rounded()))) }

    var body: some View {
        HStack(spacing: Space.s) {
            HStack(spacing: 3) {
                ForEach(0..<6, id: \.self) { i in
                    Circle()
                        .fill(i < filled ? tier.color : tier.color.opacity(0.20))
                        .frame(width: 6, height: 6)
                }
            }
            Text("\(percent)%")
                .font(Typography.scoreNumeral)
                .foregroundColor(tier.color)
            if !compact {
                Text(tier.label)
                    .font(Typography.label)
                    .foregroundColor(tier.color)
            }
        }
        .padding(.horizontal, Space.m)
        .padding(.vertical, Space.s - 2)
        .background(tier.bgColor)
        .clipShape(Capsule())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(tier.label), \(percent) percent similarity")
    }
}

// MARK: - Focus-ring modifier

struct FocusRingModifier: ViewModifier {
    let isVisible: Bool
    let radius: CGFloat

    func body(content: Content) -> some View {
        content.overlay(
            RoundedRectangle(cornerRadius: radius)
                .stroke(Tokens.accentPrimary, lineWidth: isVisible ? 2 : 0)
                .padding(-2)
        )
    }
}

extension View {
    func focusRing(_ visible: Bool, radius: CGFloat = Radius.m) -> some View {
        modifier(FocusRingModifier(isVisible: visible, radius: radius))
    }
}
