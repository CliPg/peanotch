import AppKit
import SwiftUI

/// Shared with the SwiftUI layer: the surface geometry + expansion state.
final class NotchLayoutState: ObservableObject {
    @Published var expanded = false
    @Published var sideInset: CGFloat = 56
    @Published var compactWidth: CGFloat = 291
    @Published var compactHeight: CGFloat = 32
    @Published var expandedWidth: CGFloat = 1100
    @Published var expandedHeight: CGFloat = 293
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
    private let countdownService = CountdownService()
    private let reminderService = ReminderService()
    private let systemStats = SystemStatsService()
    private let airPods = AirPodsBatteryService()
    private var editorWindow: NSWindow?
    private var settingsWindow: NSWindow?
    private var hoverProbe: NSPanel?
    private var pollTimer: Timer?
    private var collapseCheck: Timer?
    private var isExpanded = false
    private var isVisible = true
    private var eventMonitors: [Any] = []
    private var screenObserver: NSObjectProtocol?

    init(services: (weather: WeatherService, calendar: CalendarService, battery: BatteryService)) {
        panel = KeyablePanel(contentRect: .zero,
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

        let hostingView = ResignOnBackgroundHostingView(rootView: NotchView(onBandTap: { [weak self] in
            self?.toggleExpansion()
        }, onEditCountdowns: { [weak self] in
            self?.showCountdownEditor()
        }, onOpenSettings: { [weak self] in
            self?.showSettingsWindow()
        })
            .environmentObject(layout)
            .environmentObject(services.weather)
            .environmentObject(services.calendar)
            .environmentObject(services.battery)
            .environmentObject(countdownService)
            .environmentObject(reminderService)
            .environmentObject(systemStats)
            .environmentObject(airPods)
            .environmentObject(AppSettings.shared))
        reminderService.requestAccess()
        systemStats.start()
        airPods.start()
        // The canvas window owns its size; SwiftUI animates within it.
        hostingView.sizingOptions = []
        hostingView.autoresizingMask = [.width, .height]
        panel.contentView = hostingView

        computeFrames()
        panel.setFrame(canvasFrame, display: true)

        installHoverMonitors()
        installHoverProbe()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            self?.evaluateHover()
        }

        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            self.computeFrames()
            self.panel.setFrame(self.canvasFrame, display: true)
            if let probe = self.hoverProbe {
                probe.setFrame(self.probeFrame, display: false)
                probe.orderFrontRegardless()
            }
        }

