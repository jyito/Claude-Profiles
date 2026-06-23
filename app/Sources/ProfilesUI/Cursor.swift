import SwiftUI
import AppKit

/// Reusable pointing-hand cursor on hover. macOS doesn't show the pointer cursor
/// on SwiftUI buttons by default; this opts every interactive control into it.
///
/// `onHover` does NOT fire under `ImageRenderer` (the headless snapshot path), so
/// this is snapshot-safe — it changes no goldens. Push/pop keeps the cursor stack
/// balanced as the pointer enters/leaves the control.
public extension View {
    func pointerCursor() -> some View {
        onHover { inside in
            if inside {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
    }
}
