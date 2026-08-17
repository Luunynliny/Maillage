import SwiftUI

/// One line of entity metadata, e.g. `Email  marie@example.com`. The label sits in a
/// fixed-width column so stacked rows align — see ``MetadataList``.
public struct MetadataRow: View {
    private let label: String
    private let value: String
    private let isMonospaced: Bool

    public init(_ label: String, value: String, isMonospaced: Bool = false) {
        self.label = label
        self.value = value
        self.isMonospaced = isMonospaced
    }

    public var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.small) {
            Text(label)
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.textFaint)
                .frame(width: 70, alignment: .leading)
            Text(value)
                .font(isMonospaced ? Theme.Font.mono : Theme.Font.body)
                .foregroundStyle(Theme.textNormal)
                .textSelection(.enabled)
            Spacer(minLength: 0)
        }
    }
}

/// An entity's short facts, one per line with the labels in a column:
///
/// ```
/// Role    Head of Engineering
/// Email   marie@example.com
/// Added   2026-08-06
/// ```
///
/// One fact per row rather than a wrapping single line: values are read by scanning down
/// the label column, and a run-on line reflows unpredictably as the pane is resized, so
/// `Added` lands in a different place for every entity. Rows are ``MetadataRow``, so this
/// and the vault picker render key/value pairs identically.
///
/// Sized to its content, unlike ``Card``, which stretches to the full pane and turns two
/// short values into a conspicuous box. Use this in the detail pane, where the metadata
/// should sit quietly under the title; ``Card`` is for surfaces that need to read as a panel.
public struct MetadataList: View {
    /// One label/value pair. `isMonospaced` is for ids and emails.
    public struct Item: Identifiable {
        let label: String
        let value: String
        let isMonospaced: Bool

        public var id: String { label }

        public init(_ label: String, value: String, isMonospaced: Bool = false) {
            self.label = label
            self.value = value
            self.isMonospaced = isMonospaced
        }
    }

    private let items: [Item]

    public init(_ items: [Item]) {
        self.items = items
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            ForEach(items) { item in
                MetadataRow(item.label, value: item.value, isMonospaced: item.isMonospaced)
            }
        }
    }
}
