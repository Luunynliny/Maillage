import AppKit
import SwiftUI

/// Swaps the cursor while the pointer is inside this view.
///
/// AppKit only changes the cursor over views that install a tracking area, and a
/// `.buttonStyle(.plain)` button installs none — so every control in this file looked inert
/// under the pointer, and a text box that draws its own border still showed an arrow.
///
/// `push`/`pop` rather than `set`: `set` is undone by the next tracking-area update, so the
/// cursor flickers back to an arrow while the pointer is still inside. The pair has to stay
/// balanced, hence `isPushed` — a second hover-in without an intervening hover-out would
/// otherwise stack pushes that never unwind. `onDisappear` covers a control that vanishes
/// while hovered, which would leave the wrong cursor stuck app-wide.
struct HoverCursor: ViewModifier {
    let cursor: NSCursor
    let isActive: Bool

    @State private var isPushed = false

    func body(content: Content) -> some View {
        content
            .onHover { isInside in
                if isInside, isActive {
                    guard !isPushed else { return }
                    isPushed = true
                    cursor.push()
                } else {
                    guard isPushed else { return }
                    isPushed = false
                    NSCursor.pop()
                }
            }
            .onChange(of: isActive) {
                // A button disabled under the pointer has to give the hand back.
                guard !isActive, isPushed else { return }
                isPushed = false
                NSCursor.pop()
            }
            .onDisappear {
                guard isPushed else { return }
                isPushed = false
                NSCursor.pop()
            }
    }
}

extension View {
    /// A pointing hand over anything that responds to a click.
    ///
    /// Applied inside the controls themselves rather than at each use site, so a new button
    /// is clickable-looking by construction and no caller has to remember. `isActive` is for
    /// controls that are only sometimes clickable — a disabled button or an action-less pill
    /// must keep the arrow, since the hand would promise a click that does nothing.
    func clickableCursor(_ isActive: Bool = true) -> some View {
        modifier(HoverCursor(cursor: .pointingHand, isActive: isActive))
    }

    /// An I-beam over a text input's whole drawn box, including the padding around the
    /// glyphs — the border is what reads as "type here", so the cursor has to agree with it.
    func textCursor() -> some View {
        modifier(HoverCursor(cursor: .iBeam, isActive: true))
    }
}
