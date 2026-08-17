import Foundation

@testable import MaillageCore

/// A throwaway vault directory under the system temp folder, loaded into a fresh
/// ``VaultStore``. `prefix` names the temp folder so a failed run's leftovers are
/// identifiable by which suite created them.
@MainActor
func makeStore(prefix: String) throws -> (store: VaultStore, root: URL) {
    let root = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("\(prefix)-\(UUID().uuidString)", isDirectory: true)
    let store = VaultStore(location: VaultLocation(root: root))
    store.load()
    return (store, root)
}

func cleanUp(_ root: URL) {
    try? FileManager.default.removeItem(at: root)
}
