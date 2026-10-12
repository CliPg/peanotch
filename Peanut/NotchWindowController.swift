import AppKit
import SwiftUI

/// Manages the borderless panel that sits over the notch area at the top of the screen.
final class NotchWindowController {
    /// Slightly taller than the menu bar (32pt on notch MacBooks) so the rounded
    /// capsule visibly hangs below the menu bar even on the black notch.
    private let compactSize = NSSize(width: 220, height: 44)
    private let expandedSize = NSSize(width: 220, height: 170)
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
        // Keep the window in charge of sizing; otherwise SwiftUI's ideal size
        // fights the notch pill frames.
        hostingView.sizingOptions = []
        hostingView.autoresizingMask = [.width, .height]
        panel.contentView = hostingView

        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                               object: nil,
                                               queue: .main) { [weak self] _ in
            self?.reposition()
        }
        reposition()
        Diagnostics.record("panel created, frame=\(panel.frame), screen=\(panel.screen?.localizedName ?? "nil"), level=\(panel.level.rawValue)")
    }

    func show() {
        reposition()
        panel.orderFrontRegardless()
        isVisible = true
        Diagnostics.record("show: ordered front, frame=\(panel.frame)")
    }

    func toggle() {
        if isVisible {
            panel.orderOut(nil)
        } else {
            panel.orderFrontRegardless()
        }
        isVisible.toggle()
    }

    /// Dumps the real window state so launch problems are diagnosable from Console.
    func logState() {
        let screenName = panel.screen?.localizedName ?? "nil"
        let screenFrame = panel.screen?.frame ?? .zero
        Diagnostics.record("state: frame=\(panel.frame) visible=\(isVisible) onActiveSpace=\(panel.isOnActiveSpace) occlusion=\(panel.occlusionState) screen=\(screenName) screenFrame=\(screenFrame)")
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
