import AppKit

private actor FocusCalls {
    var names: [String] = []
    var ends: [Date?] = []
    func run(_ name: String, _ end: Date?) async -> Bool {
        names.append(name); ends.append(end)
        if name == "歇一会-开始" { try? await Task.sleep(for: .milliseconds(150)) }
        return true
    }
}

extension AppDelegate {
    func runFocusChecks() async {
        timer?.invalidate()
        let calls = FocusCalls()
        focusLink = RestFocusLink { name, end in await calls.run(name, end) }
        var failed = false
        func check(_ label: String, _ passed: Bool) {
            print("FOCUS \(label): \(passed ? "PASS" : "FAIL")")
            if !passed { failed = true }
        }
        session.beginRest(now: Date(), duration: 30)
        let deadline = session.restEnd!
        showRest()
        for _ in 0..<50 {
            if await !calls.names.isEmpty { break }
            try? await Task.sleep(for: .milliseconds(10))
        }
        check("cover starts without waiting for shortcut", !windows.isEmpty && focusLink.pending == 1)
        focusLink.begin(until: deadline)
        model.emergencyUnlockDisabled = false
        emergencyUnlock()
        check("emergency unlock is immediate while start is running", windows.isEmpty && session.restEnd == nil)
        await focusLink.finish()
        await Task.yield()
        check("end follows in-flight start exactly once", await calls.names == ["歇一会-开始", "歇一会-结束"])
        check("start receives the actual deadline", await calls.ends.first! == deadline)
        cleanup(); await focusLink.finish()
        check("repeated cleanup is idempotent", await calls.names.count == 2 && focusLink.pending == 0)

        let skipped = FocusCalls()
        let link = RestFocusLink { name, end in await skipped.run(name, end) }
        link.begin(until: deadline); link.end()
        await link.finish()
        check("cancel before launch skips stale start", await skipped.names == ["歇一会-结束"])
        link.enabled = false; link.begin(until: deadline)
        await link.finish()
        check("disabled link never starts a shortcut", await skipped.names.count == 1)
        let interrupted = FocusCalls()
        let disabledDuringRest = RestFocusLink { name, end in await interrupted.run(name, end) }
        disabledDuringRest.begin(until: deadline)
        for _ in 0..<50 {
            if await !interrupted.names.isEmpty { break }
            try? await Task.sleep(for: .milliseconds(10))
        }
        disabledDuringRest.enabled = false; disabledDuringRest.end()
        await disabledDuringRest.finish()
        check("disabling during a running start still sends end", await interrupted.names == ["歇一会-开始", "歇一会-结束"])
        var failures: [String] = []
        let rejected = RestFocusLink { _, _ in false }
        rejected.onFailure = { failures.append($0) }
        rejected.begin(until: deadline)
        await rejected.finish()
        rejected.end(); await rejected.finish()
        check("execution failures reach the user notification handler", failures == ["歇一会-开始", "歇一会-结束"])
        timer?.invalidate()
        exit(failed ? 1 : 0)
    }
}
