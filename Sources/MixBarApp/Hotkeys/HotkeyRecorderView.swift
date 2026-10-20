import AppKit
import SwiftUI

/// Invisible AppKit view laid over the shortcut field. Using an `NSView` (and
/// not a local `NSEvent` monitor) keeps the key handling inside the responder
/// chain, so it stays on the main actor and needs no sendable closures.
struct HotkeyRecorderView: NSViewRepresentable {
    let isRecording: Bool
    let help: String
    let accessibilityLabel: String
    let onBegin: () -> Void
    let onKeyDown: (NSEvent) -> Bool
    let onCancel: () -> Void

    func makeNSView(context: Context) -> HotkeyRecorderNSView {
        let view = HotkeyRecorderNSView()
        configure(view)
        return view
    }

    func updateNSView(_ view: HotkeyRecorderNSView, context: Context) {
        configure(view)
    }

    private func configure(_ view: HotkeyRecorderNSView) {
        view.onBeginRecording = onBegin
        view.onKeyDown = onKeyDown
        view.onCancelRecording = onCancel
        view.toolTip = help
        view.setAccessibilityElement(true)
        view.setAccessibilityRole(.button)
        view.setAccessibilityLabel(accessibilityLabel)
        view.setAccessibilityHelp(help)
        view.wantsKeyboardFocus = isRecording
        view.syncFirstResponder()
    }
}

final class HotkeyRecorderNSView: NSView {
    var onBeginRecording: (() -> Void)?
    var onKeyDown: ((NSEvent) -> Bool)?
    var onCancelRecording: (() -> Void)?
    var wantsKeyboardFocus = false

    override var acceptsFirstResponder: Bool { true }

    /// Clicking any other control while the recorder waits for a key must end
    /// the recording; otherwise global shortcuts would stay unregistered.
    override func resignFirstResponder() -> Bool {
        if wantsKeyboardFocus {
            onCancelRecording?()
        }
        return super.resignFirstResponder()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        syncFirstResponder()
    }

    func syncFirstResponder() {
        guard let window else { return }
        if wantsKeyboardFocus {
            if window.firstResponder !== self {
                window.makeFirstResponder(self)
            }
        } else if window.firstResponder === self {
            window.makeFirstResponder(nil)
        }
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        onBeginRecording?()
    }

    override func keyDown(with event: NSEvent) {
        if onKeyDown?(event) == true { return }
        super.keyDown(with: event)
    }

    /// Menu key equivalents (⌘Q, ⌘W, …) are offered to the view hierarchy
    /// before the main menu; while recording they belong to the recorder.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.type == .keyDown, onKeyDown?(event) == true else {
            return super.performKeyEquivalent(with: event)
        }
        return true
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }
}
