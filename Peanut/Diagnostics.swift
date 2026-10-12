import Foundation

/// File-based diagnostics: NSLog alone proved unreliable to observe from outside,
/// so every record also lands in /tmp/peanut_state.txt.
enum Diagnostics {
    static let path = "/tmp/peanut_state.txt"

    static func record(_ message: String) {
        let line = "[\(Date())] \(message)\n"
        NSLog("[Peanut] \(message)")
        if let handle = FileHandle(forWritingAtPath: path) {
            handle.seekToEndOfFile()
            handle.write(line.data(using: .utf8)!)
            try? handle.close()
        } else {
            try? line.write(toFile: path, atomically: true, encoding: .utf8)
        }
    }
}
