import AppKit
import SwiftUI

/// Shared with the SwiftUI layer.
final class NotchLayoutState: ObservableObject {
    @Published var sideInset: CGFloat = 56
    /// Toggled by the controller when the dashboard window shows/hides; drives
    /// the SwiftUI grow/crossfade animation inside the dashboard.
    @Published var dashboardVisible = false
}

/// Two fixed-size panels — the window frames NEVER resize, which is what caused
/// flicker with animated setFrame on a transparent borderless panel:
///
/// - bandPanel (notch + wings): always visible, hosts the compact teasers.
/// - dashboardPanel (full dashboard size): ordered out while idle; on hover it
///   fades in while its SwiftUI surface grows from notch-size to full-size.
final class NotchWindowController {
    private let layout = NotchLayoutState()
    private var compactFrame: NSRect = .zero
    private var expandedFrame: NSRect = .zero
    private let bandPanel: NSPanel
    private let dashboardPanel: NSPanel
    private var isExpanded = false
    private var isBandVisible = true
    private var eventMonitors: [Any] = []
    private var collapseCheck: Timer?
    private var screenObserver: NSObjectProtocol?

    init(services: (weather: WeatherService, calendar: CalendarService, battery: BatteryService)) {
        bandPanel = Self.makePanel()
        dashboardPanel = Self.makePanel()

        let bandView = NSHostingView(rootView: NotchView()
            .environmentObject(layout)
            .environmentObject(services.weather)
            .environmentObject(services.calendar)
            .environmentObject(services.battery))
        let dashboardView = NSHostingView(rootView: DashboardView()
            .environmentObject(layout)
            .environmentObject(services.weather)
            .environmentObject(services.calendar)
            .environmentObject(services.battery))
        // Keep the windows in charge of sizing; otherwise SwiftUI's ideal
        // size fights the notch frames.
        bandView.sizingOptions = []
        bandView.autoresizingMask = [.width, .height]
        dashboardView.sizingOptions = []
        dashboardView.autoresizingMask = [.width, .height]
        bandPanel.contentView = bandView
        dashboardPanel.contentView = dashboardView

        computeFrames()
        bandPanel.setFrame(compactFrame, display: true)
        dashboardPanel.setFrame(expandedFrame, display: false)

        installHoverMonitors()

        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            self.computeFrames()
            self.bandPanel.setFrame(self.compactFrame, display: true)
            self.dashboardPanel.setFrame(self.expandedFrame, display: true)
        }

        Diagnostics.record("panels created, compact=\(compactFrame), expanded=\(expandedFrame), screen=\(bandPanel.screen?.localizedName ?? "nil")")
    }

    deinit {
        eventMonitors.forEach { NSEvent.removeMonitor($0) }
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
    }

    private static func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: .zero,
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
        return panel
    }

    func show() {
        bandPanel.orderFrontRegardless()
        isBandVisible = true
        Diagnostics.record("show: band frame=\(bandPanel.frame)")
    }

    func toggle() {
        if isBandVisible {
            collapse()
            bandPanel.orderOut(nil)
        } else {
            bandPanel.orderFrontRegardless()
        }
        isBandVisible.toggle()
    }

    /// Dumps the real window state so launch problems are diagnosable from Console.
    func logState() {
        Diagnostics.record("state: band=\(bandPanel.frame) dashboard=\(dashboardPanel.frame) expanded=\(isExpanded)")
    }

    // MARK: - Notch geometry

    /// Compact frame = the physical notch plus a narrow side wing on each edge
    /// (Sapphire-style): the notch itself stays pure black, and the glanceable
    /// values (temperature / battery) live in the wings, clear of the camera.
    private func computeFrames() {
        guard let screen = bandPanel.screen ?? NSScreen.main else { return }
        layout.sideInset = 56
        let sideInset = layout.sideInset

        let compactWidth: CGFloat
        let bandHeight: CGFloat
        if let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
            compactWidth = (right.minX - left.maxX) + sideInset * 2
            bandHeight = left.height
        } else {
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
        if isExpanded {
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
        guard !isExpanded else { return }
        isExpanded = true
        dashboardPanel.setFrame(expandedFrame, display: false)
        dashboardPanel.alphaValue = 0
        dashboardPanel.orderFrontRegardless()
        layout.dashboardVisible = true
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            dashboardPanel.animator().alphaValue = 1
        }
    }

    private func collapse() {
        guard isExpanded else { return }
        isExpanded = false
        layout.dashboardVisible = false
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.18
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            dashboardPanel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            guard let self, !self.isExpanded else { return }
            self.dashboardPanel.orderOut(nil)
        })
    }
}
