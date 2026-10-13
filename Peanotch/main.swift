import AppKit

// Explicit bootstrap: no @main magic, the delegate is set before the run loop
// starts so applicationDidFinishLaunching is guaranteed to fire.
Diagnostics.record("main.swift: process starting")

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
