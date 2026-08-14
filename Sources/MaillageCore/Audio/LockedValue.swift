import Foundation

/// A value one thread writes often and another reads occasionally, guarded by a lock rather
/// than hopped onto an actor.
///
/// The writer for every use in this directory is a real-time Core Audio callback, which must
/// never `await` or block on the main actor — doing so risks the dropped-buffer glitch the
/// whole real-time contract exists to prevent. ``AudioCaptureSession`` instead polls this from
/// a timer at a UI-appropriate rate, decoupling "how often the level updates" from "how often
/// the hardware calls back".
final class LockedValue<Value>: @unchecked Sendable {
    private var value: Value
    private let lock = NSLock()

    init(_ value: Value) {
        self.value = value
    }

    func get() -> Value {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    func set(_ newValue: Value) {
        lock.lock()
        defer { lock.unlock() }
        value = newValue
    }
}
