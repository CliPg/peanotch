import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var notchController: NotchWindowController?
    private var statusItem: NSStatusItem?
    private let weather = WeatherService()
    private let calendarService = CalendarService()
    private let battery = BatteryService()

    func applicationDidFinishLaunching(_ notification: Notification) {
        Diagnostics.record("applicationDidFinishLaunching")

        weather.start()
        calendarService.requestAndLoad()
        battery.start()

        let controller = NotchWindowController(services: (weather, calendarService, battery))
        controller.show()
        notchController = controller

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.title = "🥜"

        let menu = NSMenu()
        let toggleItem = NSMenuItem(title: "显示/隐藏刘海", action: #selector(toggleNotch(_:)), keyEquivalent: "n")
        toggleItem.target = self
        menu.addItem(toggleItem)
        menu.addItem(.separator())
        menu.addItem(withTitle: "退出 Peanut", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.menu = menu
        statusItem = item

        dumpAppState(tag: "after-setup")

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak controller] in
            controller?.logState()
        }
    }

    /// Double-clicking the app again re-shows the notch instead of being a silent no-op.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        Diagnostics.record("reopen handled: showing notch")
        notchController?.show()
        return true
    }

    @objc private func toggleNotch(_ sender: Any?) {
        notchController?.toggle()
    }

    private func dumpAppState(tag: String) {
        let windows = NSApp.windows
            .map { "\($0.className) frame=(\(Int($0.frame.minX)),\(Int($0.frame.minY)) \(Int($0.frame.width))x\(Int($0.frame.height))) visible=\($0.isVisible) level=\($0.level.rawValue)" }
            .joined(separator: "\n    ")
        let screens = NSScreen.screens
            .map { "\($0.localizedName) frame=\(Int($0.frame.width))x\(Int($0.frame.height)) safeTop=\(Int($0.safeAreaInsets.top))" }
            .joined(separator: ", ")
        Diagnostics.record("""
            [\(tag)] app windows (\(NSApp.windows.count)):
                \(windows)
            screens: \(screens)
            """)
    }
}
