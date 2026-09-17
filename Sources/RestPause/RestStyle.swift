import AppKit

enum RestStyle {
    static let background = NSColor(srgbRed: 0.055, green: 0.10, blue: 0.095, alpha: 1)
    static let accent = NSColor(srgbRed: 0.66, green: 0.82, blue: 0.66, alpha: 1)
}

// Reminders leave keyboard focus with the user's current app.
final class ReminderPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

final class ReminderBackground: NSView {
    override func draw(_ dirtyRect: NSRect) {
        let shape = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 18, yRadius: 18)
        RestStyle.background.setFill()
        shape.fill()
        NSColor.white.withAlphaComponent(0.10).setStroke()
        shape.lineWidth = 1
        shape.stroke()
    }
}
