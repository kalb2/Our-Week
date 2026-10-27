import SwiftUI
import UIKit

extension View {
    /// Shows the control only when it can act. No disabled or ghost buttons.
    @ViewBuilder
    func shown(_ visible: Bool) -> some View {
        if visible { self }
    }

    /// Hides a control but keeps its slot, so a row of icons does not jump.
    func hiddenKeepingSlot(_ hidden: Bool) -> some View {
        opacity(hidden ? 0 : 1)
            .allowsHitTesting(!hidden)
            .accessibilityHidden(hidden)
    }
}

/// Tapping outside a text field or text view closes the keyboard, on every screen and sheet.
/// Taps still reach the control underneath; a tap that moves focus to another field keeps it.
enum TapAwayKeyboard {
    private static var installed = Set<ObjectIdentifier>()
    private static let handler = Handler()

    private static var observing = false

    @MainActor
    static func install() {
        if !observing {
            observing = true
            // The window may not exist yet on first appear, so also attach as windows show up.
            NotificationCenter.default.addObserver(forName: UIWindow.didBecomeKeyNotification, object: nil, queue: .main) { note in
                guard let window = note.object as? UIWindow else { return }
                MainActor.assumeIsolated { attach(to: window) }
            }
            DispatchQueue.main.async { install() }
        }
        for scene in UIApplication.shared.connectedScenes {
            guard let windowScene = scene as? UIWindowScene else { continue }
            for window in windowScene.windows { attach(to: window) }
        }
    }

    @MainActor
    private static func attach(to window: UIWindow) {
        guard !installed.contains(ObjectIdentifier(window)) else { return }
        installed.insert(ObjectIdentifier(window))
        let tap = UITapGestureRecognizer(target: handler, action: #selector(Handler.tapped(_:)))
        tap.cancelsTouchesInView = false
        tap.delaysTouchesEnded = false
        tap.requiresExclusiveTouchType = false
        tap.delegate = handler
        window.addGestureRecognizer(tap)
    }

    private final class Handler: NSObject, UIGestureRecognizerDelegate {
        private weak var editingAtTouch: UIResponder?

        @objc func tapped(_ recognizer: UITapGestureRecognizer) {
            guard let before = editingAtTouch, let window = recognizer.view as? UIWindow else { return }
            editingAtTouch = nil
            // Let the tapped control act first; keep focus if it moved to another field.
            DispatchQueue.main.async {
                if UIResponder.currentEditor === before {
                    window.endEditing(true)
                }
            }
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            guard let editor = UIResponder.currentEditor else { return false }
            var view: UIView? = touch.view
            while let current = view {
                if current is UITextField || current is UITextView || current is UISearchBar || current is UIKeyInput { return false }
                view = current.superview
            }
            editingAtTouch = editor
            return true
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            true
        }
    }
}

private extension UIResponder {
    private static weak var found: UIResponder?

    /// The text input that is editing now, if any.
    static var currentEditor: UIResponder? {
        found = nil
        UIApplication.shared.sendAction(#selector(UIResponder.ow_capture), to: nil, from: nil, for: nil)
        guard let responder = found, responder is UIKeyInput, !(responder is UIWindow) else { return nil }
        return responder
    }

    @objc func ow_capture() {
        UIResponder.found = self
    }
}
