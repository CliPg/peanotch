import AppKit
import SwiftUI

/// Manages the borderless panel that sits over the notch area at the top of the screen.
final class NotchWindowController {
    private let compactSize = NSSize(width: 220, height: 36)
    private let expandedSize = NSSize(width: 220, height: 150)
    private let panel: NSPanel
    private var isVisible = false

    init() {
        panel = NSPanel(contentRect: NSRect(origin: .zero, size: compactSize),
                        styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered,
                        defer: false)
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isMovable = false
        panel.hidesOnDeactivate = false

        let hostingView = NSHostingView(rootView: NotchView(onHoverChange: { [weak self] hovering in
            self?.setExpanded(hovering)
        }))
        hostingView.autoresizingMask = [.width, .height]
        panel.contentView = hostingView

        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                               object: nil,
                                               queue: .main) { [weak self] _ in
            self?.reposition()
        }
        reposition()
    }

    func show() {
        panel.orderFrontRegardless()
        isVisible = true
    }

    func toggle() {
        if isVisible {
            panel.orderOut(nil)
        } else {
            panel.orderFrontRegardless()
        }
        isVisible.toggle()
    }

    private func setExpanded(_ expanded: Bool) {
        let target = expanded ? expandedSize : compactSize
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.28
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().setFrame(frame(for: target), display: true)
        }
    }

    private func reposition() {
        panel.setFrame(frame(for: compactSize), display: true)
    }

    private func frame(for size: NSSize) -> NSRect {
        guard let screen = panel.screen ?? NSScreen.main else { return .zero }
        return NSRect(x: screen.frame.midX - size.width / 2,
                      y: screen.frame.maxY - size.height,
                      width: size.width,
                      height: size.height)
    }
}
