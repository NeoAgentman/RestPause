import Foundation
import RestCore
func XCTAssertEqual<T: Equatable>(_ a: T, _ b: T) { precondition(a == b, "Mismatch: \(a) != \(b)") }
func XCTAssertNil<T>(_ value: T?) { precondition(value == nil) }
func XCTAssertFalse(_ value: Bool) { precondition(!value) }
final class SessionTests {
    let base = Date(timeIntervalSince1970: 1000)
    func testStartsOnlyWithInputAndCountsReading() {
        var s = Session(); s.tick(now: base, active: true, hasInput: false)
        s.tick(now: base.addingTimeInterval(1), active: true, hasInput: true)
        s.tick(now: base.addingTimeInterval(4), active: true, hasInput: false)
        XCTAssertEqual(s.elapsed, 3)
    }
    func testShortLockPreservesUsageLongLockResets() {
        var s = Session(); s.restDuration = 10
        s.tick(now: base, active: true, hasInput: true)
        s.tick(now: base.addingTimeInterval(4), active: true, hasInput: true)
        s.tick(now: base.addingTimeInterval(5), active: false, hasInput: false)
        s.tick(now: base.addingTimeInterval(8), active: true, hasInput: true)
        XCTAssertEqual(s.elapsed, 4)
        s.tick(now: base.addingTimeInterval(9), active: false, hasInput: false)
        s.tick(now: base.addingTimeInterval(30), active: true, hasInput: true)
        XCTAssertEqual(s.elapsed, 0)
    }
    func testBreakDeadlineAndReset() {
        var s = Session(); s.workDuration = 3; s.restDuration = 10
        s.tick(now: base, active: true, hasInput: true)
        s.tick(now: base.addingTimeInterval(3), active: true, hasInput: true)
        XCTAssertEqual(s.restEnd, base.addingTimeInterval(13))
        s.tick(now: base.addingTimeInterval(13), active: true, hasInput: false)
        XCTAssertNil(s.restEnd); XCTAssertEqual(s.elapsed, 0); XCTAssertFalse(s.started)
    }
    func testDelayedTickIsBounded() {
        var s = Session(); s.tick(now: base, active: true, hasInput: true)
        s.tick(now: base.addingTimeInterval(7200), active: true, hasInput: false)
        XCTAssertEqual(s.elapsed, 5)
    }
    func testIdleCountsUntilResetBoundary() {
        var s = Session(); s.workDuration = 3600
        s.tick(now: base, active: true, hasInput: true, idleDuration: 0)
        for second in 1...299 {
            s.tick(now: base.addingTimeInterval(Double(second)), active: true, hasInput: false, idleDuration: Double(second))
            XCTAssertEqual(s.elapsed, Double(second))
        }
        s.tick(now: base.addingTimeInterval(300), active: true, hasInput: false, idleDuration: 300)
        XCTAssertEqual(s.elapsed, 0); XCTAssertFalse(s.started)
        s.tick(now: base.addingTimeInterval(310), active: true, hasInput: false, idleDuration: 310)
        XCTAssertEqual(s.elapsed, 0); XCTAssertFalse(s.started)
        s.tick(now: base.addingTimeInterval(311), active: true, hasInput: true, idleDuration: 0)
        XCTAssertEqual(s.elapsed, 0)
        s.tick(now: base.addingTimeInterval(312), active: true, hasInput: true, idleDuration: 0)
        XCTAssertEqual(s.elapsed, 1)
    }
    func testShortIdleResumeAndConfiguredReset() {
        var s = Session(); s.workDuration = 3600; s.restDuration = 180
        s.tick(now: base, active: true, hasInput: true, idleDuration: 0)
        for second in 1...179 { s.tick(now: base.addingTimeInterval(Double(second)), active: true, hasInput: false, idleDuration: Double(second)) }
        s.tick(now: base.addingTimeInterval(180), active: true, hasInput: true, idleDuration: 0)
        XCTAssertEqual(s.elapsed, 180)
        for second in 181...359 { s.tick(now: base.addingTimeInterval(Double(second)), active: true, hasInput: false, idleDuration: Double(second - 180)) }
        XCTAssertEqual(s.elapsed, 359)
        s.tick(now: base.addingTimeInterval(360), active: true, hasInput: false, idleDuration: 180)
        XCTAssertEqual(s.elapsed, 0); XCTAssertFalse(s.started)
    }
    func testIdleStillUsesNormalBreakThreshold() {
        var s = Session(); s.workDuration = 120
        s.tick(now: base, active: true, hasInput: true, idleDuration: 0)
        for second in 1...120 { s.tick(now: base.addingTimeInterval(Double(second)), active: true, hasInput: false, idleDuration: Double(second)) }
        XCTAssertEqual(s.restEnd, base.addingTimeInterval(420))
    }
    func testViewingCountsWithoutInputAndOnlyReminds() {
        var s = Session(); s.workDuration = 60; s.setViewingMode(true)
        s.tick(now: base, active: true, hasInput: false, idleDuration: 600)
        for second in 1...360 { s.tick(now: base.addingTimeInterval(Double(second)), active: true, hasInput: false, idleDuration: Double(second + 600)) }
        XCTAssertEqual(s.elapsed, 360)
        XCTAssertEqual(s.viewingReminderDue, true)
        XCTAssertNil(s.restEnd)
    }
    func testViewingSnoozeRetainsUsageAndPausesDuringAbsence() {
        var s = Session(); s.workDuration = 3; s.restDuration = 300; s.setViewingMode(true)
        s.tick(now: base, active: true, hasInput: false)
        s.tick(now: base.addingTimeInterval(3), active: true, hasInput: false)
        s.snoozeViewingReminder()
        XCTAssertEqual(s.elapsed, 3); XCTAssertEqual(s.secondsUntilReminder, 600)
        s.tick(now: base.addingTimeInterval(4), active: false, hasInput: false)
        s.tick(now: base.addingTimeInterval(100), active: true, hasInput: false)
        XCTAssertEqual(s.elapsed, 3); XCTAssertEqual(s.secondsUntilReminder, 600)
        for second in 101...699 { s.tick(now: base.addingTimeInterval(Double(second)), active: true, hasInput: false) }
        XCTAssertFalse(s.viewingReminderDue)
        s.tick(now: base.addingTimeInterval(700), active: true, hasInput: false)
        XCTAssertEqual(s.viewingReminderDue, true); XCTAssertEqual(s.elapsed, 603)
        XCTAssertNil(s.restEnd)
    }
    func testViewingLongAbsenceResetsReminder() {
        var s = Session(); s.workDuration = 3; s.restDuration = 10; s.setViewingMode(true)
        s.tick(now: base, active: true, hasInput: false)
        s.tick(now: base.addingTimeInterval(3), active: true, hasInput: false)
        s.snoozeViewingReminder()
        s.tick(now: base.addingTimeInterval(4), active: false, hasInput: false)
        s.tick(now: base.addingTimeInterval(14), active: false, hasInput: false)
        XCTAssertEqual(s.elapsed, 0); XCTAssertFalse(s.viewingReminderDue)
        XCTAssertEqual(s.secondsUntilReminder, 3)
        s.tick(now: base.addingTimeInterval(15), active: true, hasInput: false)
        XCTAssertEqual(s.started, true); XCTAssertEqual(s.elapsed, 0)
    }
    func testViewingManualRestAndModeSwitch() {
        var s = Session(); s.workDuration = 3; s.restDuration = 10; s.setViewingMode(true)
        s.tick(now: base, active: true, hasInput: false)
        s.tick(now: base.addingTimeInterval(3), active: true, hasInput: false)
        s.beginRest(now: base.addingTimeInterval(3))
        XCTAssertFalse(s.viewingReminderDue)
        s.tick(now: base.addingTimeInterval(13), active: true, hasInput: false)
        XCTAssertNil(s.restEnd); XCTAssertEqual(s.viewingMode, true); XCTAssertEqual(s.elapsed, 0)
        s.tick(now: base.addingTimeInterval(14), active: true, hasInput: false)
        s.tick(now: base.addingTimeInterval(16), active: true, hasInput: false)
        s.setViewingMode(false)
        XCTAssertEqual(s.elapsed, 2)
        s.tick(now: base.addingTimeInterval(17), active: true, hasInput: true, idleDuration: 0)
        XCTAssertEqual(s.restEnd, base.addingTimeInterval(27))
    }
}

let checks = SessionTests()
checks.testStartsOnlyWithInputAndCountsReading()
checks.testShortLockPreservesUsageLongLockResets()
checks.testBreakDeadlineAndReset()
checks.testDelayedTickIsBounded()
checks.testIdleCountsUntilResetBoundary()
checks.testShortIdleResumeAndConfiguredReset()
checks.testIdleStillUsesNormalBreakThreshold()
checks.testViewingCountsWithoutInputAndOnlyReminds()
checks.testViewingSnoozeRetainsUsageAndPausesDuringAbsence()
checks.testViewingLongAbsenceResetsReminder()
checks.testViewingManualRestAndModeSwitch()
print("PASS: 11 timing scenarios")
