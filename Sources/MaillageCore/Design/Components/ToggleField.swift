import SwiftUI

/// A switch with a label and a line explaining what turning it on does.
///
/// The explanation is part of the control rather than optional chrome: a switch in a form
/// changes what the rest of the form means, which a bare label can't convey.
public struct ToggleField: View {
    private let label: String
    private let caption: String
    @Binding private var isOn: Bool

    public init(_ label: String, caption: String, isOn: Binding<Bool>) {
        self.label = label
        self.caption = caption
        self._isOn = isOn
    }

    public var body: some View {
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text(label)
                    .font(Theme.Font.body)
                    .foregroundStyle(Theme.textNormal)
                Text(caption)
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .toggleStyle(.switch)
        .tint(Theme.accent)
    }
}
