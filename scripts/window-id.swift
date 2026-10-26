// Prints the window ids of a running app's on-screen windows, largest
// first, for `screencapture -l`. Usage: swift scripts/window-id.swift WinLab
import CoreGraphics
import Foundation

let owner = CommandLine.arguments.dropFirst().first ?? "WinLab"
let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
let windows = list
    .filter { ($0[kCGWindowOwnerName as String] as? String) == owner }
    .compactMap { w -> (Int, Double)? in
        guard let id = w[kCGWindowNumber as String] as? Int,
              let b = w[kCGWindowBounds as String] as? [String: Double] else { return nil }
        return (id, (b["Width"] ?? 0) * (b["Height"] ?? 0))
    }
    .sorted { $0.1 > $1.1 }
for (id, _) in windows { print(id) }
