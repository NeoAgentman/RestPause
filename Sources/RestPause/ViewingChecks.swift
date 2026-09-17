import AppKit
import RestCore

extension AppDelegate {
    func runViewingChecks() async {
        timer?.invalidate()
        if let path = ProcessInfo.processInfo.environment["RESTPAUSE_WARNING_CAPTURE"] {
            showWarning()
            if let view = warning?.contentView,
               let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                view.cacheDisplay(in: view.bounds, to: bitmap)
                try? bitmap.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
            }
            hideWarning()
        }
        let foreground = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let presentation = NSApp.presentationOptions
        let base = Date(timeIntervalSince1970: 20000)
        var time = base
        currentTime = { time }
        activitySnapshot = { (nil, nil) }
        inputIdle = { 900 }
        session = Session(); session.workDuration = 60
        session.setViewingMode(true)
        var failed = false
        func check(_ label: String, _ passed: Bool) {
            print("VIEWING \(label): \(passed ? "PASS" : "FAIL")")
            if !passed { failed = true }
        }
        tick()
        for second in 1...60 { time = base.addingTimeInterval(Double(second)); tick() }
        check("counts idle input", session.elapsed == 60)
        check("shows reminder without break or music", viewingReminder?.isVisible == true && session.restEnd == nil && windows.isEmpty && !music.active)
        check("status identifies viewing mode", item.button?.title == " 观影 · 待休息")
        check("fullscreen collection behavior", viewingReminder?.collectionBehavior.contains(.fullScreenAuxiliary) == true && viewingReminder?.collectionBehavior.contains(.canJoinAllSpaces) == true)
        try? await Task.sleep(for: .milliseconds(400))
        if let path = ProcessInfo.processInfo.environment["RESTPAUSE_VIEWING_CAPTURE"], let panel = viewingReminder {
            let capture = Process()
            capture.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            capture.arguments = ["-x", "-l", String(panel.windowNumber), path]
            try? capture.run()
            capture.waitUntilExit()
            if capture.terminationStatus != 0, let view = panel.contentView,
               let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                view.cacheDisplay(in: view.bounds, to: bitmap)
                try? bitmap.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
                print("VIEWING captured native view layout; screen capture unavailable")
            }
        }
        check("reminder does not take focus or change presentation", NSWorkspace.shared.frontmostApplication?.processIdentifier == foreground && viewingReminder?.isKeyWindow == false && NSApp.presentationOptions == presentation)
        let originalPanel = viewingReminder
        tick()
        check("does not recreate visible reminder", viewingReminder === originalPanel)
        let buttons = viewingReminder?.contentView?.subviews.compactMap { $0 as? NSButton } ?? []
        check("both actions are available", buttons.count == 2)
        buttons.first(where: { $0.title == "10 分钟后提醒" })?.performClick(nil)
        check("snooze hides panel and preserves usage", viewingReminder == nil && session.elapsed == 60 && session.secondsUntilReminder == 600)
        for second in 61...659 { time = base.addingTimeInterval(Double(second)); tick() }
        check("does not remind early", viewingReminder == nil && session.restEnd == nil)
        time = base.addingTimeInterval(660); tick()
        check("reminds again after ten viewing minutes", viewingReminder?.isVisible == true && session.elapsed == 660 && !music.active)
        screenLocked()
        check("lock hides reminder immediately", viewingReminder == nil)
        time = base.addingTimeInterval(670); tick()
        check("lock pauses watching", session.elapsed == 660)
        screenUnlocked(); tick()
        check("short unlock returns pending reminder", viewingReminder?.isVisible == true)
        let rest = viewingReminder?.contentView?.subviews.compactMap { $0 as? NSButton }.first(where: { $0.title == "开始休息" })
        rest?.performClick(nil)
        check("start action enters real cover", session.restEnd != nil && viewingReminder == nil && windows.count == NSScreen.screens.count && !windows.isEmpty && music.active)
        endRest()
        check("ending break keeps mode but resets usage", session.viewingMode && session.elapsed == 0 && windows.isEmpty && !music.active)
        tick()
        time = base.addingTimeInterval(731); tick()
        let beforePreview = session.elapsed
        preview(); endRest()
        check("preview preserves viewing progress", session.viewingMode && session.elapsed == beforePreview && !isPreview)
        // The real menu toggle produces keyboard/mouse activity.
        inputIdle = { 0 }
        toggleViewingMode()
        check("menu disables viewing and restores status", !session.viewingMode && viewingReminder == nil && item.button?.title.contains("观影") == false)
        check("mode switch preserves usage", session.elapsed == beforePreview)
        cleanup()
        exit(failed ? 1 : 0)
    }
}
