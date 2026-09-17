import AppKit
import Combine
import RestCore

@MainActor private final class WriteCounter { var value = 0 }

extension AppDelegate {
    func runPerformanceChecks() {
        let base = Date(timeIntervalSince1970: 30000)
        var time = base
        currentTime = { time }
        activitySnapshot = { (nil, nil) }
        var idleReads = 0
        inputIdle = { idleReads += 1; return 0 }
        session = Session()
        var failed = false
        func check(_ label: String, _ passed: Bool) {
            print("PERFORMANCE \(label): \(passed ? "PASS" : "FAIL")")
            if !passed { failed = true }
        }
        check("background timer runs once per second", timer?.timeInterval == 1)

        // Observe native setters reached through the real tick, not a mock renderer.
        let titleWrites = WriteCounter()
        let titleObservation = item.button!.observe(\.title, options: [.new]) { _, _ in
            MainActor.assumeIsolated { titleWrites.value += 1 }
        }
        tick()
        check("initial status is rendered", titleWrites.value == 1 && item.button?.title == " 45")
        titleWrites.value = 0; idleReads = 0
        for quarter in 1...40 {
            time = base.addingTimeInterval(Double(quarter) / 4)
            tick()
        }
        check("unchanged status makes no native title writes (\(titleWrites.value))", titleWrites.value == 0)
        check("one idle query per tick (\(idleReads))", idleReads == 40)
        for second in 11...60 { time = base.addingTimeInterval(Double(second)); tick() }
        check("minute boundary updates exactly once", titleWrites.value == 1 && item.button?.title == " 44")

        locked = true // Exercise countdown without opening a cover or playing music.
        session.beginRest(now: time, duration: 10)
        tick()
        check("break timer retains quarter-second response", timer?.timeInterval == 0.25)
        var countdownWrites = 0
        let countdownObservation = model.$remaining.dropFirst().sink { _ in countdownWrites += 1 }
        for quarter in 1...3 { time = base.addingTimeInterval(60 + Double(quarter) / 4); tick() }
        check("same countdown second does not publish", countdownWrites == 0)
        time = base.addingTimeInterval(61); tick()
        check("next countdown second publishes once", countdownWrites == 1 && model.remaining == 9)
        titleObservation.invalidate()
        countdownObservation.cancel()
        endRest()
        check("ending break restores background interval", timer?.timeInterval == 1)
        timer?.invalidate()
        cleanup()
        exit(failed ? 1 : 0)
    }
}
