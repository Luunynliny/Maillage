import AppKit
import SwiftUI

/// First-launch welcome: confirm the default vault folder or choose another.
///
/// Shown only when no vault exists yet, so returning users go straight to their data.
struct VaultPicker: View {
    @Environment(VaultStore.self) private var store
    @Binding var isPresented: Bool

    @State private var chosenRoot: URL?

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.large) {
            VStack(alignment: .leading, spacing: Theme.Spacing.small) {
                Text("Welcome to maillage")
                    .font(Theme.Font.title)
                    .foregroundStyle(Theme.textNormal)
                Text(
                    "Your people, organizations and projects are stored as plain markdown files "
                        + "with YAML frontmatter — readable in Finder, versionable with git, and "
                        + "openable in Obsidian."
                )
                .font(Theme.Font.body)
                .foregroundStyle(Theme.textMuted)
                .fixedSize(horizontal: false, vertical: true)
            }

            Card {
                MetadataRow("Folder", value: displayPath, isMonospaced: true)
            }

            HStack(spacing: Theme.Spacing.small) {
                SecondaryButton("Choose Another Folder…", icon: "folder") { chooseFolder() }
                Spacer()
                PrimaryButton("Create Vault") { confirm() }
            }
        }
        .padding(Theme.Spacing.xl)
        .frame(width: 520)
        .background(Theme.bgSecondary)
    }

    private var root: URL {
        chosenRoot ?? store.location.root
    }

    private var displayPath: String {
        root.path.replacingOccurrences(of: NSHomeDirectory(), with: "~")
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Use This Folder"
        panel.message = "Pick where maillage should keep your vault."
        panel.directoryURL = root.deletingLastPathComponent()
        if panel.runModal() == .OK, let url = panel.url {
            chosenRoot = url
        }
    }

    private func confirm() {
        if let chosenRoot {
            store.changeLocation(to: VaultLocation(root: chosenRoot))
        } else {
            store.load()
        }
        isPresented = false
    }
}
