import AppKit
import SwiftUI

/// Shared with the SwiftUI layer: drives which layout (compact band vs expanded
/// dashboard) the notch surface renders, plus the compact side-wing width.
final class NotchLayoutState: ObservableObject {
    @Published var expanded = false
    @Published var sideInset: CGFloat = 38
}

/// Manages the borderless panel that sits over the notch area at the top of the screen.
///
/// The compact window is sized to the physical notch (via the screen's auxiliary
/// top areas) so it blends into the hardware. On hover — tracked with global mouse
/// monitors against a state-based region, never against the animating window
/// frame — the panel expands horizontally into a dashboard below the notch band.
final class NotchWindowController {
    private let layout = NotchLayoutState()
    private var compactFrame: NSRect = .zero
    private var expandedFrame: NSRect = .zero
    private let panel: NSPanel
    private var isVisible = false
    private var eventMonitors: [Any] = []
    private var collapseCheck: Timer?
    private var screenObserver: NSObjectProtocol?

    init(services: (weather: WeatherService, calendar: CalendarService, battery: BatteryService)) {
        panel = NSPanel(contentRect: .zero,
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

        let hostingView = NSHostingView(rootView: NotchView()
            .environmentObject(layout)
            .environmentObject(services.weather)
            .environmentObject(services.calendar)
            .environmentObject(services.battery))
        // Keep the window in charge of sizing; otherwise SwiftUI's ideal size
        // fights the notch frames.
        hostingView.sizingOptions = []
        hostingView.autoresizingMask = [.width, .height]
        panel.contentView = hostingView

        computeFrames()
        panel.setFrame(compactFrame, display: true)

        installHoverMonitors()

        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            self.computeFrames()
            self.panel.setFrame(self.layout.expanded ? self.expandedFrame : self.compactFrame, display: true)
        }

        Diagnostics.record("panel created, compact=\(compactFrame), expanded=\(expandedFrame), screen=\(panel.screen?.localizedName ?? "nil")")
    }

    deinit {
        eventMonitors.forEach { NSEvent.removeMonitor($0) }
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
    }

    func show() {
        panel.setFrame(layout.expanded ? expandedFrame : compactFrame, display: true)
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
        Diagnostics.record("state: frame=\(panel.frame) visible=\(isVisible) onActiveSpace=\(panel.isOnActiveSpace) occlusion=\(panel.occlusionState)")
    }

    // MARK: - Notch geometry

    /// Compact frame = the physical notch plus a narrow side wing on each edge
    /// (Sapphire-style): the notch itself stays pure black, and the glanceable
    /// values (temperature / battery) live in the wings, clear of the camera.
    private func computeFrames() {
        guard let screen = panel.screen ?? NSScreen.main else { return }
        layout.sideInset = 56
        let sideInset = layout.sideInset

        let compactWidth: CGFloat
        let bandHeight: CGFloat
        if let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
            compactWidth = (right.minX - left.maxX) + sideInset * 2
            bandHeight = left.height
        } else {
            // No notch (external display): a modest pill at top-center.
            compactWidth = 210 + sideInset * 2
            bandHeight = 32
        }

        compactFrame = NSRect(x: screen.frame.midX - compactWidth / 2,
                              y: screen.frame.maxY - bandHeight,
                              width: compactWidth,
                              height: bandHeight)

        let expandedWidth = min(780, screen.frame.width - 80)
        let expandedHeight: CGFloat = 208
        expandedFrame = NSRect(x: screen.frame.midX - expandedWidth / 2,
                               y: screen.frame.maxY - expandedHeight,
                               width: expandedWidth,
                               height: expandedHeight)
    }

    // MARK: - Hover tracking (state-based region, never the animating frame)

    private func installHoverMonitors() {
        let events: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged]
        eventMonitors.append(NSEvent.addGlobalMonitorForEvents(matching: events) { [weak self] _ in
            self?.evaluateHover()
        } as Any)
        eventMonitors.append(NSEvent.addLocalMonitorForEvents(matching: events) { [weak self] event in
            self?.evaluateHover()
            return event
        } as Any)
    }

    private func evaluateHover() {
        let location = NSEvent.mouseLocation
        if layout.expanded {
            if expandedFrame.insetBy(dx: -6, dy: -6).contains(location) {
                collapseCheck?.invalidate()
                collapseCheck = nil
            } else {
                scheduleCollapse()
            }
        } else if compactFrame.insetBy(dx: -4, dy: -8).contains(location) {
            expand()
        }
    }

    private func scheduleCollapse() {
        guard collapseCheck == nil else { return }
        collapseCheck = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: false) { [weak self] _ in
            guard let self else { return }
            self.collapseCheck = nil
            if !self.expandedFrame.insetBy(dx: -6, dy: -6).contains(NSEvent.mouseLocation) {
                self.collapse()
            }
        }
    }

    private func expand() {
        layout.expanded = true
        setFrameImmediately(expandedFrame)
    }

    private func collapse() {
        layout.expanded = false
        setFrameImmediately(compactFrame)
    }

    private func setFrameImmediately(_ frame: NSRect) {
        panel.setFrame(frame, display: true)
    }
}
