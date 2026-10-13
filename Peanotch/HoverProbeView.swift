import AppKit

/// Content view for the hover probe panel: reports pointer enter/move/exit via
/// NSTrackingArea (position-driven, works while the cursor is over the menu
/// bar where NSEvent monitors receive nothing) and passes every click through
/// to whatever is underneath.
final class HoverProbeView: NSView {
    var onHoverEvent: () -> Void = {}

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero,
                                       options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect],
                                       owner: self,
                                       userInfo: nil))
    }

    override func mouseEntered(with event: NSEvent) { onHoverEvent() }
    override func mouseMoved(with event: NSEvent) { onHoverEvent() }
    override func mouseExited(with event: NSEvent) { onHoverEvent() }

    /// Click-through: tracking areas still fire with a nil hit-test view.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
