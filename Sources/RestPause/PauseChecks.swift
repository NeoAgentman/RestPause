import AppKit
import RestCore

extension AppDelegate {
    func runPauseChecks() {
        timer?.invalidate()
        let base = Date(timeIntervalSince1970: 40000)
        var time = base
        currentTime = { time }
        activitySnapshot = { (nil, nil) }
        inputIdle = { 0 }
        var failed = false
        func check(_ label: String, _ passed: Bool) {
            print("PAUSE \(label): \(passed ? "PASS" : "FAIL")")
            if !passed { failed = true }
        }
        func prepare(viewing: Bool = false, duration: TimeInterval = 3600) {
            hideWarning(); hideViewingReminder()
            enabled = true; locked = false; displaysSleeping = false; warned = false
            session = Session(); session.workDuration = duration
            session.setViewingMode(viewing)
            time = base; tick()
            for second in 1...120 { time = base.addingTimeInterval(Double(second)); tick() }
        }
        // Use the same selector as the real menu and the production tick path.
        prepare()
        toggle()
        check("pause retains 120 seconds and shows paused status", !enabled && session.elapsed == 120 && item.button?.title == " 暂停")
        time = base.addingTimeInterval(130); tick()
        check("paused ticks do not count", session.elapsed == 120)
        toggle()
        check("resume retains 120 seconds without counting pause", enabled && session.elapsed == 120 && item.button?.title == " 58")
        time = base.addingTimeInterval(131); tick()
        check("next second continues from saved progress", session.elapsed == 121)
        for _ in 0..<3 { toggle(); toggle() }
        check("repeated toggles neither reset nor add time", session.elapsed == 121)

        prepare()
        toggle()
        time = base.addingTimeInterval(121); screenLocked()
        time = base.addingTimeInterval(800); displaysDidSleep(); tick()
        check("long pause and absence notifications retain progress", session.elapsed == 120)
        screenUnlocked(); displaysDidWake(); toggle()
        check("resume after long pause retains progress", session.elapsed == 120)
        time = base.addingTimeInterval(801); tick()
        check("long pause is excluded from resumed usage", session.elapsed == 121)

        prepare(viewing: true, duration: 120)
        snoozeViewingReminder()
        toggle()
        time = base.addingTimeInterval(900); tick(); toggle()
        check("viewing pause preserves mode and snooze", session.viewingMode && session.elapsed == 120 && session.secondsUntilReminder == 600 && viewingReminder == nil)
        time = base.addingTimeInterval(901); tick()
        check("viewing snooze continues counting after resume", session.elapsed == 121 && session.secondsUntilReminder == 599)

        prepare(duration: 180)
        check("warning is visible before pause", warning?.isVisible == true)
        toggle()
        check("pause hides warning", warning == nil)
        time = base.addingTimeInterval(140); toggle()
        check("resume restores pending one-minute warning", session.elapsed == 120 && warning?.isVisible == true)

        prepare(viewing: true, duration: 120)
        toggle()
        check("pause hides due viewing reminder", viewingReminder == nil)
        time = base.addingTimeInterval(140); toggle()
        check("resume restores due viewing reminder", session.elapsed == 120 && viewingReminder?.isVisible == true)

        prepare()
        locked = true // Keep this deadline check from displaying a cover or playing music.
        session.beginRest(now: time, duration: 10)
        let end = session.restEnd
        toggle()
        check("pausing usage preserves an existing rest deadline", session.restEnd == end)
        time = base.addingTimeInterval(130); tick()
        check("existing rest completes while usage is paused", !enabled && session.restEnd == nil && session.elapsed == 0)

        hideWarning(); hideViewingReminder()
        cleanup()
        exit(failed ? 1 : 0)
    }
}
