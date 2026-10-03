// Prints the CGWindowID of the largest on-screen window owned by a process.
// Usage: swift Scripts/window-id.swift <pid>
import CoreGraphics
import Foundation

guard CommandLine.arguments.count > 1, let pid = Int(CommandLine.arguments[1]) else { exit(1) }
let windows = (CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]]) ?? []
let mine = windows.filter { ($0[kCGWindowOwnerPID as String] as? Int) == pid && ($0[kCGWindowLayer as String] as? Int) == 0 }
let largest = mine.max { a, b in
    func area(_ w: [String: Any]) -> Double {
        let b = w[kCGWindowBounds as String] as? [String: Double] ?? [:]
        return (b["Width"] ?? 0) * (b["Height"] ?? 0)
    }
    return area(a) < area(b)
}
if let id = largest?[kCGWindowNumber as String] as? Int { print(id) } else { exit(2) }
