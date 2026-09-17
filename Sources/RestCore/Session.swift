import Foundation
public struct Session {
    public var workDuration: TimeInterval = 45 * 60
    public var restDuration: TimeInterval = 5 * 60
    public var idleIndicatorDuration: TimeInterval = 60
    public private(set) var elapsed: TimeInterval = 0
    public private(set) var restEnd: Date?
    public private(set) var started = false
    public private(set) var viewingMode = false
    private var viewingReminderAt: TimeInterval?
    public var secondsUntilReminder: TimeInterval { max(0, (viewingReminderAt ?? workDuration) - elapsed) }
    public var viewingReminderDue: Bool { viewingMode && restEnd == nil && secondsUntilReminder == 0 }
    private var last: Date?
    private var awaySince: Date?
    public init() {}
    public mutating func tick(now: Date, active: Bool, hasInput: Bool, idleDuration: TimeInterval? = nil) {
        defer { last = now }
        if let end = restEnd {
            if now >= end { reset(); last = now }
            return
        }
        let idle = viewingMode ? nil : idleDuration.flatMap { $0.isFinite && $0 >= 0 ? $0 : nil }
        // Input inactivity only resets a completed natural break; it does not
        // pause accumulation during shorter pauses in reading or working.
        if let idle, idle >= restDuration {
            reset()
            return
        }
        if !active {
            if awaySince == nil { awaySince = now }
            if let idle, idle >= idleIndicatorDuration {
                // Include the first minute of inactivity in the rest interval.
                awaySince = min(awaySince ?? now, now.addingTimeInterval(-idle))
            }
            if let away = awaySince, now.timeIntervalSince(away) >= restDuration {
                elapsed = 0
                started = false
                viewingReminderAt = nil
            }
            return
        }
        if let away = awaySince {
            if now.timeIntervalSince(away) >= restDuration { reset() }
            awaySince = nil
            last = now
        }
        if !started { started = viewingMode || hasInput; return }
        // A delayed callback cannot turn sleep or a stalled process into hours of usage.
        if let previous = last { elapsed += min(5, max(0, now.timeIntervalSince(previous))) }
        if !viewingMode && elapsed >= workDuration { beginRest(now: now) }
    }
    public mutating func setViewingMode(_ enabled: Bool) {
        viewingMode = enabled
        viewingReminderAt = nil
    }
    public mutating func snoozeViewingReminder() {
        guard viewingReminderDue else { return }
        viewingReminderAt = elapsed + 10 * 60
    }
    public mutating func beginRest(now: Date, duration: TimeInterval? = nil) { restEnd = now.addingTimeInterval(duration ?? restDuration) }
    public mutating func resumeTiming(now: Date) {
        // Manual pauses freeze progress and snoozes; only restart the clock baseline.
        last = now
        awaySince = nil
    }
    public mutating func reset() { elapsed = 0; started = false; restEnd = nil; last = nil; awaySince = nil; viewingReminderAt = nil }
}
