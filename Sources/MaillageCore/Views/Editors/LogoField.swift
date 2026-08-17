import AppKit
import SwiftUI

/// What the sheet should do to the entity's logo when it is saved.
///
/// A value rather than an immediate write, for the same reason membership is: an abandoned sheet
/// must leave the vault untouched. It is also forced by fact — while creating, there is no id to
/// write a logo *for* until `createPerson`/`createOrganization`/`createProject` has returned one.
enum LogoChange: Equatable {
    case unchanged
    /// Already squared 512×512 PNG data, converted at pick time.
    case replaced(Data)
    case removed
}

extension VaultStore {
    /// Commits what a ``LogoField`` staged. Lives here rather than on the store, so the store
    /// stays unaware of a type that only exists to defer one of its own writes.
    func apply(_ change: LogoChange, kind: EntityKind, id: EntityID) {
        switch change {
        case .unchanged: break
        case .replaced(let data): setLogo(kind: kind, id: id, pngData: data)
        case .removed: removeLogo(kind: kind, id: id)
        }
    }
}

/// Picks the image that stands for an entity, shared by the three editors.
///
/// Converts at pick time rather than at save, so the preview is the actual cropped result
/// instead of a promise about it — the crop discards the ends of a wide image, and seeing that
/// before committing is the difference between a choice and a surprise.
struct LogoField: View {
    @Environment(VaultStore.self) private var store

    let kind: EntityKind
    /// `nil` while creating, when there is no stored logo to start from.
    let existingID: EntityID?
    @Binding var change: LogoChange

    /// What went wrong with the last pick. Shown beside the field, since a file that won't
    /// convert is about *this* control and not the sheet as a whole.
    @State private var failure: String?
    @State private var isTargeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text("Logo")
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.textMuted)

            HStack(spacing: Theme.Spacing.medium) {
                preview

                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    HStack(spacing: Theme.Spacing.small) {
                        SecondaryButton("Choose Image…", icon: "photo", action: choose)

                        // Only offered when there is something to clear: with no logo it would
                        // be a button that does nothing, which the cursor rule forbids
                        // promising. `.removed` on a creating sheet is unreachable for the same
                        // reason — there is nothing there to remove.
                        if hasSomethingToRemove {
                            SecondaryButton("Remove", icon: "trash") {
                                change = .removed
                                failure = nil
                            }
                        }
                    }

                    Text(caption)
                        .font(Theme.Font.caption)
                        .foregroundStyle(failure == nil ? Theme.textFaint : Theme.projectColor)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }
        }
    }

    /// The round well. Doubles as the drop target, so dragging a file onto the picture you are
    /// replacing works — the gesture the image itself invites.
    private var preview: some View {
        stagedOrStored
            .frame(width: Theme.Avatar.well, height: Theme.Avatar.well)
            .overlay {
                Circle().strokeBorder(
                    isTargeted ? Theme.accent : Theme.border,
                    lineWidth: isTargeted ? 2 : Theme.hairline)
            }
            .contentShape(Circle())
            .onTapGesture(perform: choose)
            .clickableCursor()
            .help("Choose an image for this \(kind.rawValue)")
            .dropDestination(for: URL.self) { urls, _ in
                guard let url = urls.first else { return false }
                return convert(url)
            } isTargeted: {
                isTargeted = $0
            }
    }

    @ViewBuilder
    private var stagedOrStored: some View {
        switch change {
        case .replaced(let data):
            if let image = NSImage(data: data) {
                Image(nsImage: image)
                    .resizable()
                    .clipShape(Circle())
            } else {
                glyphWell
            }
        case .removed:
            glyphWell
        case .unchanged:
            if let existingID {
                // The store's own avatar, so the well shows exactly what the rest of the app
                // shows — including its glyph fallback when there is no logo yet.
                EntityAvatar(kind: kind, id: existingID, size: Theme.Avatar.well)
            } else {
                glyphWell
            }
        }
    }

    /// The empty state, drawn without the store because a staged removal must show as empty
    /// even while the file is still on disk.
    private var glyphWell: some View {
        Circle()
            .fill(Theme.color(for: kind).opacity(0.15))
            .overlay {
                Image(systemName: kind.symbolName)
                    .font(.system(size: Theme.Avatar.well * 0.46))
                    .foregroundStyle(Theme.color(for: kind))
            }
    }

    private var hasSomethingToRemove: Bool {
        switch change {
        case .replaced: true
        case .removed: false
        case .unchanged: existingID.map { store.hasLogo(kind: kind, id: $0) } ?? false
        }
    }

    private var caption: String {
        if let failure { return failure }
        return
            "Any image. It's cropped to a square and stored at \(ImageSquarer.side)×\(ImageSquarer.side)."
    }

    private func choose() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = ImageSquarer.readableTypes
        panel.prompt = "Use This Image"
        panel.message = "Pick an image. It will be cropped to a square."
        if panel.runModal() == .OK, let url = panel.url {
            _ = convert(url)
        }
    }

    /// Returns whether the file was usable, which is also what `dropDestination` wants — a
    /// rejected drop should animate back rather than silently vanish.
    @discardableResult
    private func convert(_ url: URL) -> Bool {
        do {
            change = .replaced(try ImageSquarer.squarePNG(contentsOf: url))
            failure = nil
            return true
        } catch {
            failure = error.localizedDescription
            return false
        }
    }
}