        Diagnostics.record("canvas created, frame=\(canvasFrame), compact=\(compactFrame), expanded=\(expandedFrame), screen=\(panel.screen?.localizedName ?? "nil")")
    }

    deinit {
        eventMonitors.forEach { NSEvent.removeMonitor($0) }
        pollTimer?.invalidate()
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
        layout.expandedWidth = min(1100, screen.frame.width - 80)
        layout.expandedHeight = 293

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

    /// Clicks only — pointer MOVEMENT is tracked by the hover probe window:
    /// NSEvent monitors never see mouseMoved while the cursor is inside the
    /// menu bar (which is exactly where the notch lives), so they can't drive
    /// proximity expansion.
    private func installHoverMonitors() {
        let downs: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        eventMonitors.append(NSEvent.addGlobalMonitorForEvents(matching: downs) { [weak self] _ in
            self?.handleMouseDown()
        } as Any)
        eventMonitors.append(NSEvent.addLocalMonitorForEvents(matching: downs) { [weak self] event in
            if let window = event.window,
               let self,
               window === self.panel || window === self.editorWindow || window === self.settingsWindow {
                self.resignFieldEditorIfClickedOutside(event, in: window)
            }
            self?.handleMouseDown()
            return event
        } as Any)
    }

    /// Deterministic caret dismissal: while a field editor (the SwiftUI
    /// TextField's editor) is first responder, any canvas click that does not
    /// land inside its frame ends editing. SwiftUI-internal hitTest results
    /// proved unreliable for this.
    private func resignFieldEditorIfClickedOutside(_ event: NSEvent, in window: NSWindow) {
        guard let editor = window.firstResponder as? NSTextView else { return }
        let editorFrame = editor.convert(NSRect(origin: .zero, size: editor.bounds.size), to: nil)
        if !editorFrame.insetBy(dx: -4, dy: -4).contains(event.locationInWindow) {
            window.makeFirstResponder(nil)
        }
    }

    /// Transparent Sapphire-style probe over the notch region. NSTrackingArea
    /// is position-driven (works while the cursor is in the menu bar); its
    /// hitTest returns nil so every click passes through untouched.
    private var probeFrame: NSRect {
        expandedFrame.insetBy(dx: -6, dy: -10)
    }

    private func installHoverProbe() {
        let probe = NSPanel(contentRect: probeFrame,
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered,
                            defer: false)
        probe.level = .statusBar
        probe.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        probe.isOpaque = false
        probe.backgroundColor = .clear
        probe.hasShadow = false
        // Click-through: enter/exit tracking areas fire regardless; a false
        // value here swallows every click over the whole probe region (which
        // made the top of the screen unclickable).
        probe.ignoresMouseEvents = true
        let probeView = HoverProbeView(frame: NSRect(origin: .zero, size: probeFrame.size))
        probeView.onHoverEvent = { [weak self] in self?.evaluateHover() }
        probe.contentView = probeView
        probe.setFrame(probeFrame, display: false)
        probe.orderFrontRegardless()
        hoverProbe = probe
    }

    /// Probe-driven pointer evaluation: hover mode expands/collapses by
    /// proximity; click mode only refreshes event passthrough here.
    private func evaluateHover() {
        guard isVisible else { return }
        let location = NSEvent.mouseLocation
        if AppSettings.shared.openMode == "hover" {
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
        updateMouseEventHandling()
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
        let accepts = surface.insetBy(dx: -6, dy: -6).contains(NSEvent.mouseLocation)
        if panel.ignoresMouseEvents == accepts {
            panel.ignoresMouseEvents = !accepts
            Diagnostics.record("canvas events -> \(accepts ? "accepting (over surface)" : "passthrough"), at \(NSEvent.mouseLocation)")
        }
    }

    private func toggleExpansion() {
        guard AppSettings.shared.openMode == "click" else { return }
        if isExpanded {
            collapse()
        } else {
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
        layout.expanded = true
        if AppSettings.shared.hapticFeedback {
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        }
    }

    private func collapse() {
        guard isExpanded else { return }
        isExpanded = false
        layout.expanded = false
        panel.makeFirstResponder(nil)
    }

    // MARK: - Utility windows (editor / settings)

    /// Presents a titled utility window above the notch canvas. The canvas is
    /// at .statusBar (25) — a plain window would render underneath its black
    /// surface — and an accessory app must activate before ordering front.
    /// No inout: the content closure receives the window directly, so reading
    /// self.<window> during presentation can't trip Swift's exclusivity checks
    /// (that abort()ed the app on the first gear click).
    private func presentUtilityWindow(existing: NSWindow?,
                                      title: String,
                                      size: NSSize,
                                      makeContent: (NSWindow) -> NSView) -> NSWindow {
        let window: NSWindow
        if let existing {
            window = existing
        } else {
            window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                              styleMask: [.titled, .closable],
                              backing: .buffered,
                              defer: false)
            window.title = title
            window.isReleasedWhenClosed = false
            window.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
            window.collectionBehavior = [.fullScreenAuxiliary, .ignoresCycle]
            window.contentView = makeContent(window)
        }
        NSApp.activate(ignoringOtherApps: true)
        window.center()
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        DispatchQueue.main.async { [weak window] in
            NSApp.activate(ignoringOtherApps: true)
            window?.makeKeyAndOrderFront(nil)
        }
        return window
    }

    private func showCountdownEditor() {
        editorWindow = presentUtilityWindow(existing: editorWindow,
                                            title: L10n.t("倒计时设置", "Countdowns"),
                                            size: NSSize(width: 420, height: 460)) { [weak self] window in
            NSHostingView(rootView: CountdownEditorView(service: self?.countdownService ?? CountdownService(),
                                                        onDone: { [weak window] in
                                                            window?.orderOut(nil)
                                                        }))
        }
    }

    private func showSettingsWindow() {
        settingsWindow = presentUtilityWindow(existing: settingsWindow,
                                              title: L10n.t("设置", "Settings"),
                                              size: NSSize(width: 680, height: 460)) { [weak self] window in
            NSHostingView(rootView: SettingsView(settings: AppSettings.shared,
                                                 onDone: { [weak window] in
                                                     window?.orderOut(nil)
                                                 },
                                                 onOpenCountdowns: { [weak self] in
                                                     self?.showCountdownEditor()
                                                 }))
        }
    }
}

/// Borderless non-activating panels refuse key status by default, which makes
/// the inline "new reminder" TextField untypeable. Allow key (Spotlight-style:
/// focus without activating the app).
final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

/// SwiftUI leaves the caret in the inline TextField forever when clicks land
/// on non-interactive areas of the canvas (nothing else accepts keyboard
/// focus). Resign first responder whenever a click hits a non-input view.
final class ResignOnBackgroundHostingView<Content: View>: NSHostingView<Content> {
    override func hitTest(_ point: NSPoint) -> NSView? {
        let view = super.hitTest(point)
        if let view, view !== self, !view.acceptsFirstResponder {
            window?.makeFirstResponder(nil)
        }
        return view
    }
}
