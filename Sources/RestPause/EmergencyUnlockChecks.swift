import AppKit
import RestCore

extension AppDelegate {
    func runEmergencyUnlockChecks() {
        timer?.invalidate()
        let defaults = UserDefaults.standard
        let savedPreference = defaults.object(forKey: "disableEmergencyUnlock")
        let savedDisabled = model.emergencyUnlockDisabled
        let base = Date(timeIntervalSince1970: 50000)
        var time = base
        currentTime = { time }
        activitySnapshot = { (nil, nil) }
        inputIdle = { 0 }
        locked = true // Exercise production paths without displaying a cover or playing music.
        var failed = false
        func check(_ label: String, _ passed: Bool) {
            print("EMERGENCY \(label): \(passed ? "PASS" : "FAIL")")
            if !passed { failed = true }
        }
        func key(_ type: NSEvent.EventType) -> NSEvent {
            NSEvent.keyEvent(with: type, location: .zero,
                modifierFlags: [.control, .option, .command], timestamp: 0,
                windowNumber: 0, context: nil, characters: "\u{1b}",
                charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53)!
        }
        func begin() {
            time = base; holdStart = nil
            session = Session()
            session.beginRest(now: time, duration: 10)
        }

        model.emergencyUnlockDisabled = false
        toggleEmergencyUnlock()
        check("menu toggle enables and saves setting", model.emergencyUnlockDisabled
            && defaults.bool(forKey: "disableEmergencyUnlock")
            && item.menu?.items.first(where: { $0.title == "禁用紧急解锁" })?.state == .on)
        begin()
        let deadline = session.restEnd
        model.escape()
        check("disabled button callback preserves rest", session.restEnd == deadline)
        handleEmergencyKey(key(.keyDown))
        check("disabled shortcut cannot start hold", holdStart == nil)
        holdStart = base // A hold that started before the setting changed must also be blocked.
        time = base.addingTimeInterval(4); tick()
        check("disabled stale hold cannot unlock", session.restEnd == deadline && holdStart == nil)
        time = base.addingTimeInterval(10); tick()
        check("disabled rest still finishes at deadline", session.restEnd == nil)

        begin()
        savedSession = Session(); savedSession?.workDuration = 2700
        isPreview = true
        time = base.addingTimeInterval(10); tick()
        check("disabled preview finishes and restores session", !isPreview && savedSession == nil
            && session.restEnd == nil && session.workDuration == 2700)

        holdStart = base
        toggleEmergencyUnlock()
        check("menu toggle disables and clears pending hold", !model.emergencyUnlockDisabled
            && !defaults.bool(forKey: "disableEmergencyUnlock") && holdStart == nil
            && item.menu?.items.first(where: { $0.title == "禁用紧急解锁" })?.state == .off)
        begin()
        handleEmergencyKey(key(.keyDown))
        time = base.addingTimeInterval(2); tick()
        check("enabled shortcut requires three seconds", session.restEnd != nil)
        handleEmergencyKey(key(.keyUp))
        time = base.addingTimeInterval(4); tick()
        check("releasing shortcut cancels hold", session.restEnd != nil && holdStart == nil)
        handleEmergencyKey(key(.keyDown))
        time = base.addingTimeInterval(7); tick()
        check("enabled shortcut unlocks after three seconds", session.restEnd == nil)
        begin(); model.escape()
        check("enabled button callback unlocks", session.restEnd == nil)

        cleanup()
        model.emergencyUnlockDisabled = savedDisabled
        if let savedPreference { defaults.set(savedPreference, forKey: "disableEmergencyUnlock") }
        else { defaults.removeObject(forKey: "disableEmergencyUnlock") }
        exit(failed ? 1 : 0)
    }
}
