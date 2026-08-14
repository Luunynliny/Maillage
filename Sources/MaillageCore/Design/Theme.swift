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
    // headers and pills so a colour always means the same thing.
    //
    // The People graph is the one documented exception: inside a labelled company bubble,
    // "purple means this is a person" is already said by the bubble, so the hue is freed
    // to carry *which employer* instead. See ``clusterPalette``.

    public static let personColor = adaptive(dark: 0x8B_6CEF, light: 0x7C_5CE0)
    public static let organizationColor = adaptive(dark: 0x4E_A8DE, light: 0x2F_86C4)
    public static let projectColor = adaptive(dark: 0xE8_9E4C, light: 0xD1_7F26)
    /// Green, the one hue free of the other three and of the People graph's cluster
    /// palette — a meeting is neither a person, a company nor a project, and shouldn't
    /// borrow the colour of any of them.
    public static let meetingColor = adaptive(dark: 0x6C_B86C, light: 0x3E_8E3E)
    /// Placeholder people — deliberately desaturated to read as "not yet known".
    public static let placeholderColor = adaptive(dark: 0x7A_7A8C, light: 0x92_95A3)

    public static func color(for kind: EntityKind) -> Color {
        switch kind {
        case .person: personColor
        case .organization: organizationColor
        case .project: projectColor
        case .meeting: meetingColor
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

    // MARK: Cluster colors

    /// One hue per employer cluster in the People graph — the only place a colour means
    /// "which company" rather than "which kind of thing".
    ///
    /// Each hue does double duty: a saturated dot at 14pt across, and the same colour at low
    /// opacity as the bubble wash behind it. That's why the wash is derived at the use site
    /// by lowering opacity rather than stored as a second palette — one value guarantees the
    /// dot and the bubble that contains it always agree.
    ///
    /// Purple is deliberately absent: it is ``accent``, which means selection everywhere in
    /// the app, and a cluster that looked selected would be a lie. Hues cycle if a vault
    /// holds more organizations than there are entries.
    public static let clusterPalette: [Color] = [
        adaptive(dark: 0x4E_A8DE, light: 0x2F_86C4),  // blue
        adaptive(dark: 0x4F_B79A, light: 0x2E_9179),  // teal
        adaptive(dark: 0xE8_9E4C, light: 0xD1_7F26),  // amber
        adaptive(dark: 0xD9_6F7A, light: 0xC2_4E5B),  // rose
        adaptive(dark: 0x7E_A845, light: 0x5F_8A2B),  // olive
        adaptive(dark: 0xC8_7BD1, light: 0xA9_55B4),  // orchid
        adaptive(dark: 0xD2_8B5A, light: 0xB3_6B3A),  // clay
    ]

    /// The unaffiliated bucket's wash — grey, so "no employer" never reads as a company.
    public static let noClusterColor = adaptive(dark: 0x7A_7A8C, light: 0x92_95A3)

    /// Hue for the cluster at `index`, or grey for the unaffiliated bucket (`nil`).
    public static func clusterColor(at index: Int?) -> Color {
        guard let index else { return noClusterColor }
        return clusterPalette[index % clusterPalette.count]
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

    /// The square a ``DisclosureChevron`` occupies. Fixed so rotating the glyph can't change
    /// the width it claims and nudge the label beside it.
    public static let chevron: CGFloat = 10

    /// Fixed widths, for a column that has to line up with the header above it.
    public enum Width {
        /// The role input in a ``RoleAssignmentField`` row. Shared with the "Role" header,
        /// so the two cannot drift apart.
        public static let roleField: CGFloat = 130
        /// An ``OrganizationBoardView`` card. Every card is the same width whatever it holds, so
        /// the board reads as a row of equals rather than as a ranking by name length.
        ///
        /// Grew with ``Theme/Avatar/card``, and by exactly as much: the title shares its line
        /// with the logo and the status, so a bigger logo is width taken straight off the name —
        /// at 240 "Dark Matter Supply" started wrapping, which cost a line of card height to
        /// save none.
        public static let boardCard: CGFloat = 260
        /// A ``ProjectRosterView`` row's role column, and the heading over it.
        public static let rosterRole: CGFloat = 150
        /// Its employer column. Wider than the role beside it because this cell carries a logo
        /// as well as a name, and the logo eats into the width the name had — enough of it that
        /// at the role column's 150 a company like "Democratic Order of Planets" wrapped to a
        /// third line and pushed the whole row taller. Long names still wrap to two, which
        /// ``EntityLink`` allows on purpose: wrapping a name is better than truncating it when
        /// the name is the identification.
        public static let rosterEmployer: CGFloat = 190
    }

    /// Fixed heights, for surfaces that must not grow to whatever their content wants.
    public enum Height {
        /// The tallest an unfolded details section may get before it scrolls. A subject with
        /// thirty backlinks would otherwise push the graph out of the window.
        public static let detailsMax: CGFloat = 340
    }

    /// The circle that stands for one entity: its logo, or its kind's glyph until it has one.
    ///
    /// Several sizes rather than one, unlike the dot this replaced. A dot carries no detail, so
    /// one size fit everywhere; a logo has to be big enough to recognise, and how much room
    /// there is differs — a title band can afford more than a scrolling list of rows, and a
    /// board card packs many into a narrow column.
    ///
    /// Each is measured against the text it sits beside, not chosen as a round number: a circle
    /// shorter than the type next to it reads as a smudge on a label rather than as a picture of
    /// something, which is the failure these sizes exist to avoid.
    public enum Avatar {
        /// Rows: the sidebar, the command palette, the editors' option lists. Every one of those is a
        /// list as long as the vault, where a taller row costs entries visible at once.
        public static let row: CGFloat = 20
        /// A table row that exists to be read *across*: ``ProjectRosterView``'s participant and
        /// employer columns.
        ///
        /// Bigger than ``row`` because the trade-off inverts. A roster is as long as one
        /// project — a handful of people — so row height is nearly free, and the pane is scanned
        /// down two columns of logos to see who is on this and who they work for. At 20 the
        /// employer logos were the same height as the company names beside them and read as
        /// bullets rather than as marks you could tell apart.
        public static let tableRow: CGFloat = 28
        /// The centre pane's title band, beside a 15pt heading over an 11pt subtitle.
        ///
        /// Matched to the height of those two lines together rather than to the heading alone.
        /// At 28 it was sized to the name and came out shorter than the text block beside it,
        /// which put a 28pt-wide crop of a face next to two lines of type — too small to
        /// recognise, and visibly not aligned with either line. Squaring it off against the
        /// whole block costs no band height, since the text already claims that much.
        public static let header: CGFloat = 40
        /// A board card's title: the project the card is about.
        ///
        /// The board's job is "which projects, staffed by whom", and both halves of that are
        /// answered by a picture — so this is sized to be recognised across a pane rather than to
        /// fit tightly against its own heading. It stays a step above ``cardMember`` so a card
        /// still reads as one subject over a list, which is the thing a single size destroyed.
        public static let card: CGFloat = 34
        /// A person listed on a board card.
        ///
        /// Its own token rather than ``row``, which the sidebar and the palette also read: those
        /// are vault-length lists where height is the scarce thing, while a card holds a project's
        /// worth of people and can afford faces you can tell apart without reading the names.
        public static let cardMember: CGFloat = 26
        /// The editors' logo well, where the image is the subject rather than a marker.
        public static let well: CGFloat = 64
    }

    // MARK: Typography

    public enum Font {
        public static let title = SwiftUI.Font.system(size: 22, weight: .semibold)
        public static let heading = SwiftUI.Font.system(size: 15, weight: .semibold)
        public static let body = SwiftUI.Font.system(size: 13)
        public static let caption = SwiftUI.Font.system(size: 11)
        /// The command palette's query, larger than body text the way Obsidian's is.
        public static let paletteQuery = SwiftUI.Font.system(size: 16)
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
