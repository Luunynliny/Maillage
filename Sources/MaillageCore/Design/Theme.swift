import SwiftUI

/// Obsidian's design tokens, ported from its CSS custom properties.
///
/// Every colour, radius and spacing value in the app comes from here — views must
/// never hardcode a literal. Both schemes are defined so the app follows the system
/// appearance the way Obsidian does.
public enum Theme {
    // MARK: Colors

    /// Window and primary surface background.
    public static let bgPrimary = adaptive(dark: 0x1E_1E1E, light: 0xFF_FFFF)
    /// Sidebar, toolbars and inset surfaces.
    public static let bgSecondary = adaptive(dark: 0x26_2626, light: 0xF5_F6F8)
    /// Cards and raised surfaces.
    public static let bgSurface = adaptive(dark: 0x2A_2A2A, light: 0xFF_FFFF)
    /// Hovered rows and subtle fills.
    public static let bgHover = adaptive(dark: 0x36_3636, light: 0xEB_EDF2)

    /// Body text.
    public static let textNormal = adaptive(dark: 0xDA_DADA, light: 0x1F_2023)
    /// Secondary and supporting text.
    public static let textMuted = adaptive(dark: 0x99_9999, light: 0x6E_7176)
    /// Captions and metadata.
    public static let textFaint = adaptive(dark: 0x6E_6E6E, light: 0x9A_9DA3)

    /// Obsidian's signature purple, used for selection and links.
    public static let accent = adaptive(dark: 0x8B_6CEF, light: 0x7C_5CE0)
    public static let accentHover = adaptive(dark: 0xA2_8BF2, light: 0x6A_49D6)

    /// Hairline borders. Obsidian uses borders, not shadows, to separate surfaces.
    public static let border = adaptive(dark: 0x3A_3A3A, light: 0xE0_E2E7)
    public static let borderStrong = adaptive(dark: 0x4A_4A4A, light: 0xC9_CCD3)

    // MARK: Entity colors
    // One hue per entity kind, used consistently by the sidebar dots, detail
    // headers and graph nodes so a colour always means the same thing.

    public static let personColor = adaptive(dark: 0x8B_6CEF, light: 0x7C_5CE0)
    public static let organizationColor = adaptive(dark: 0x4E_A8DE, light: 0x2F_86C4)
    public static let projectColor = adaptive(dark: 0xE8_9E4C, light: 0xD1_7F26)
    /// Placeholder people — deliberately desaturated to read as "not yet known".
    public static let placeholderColor = adaptive(dark: 0x7A_7A8C, light: 0x92_95A3)

    public static func color(for kind: EntityKind) -> Color {
        switch kind {
        case .person: personColor
        case .organization: organizationColor
        case .project: projectColor
        }
    }

    /// Colour for a person, accounting for placeholder state.
    public static func color(for person: Person) -> Color {
        person.placeholder ? placeholderColor : personColor
    }

    public static func color(for entity: AnyEntity) -> Color {
        if case .person(let person) = entity { return color(for: person) }
        return color(for: entity.kind)
    }

    // MARK: Metrics

    public enum Radius {
        public static let small: CGFloat = 4
        public static let medium: CGFloat = 6
        public static let large: CGFloat = 10
    }

    public enum Spacing {
        public static let xs: CGFloat = 4
        public static let small: CGFloat = 8
        public static let medium: CGFloat = 12
        public static let large: CGFloat = 16
        public static let xl: CGFloat = 24
    }

    /// Obsidian draws separators as true hairlines.
    public static let hairline: CGFloat = 1

    // MARK: Typography

    public enum Font {
        public static let title = SwiftUI.Font.system(size: 22, weight: .semibold)
        public static let heading = SwiftUI.Font.system(size: 15, weight: .semibold)
        public static let body = SwiftUI.Font.system(size: 13)
        public static let caption = SwiftUI.Font.system(size: 11)
        /// Section headers in the sidebar: small, uppercase, tracked out.
        public static let sectionHeader = SwiftUI.Font.system(size: 10, weight: .semibold)
        /// Ids and emails, where character disambiguation matters.
        public static let mono = SwiftUI.Font.system(size: 12, design: .monospaced)
    }

    // MARK: Helpers

    /// Builds a colour that resolves per appearance, so light and dark are handled
    /// in one place rather than branched at every use site.
    static func adaptive(dark: UInt32, light: UInt32) -> Color {
        #if canImport(AppKit)
            return Color(
                nsColor: NSColor(name: nil) { appearance in
                    let isDark =
                        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                    return NSColor(hex: isDark ? dark : light)
                })
        #else
            return Color(hex: dark)
        #endif
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }
}

#if canImport(AppKit)
    extension NSColor {
        convenience init(hex: UInt32) {
            self.init(
                srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
                green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255,
                alpha: 1
            )
        }
    }
#endif
