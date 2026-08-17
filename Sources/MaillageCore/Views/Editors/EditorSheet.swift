import SwiftUI

/// Shared sheet frame so every editor has identical padding, title and footer.
struct EditorSheet<Content: View>: View {
    let title: String
    let subtitle: String?
    let confirmTitle: String
    let isConfirmEnabled: Bool
    let onConfirm: () -> Void
    let onCancel: () -> Void
    @ViewBuilder let content: Content

    init(
        title: String,
        subtitle: String? = nil,
        confirmTitle: String = "Save",
        isConfirmEnabled: Bool = true,
        onConfirm: @escaping () -> Void,
        onCancel: @escaping () -> Void,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.confirmTitle = confirmTitle
        self.isConfirmEnabled = isConfirmEnabled
        self.onConfirm = onConfirm
        self.onCancel = onCancel
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.large) {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text(title)
                    .font(Theme.Font.heading)
                    .foregroundStyle(Theme.textNormal)
                if let subtitle {
                    Text(subtitle)
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            content

            HStack {
                Spacer()
                SecondaryButton("Cancel", action: onCancel)
                PrimaryButton(confirmTitle, isEnabled: isConfirmEnabled, action: onConfirm)
            }
        }
        .padding(Theme.Spacing.xl)
        .frame(width: 460)
        .background(Theme.bgSecondary)
    }
}
