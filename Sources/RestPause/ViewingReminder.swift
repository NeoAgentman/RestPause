import AppKit

private final class ReminderButton: NSButton {
    var primary = false
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        let fill = primary ? RestStyle.accent.withAlphaComponent(isHighlighted ? 0.75 : 1)
            : NSColor.white.withAlphaComponent(isHighlighted ? 0.18 : 0.07)
        fill.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: bounds.height / 2, yRadius: bounds.height / 2).fill()
        let text = NSAttributedString(string: title, attributes: [
            .font: NSFont.systemFont(ofSize: 13, weight: primary ? .medium : .regular),
            .foregroundColor: primary ? RestStyle.background : NSColor.white.withAlphaComponent(0.8)
        ])
        let size = text.size()
        text.draw(at: NSPoint(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2))
    }
}

extension AppDelegate {
    func showViewingReminder() {
        let title = "已观看 \(Int(session.elapsed / 60)) 分钟"
        if viewingReminder != nil {
            if viewingReminderLabel?.stringValue != title { viewingReminderLabel?.stringValue = title }
            return
        }
        guard let screen = NSScreen.main else { return }
        let frame = NSRect(x: screen.visibleFrame.maxX - 424, y: screen.visibleFrame.maxY - 252, width: 400, height: 228)
        let panel = ReminderPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        let background = ReminderBackground(frame: NSRect(origin: .zero, size: frame.size))
        panel.contentView = background

        let leaf = NSImageView(frame: NSRect(x: 24, y: 179, width: 19, height: 19))
        leaf.image = NSImage(systemSymbolName: "leaf", accessibilityDescription: nil)
        leaf.contentTintColor = RestStyle.accent
        background.addSubview(leaf)
        let watched = NSTextField(labelWithString: title)
        watched.font = .systemFont(ofSize: 12)
        watched.textColor = .white.withAlphaComponent(0.55)
        watched.frame = NSRect(x: 52, y: 177, width: 324, height: 21)
        background.addSubview(watched)
        let heading = NSTextField(labelWithString: "让眼睛，歇一会儿")
        heading.font = .systemFont(ofSize: 24, weight: .medium)
        heading.textColor = .white
        heading.frame = NSRect(x: 24, y: 128, width: 352, height: 34)
        background.addSubview(heading)
        let detail = NSTextField(labelWithString: "暂停影片后，点击「开始休息」。")
        detail.font = .systemFont(ofSize: 13)
        detail.textColor = .white.withAlphaComponent(0.65)
        detail.frame = NSRect(x: 24, y: 96, width: 352, height: 21)
        background.addSubview(detail)
        let snooze = ReminderButton(title: "10 分钟后提醒", target: self, action: #selector(snoozeViewingReminder))
        snooze.isBordered = false
        snooze.frame = NSRect(x: 24, y: 24, width: 184, height: 40)
        background.addSubview(snooze)
        let rest = ReminderButton(title: "开始休息", target: self, action: #selector(restNow))
        rest.primary = true
        rest.isBordered = false
        rest.frame = NSRect(x: 220, y: 24, width: 156, height: 40)
        background.addSubview(rest)
        viewingReminder = panel
        viewingReminderLabel = watched
        panel.orderFrontRegardless()
    }

    func hideViewingReminder() {
        viewingReminder?.orderOut(nil)
        viewingReminder = nil
        viewingReminderLabel = nil
    }
}
