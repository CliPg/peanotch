import AppKit

@main
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var notchController: NotchWindowController?
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let controller = NotchWindowController()
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
    }

    @objc private func toggleNotch(_ sender: Any?) {
        notchController?.toggle()
    }
}
