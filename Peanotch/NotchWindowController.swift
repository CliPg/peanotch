import AppKit
import SwiftUI

/// Shared with the SwiftUI layer: the surface geometry + expansion state.
final class NotchLayoutState: ObservableObject {
    @Published var expanded = false
    @Published var sideInset: CGFloat = 56
    @Published var compactWidth: CGFloat = 291
    @Published var compactHeight: CGFloat = 32
    @Published var expandedWidth: CGFloat = 780
    @Published var expandedHeight: CGFloat = 208
}

/// Sapphire-style notch controller.
///
/// The window is a large FIXED-SIZE canvas (full screen width, ~42% of the
/// screen height) that never resizes — resizing a transparent borderless panel
/// is what caused ghosting/flicker. The notch surface animates from compact to
/// expanded size entirely inside the canvas via a SwiftUI spring. The canvas is
/// mouse-transparent (`ignoresMouseEvents`) except while the pointer is over
/// the surface, so the menu bar stays clickable.
final class NotchWindowController {
    private let layout = NotchLayoutState()
    private var canvasFrame: NSRect = .zero
    private var compactFrame: NSRect = .zero   // surface rect on screen when compact
    private var expandedFrame: NSRect = .zero  // surface rect on screen when expanded
    private let panel: NSPanel
    private var isExpanded = false
    private var isVisible = true
    private var eventMonitors: [Any] = []
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
        panel.ignoresMouseEvents = true

        let hostingView = NSHostingView(rootView: NotchView(onBandTap: { [weak self] in
            self?.toggleExpansion()
        })
            .environmentObject(layout)
            .environmentObject(services.weather)
            .environmentObject(services.calendar)
            .environmentObject(services.battery))
        // The canvas window owns its size; SwiftUI animates within it.
        hostingView.sizingOptions = []
        hostingView.autoresizingMask = [.width, .height]
        panel.contentView = hostingView

        computeFrames()
        panel.setFrame(canvasFrame, display: true)

        installHoverMonitors()

        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            self.computeFrames()
            self.panel.setFrame(self.canvasFrame, display: true)
        }

        Diagnostics.record("canvas created, frame=\(canvasFrame), compact=\(compactFrame), expanded=\(expandedFrame), screen=\(panel.screen?.localizedName ?? "nil")")
    }

    deinit {
        eventMonitors.forEach { NSEvent.removeMonitor($0) }
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
    }

    func show() {
        panel.orderFrontRegardless()
        isVisible = true
        Diagnostics.record("show: canvas=\(panel.frame)")
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
        Diagnostics.record("state: canvas=\(panel.frame) expanded=\(isExpanded) ignoresMouseEvents=\(panel.ignoresMouseEvents)")
    }

    // MARK: - Geometry

    private func computeFrames() {
        guard let screen = panel.screen ?? NSScreen.main else { return }
        layout.sideInset = 56
        let sideInset = layout.sideInset

        let notchWidth: CGFloat
        let bandHeight: CGFloat
        if let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
            notchWidth = right.minX - left.maxX
            bandHeight = left.height
        } else {
            notchWidth = 210
            bandHeight = 32
        }

        layout.compactWidth = notchWidth + sideInset * 2
        layout.compactHeight = bandHeight
        layout.expandedWidth = min(780, screen.frame.width - 80)
        layout.expandedHeight = 208

        compactFrame = NSRect(x: screen.frame.midX - layout.compactWidth / 2,
                              y: screen.frame.maxY - layout.compactHeight,
                              width: layout.compactWidth,
                              height: layout.compactHeight)
        expandedFrame = NSRect(x: screen.frame.midX - layout.expandedWidth / 2,
                               y: screen.frame.maxY - layout.expandedHeight,
                               width: layout.expandedWidth,
                               height: layout.expandedHeight)

        // Fixed canvas: full screen width, tall enough for the expanded surface.
        let canvasHeight = max(layout.expandedHeight + 24, screen.frame.height * 0.42)
        canvasFrame = NSRect(x: screen.frame.minX,
                             y: screen.frame.maxY - canvasHeight,
                             width: screen.frame.width,
                             height: canvasHeight)
    }

    // MARK: - Pointer tracking + click handling

    /// Mouse moves only toggle whether the canvas accepts events over the live
    /// surface; expansion is click-driven, not hover-driven.
    private func installHoverMonitors() {
        let moves: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged]
        eventMonitors.append(NSEvent.addGlobalMonitorForEvents(matching: moves) { [weak self] _ in
            self?.updateMouseEventHandling()
        } as Any)
        eventMonitors.append(NSEvent.addLocalMonitorForEvents(matching: moves) { [weak self] event in
            self?.updateMouseEventHandling()
            return event
        } as Any)

        let downs: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        eventMonitors.append(NSEvent.addGlobalMonitorForEvents(matching: downs) { [weak self] _ in
            self?.handleMouseDown()
        } as Any)
        eventMonitors.append(NSEvent.addLocalMonitorForEvents(matching: downs) { [weak self] event in
            self?.handleMouseDown()
            return event
        } as Any)
    }

    /// A click outside the expanded dashboard closes it (Sapphire's click mode).
    private func handleMouseDown() {
        guard isExpanded,
              !expandedFrame.insetBy(dx: -6, dy: -6).contains(NSEvent.mouseLocation) else { return }
        collapse()
    }

    /// The big canvas intercepts clicks only over the live surface.
    private func updateMouseEventHandling() {
        let surface = isExpanded ? expandedFrame : compactFrame
        panel.ignoresMouseEvents = !surface.insetBy(dx: -6, dy: -6).contains(NSEvent.mouseLocation)
    }

    private func toggleExpansion() {
        if isExpanded {
            collapse()
        } else {
            expand()
        }
    }

    private func expand() {
        guard !isExpanded else { return }
        isExpanded = true
        layout.expanded = true
    }

    private func collapse() {
        guard isExpanded else { return }
        isExpanded = false
        layout.expanded = false
    }
}
