import AppKit
import Foundation

enum CodexDateParser {
    static func parseISO8601(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) {
            return date
        }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }
}

enum AppIconLoader {
    static func loadBundleIcon() -> NSImage? {
        guard let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns") else {
            return nil
        }
        return NSImage(contentsOf: url)
    }

    static func menuBarIcon(side: CGFloat = 18) -> NSImage? {
        guard let source = loadBundleIcon() else { return nil }

        return NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
            let sourceSize = source.size
            guard sourceSize.width > 0, sourceSize.height > 0 else { return false }

            let scale = min(rect.width / sourceSize.width, rect.height / sourceSize.height)
            let drawSize = NSSize(width: sourceSize.width * scale, height: sourceSize.height * scale)
            let origin = NSPoint(x: (rect.width - drawSize.width) / 2, y: (rect.height - drawSize.height) / 2)
            source.draw(in: NSRect(origin: origin, size: drawSize))
            return true
        }
    }
}
