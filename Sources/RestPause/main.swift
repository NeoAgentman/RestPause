import AppKit
import SwiftUI
import IOKit.pwr_mgt
import RestCore

struct RestMessage: Equatable {
    let title: String
    let detail: String

    static let all: [RestMessage] = [
        .init(title: "把目光，借给远方", detail: "看看窗外的树梢，让眼睛在绿意里歇一会儿"),
        .init(title: "给这一刻，留一点白", detail: "起身走几步，让呼吸慢慢填满这段空白"),
        .init(title: "风经过时，不必赶路", detail: "放下手边的忙碌，轻轻舒展肩颈"),
        .init(title: "让思绪，去窗边坐坐", detail: "望一望远处，暂时不急着找到答案"),
        .init(title: "日子很长，容得下一次停顿", detail: "离开屏幕，喝口水，也照顾一下自己"),
        .init(title: "把呼吸，还给自己", detail: "松开紧绷的肩膀，慢慢吸气，缓缓呼气"),
        .init(title: "忙碌的句子，也需要逗号", detail: "站起来走走，让这一小段停顿有处安放"),
        .init(title: "窗外，还有另一种时间", detail: "看云缓缓经过，让目光停在远处"),
        .init(title: "暂且合上，心里的清单", detail: "伸一伸手臂，这几分钟只用来好好休息"),
        .init(title: "让肩头的山，轻一点", detail: "放松肩颈，换个姿势，让身体自在一些"),
        .init(title: "去拾起，一小片日常", detail: "倒杯温水，走到窗边，看看此刻的天色"),
        .init(title: "灵感也有，散步的时候", detail: "离开座位走几步，让念头慢慢舒展开来"),
        .init(title: "此刻，适合听见自己", detail: "暂时移开目光，留意一呼一吸的节奏"),
        .init(title: "给眼睛，一段远行", detail: "从眼前的文字出发，望向窗外更远的地方"),
        .init(title: "把片刻，过得松软些", detail: "松开双手，放下肩膀，慢慢喝一口水"),
        .init(title: "不妨，和树影待一会儿", detail: "看看远处的枝叶，让目光有一处安静的落点"),
        .init(title: "在匆忙里，添一笔从容", detail: "起身舒展一下，把步子放慢一点"),
        .init(title: "让心事，暂时靠岸", detail: "离开屏幕片刻，让双手和眼睛都歇一歇"),
        .init(title: "一杯水的时间，也很好", detail: "去接一杯水，慢慢喝，不必急着回来"),
        .init(title: "把自己，放回生活里", detail: "感受脚下的地面，走几步，看看身边的光"),
        .init(title: "这一页，先留一阵风", detail: "手边的事稍后继续，此刻起身活动一下"),
        .init(title: "远处的天，值得抬头", detail: "让视线离开屏幕，看看今天云的模样"),
        .init(title: "慢一点，也会抵达", detail: "舒展肩背，平静呼吸，给自己几分钟余地"),
        .init(title: "歇一会儿，等自己跟上", detail: "让身体松下来，再带着轻一点的心情出发")
    ]
}

@MainActor final class RestModel: ObservableObject {
    @Published var remaining = 0
    @Published var message = RestMessage.all[0]
    @Published var keepingAwake = false
    var escape: () -> Void = {}

    func chooseMessage() {
        message = RestMessage.all.filter { $0 != message }.randomElement() ?? message
    }
}
struct RestView: View {
    @ObservedObject var model: RestModel
    @State private var holding = false
    var body: some View {
        ZStack {
            Color(nsColor: RestStyle.background).ignoresSafeArea()
            VStack(spacing: 24) {
                Image(systemName: "leaf").font(.system(size: 42, weight: .light)).foregroundStyle(Color(nsColor: RestStyle.accent))
                Text(model.message.title).font(.system(size: 34, weight: .medium))
                    .multilineTextAlignment(.center)
                Text(String(format: "%02d:%02d", model.remaining / 60, model.remaining % 60))
                    .font(.system(size: 88, weight: .ultraLight, design: .rounded)).monospacedDigit()
                Text(model.message.detail).font(.system(size: 17)).foregroundStyle(.white.opacity(0.65))
                    .multilineTextAlignment(.center)
                Text(model.keepingAwake ? "电脑保持运行，任务继续进行" : "任务继续进行；系统仍按原有电源设置运行")
                    .font(.system(size: 13)).foregroundStyle(.white.opacity(0.4)).padding(.top, 14)
                Text(holding ? "继续按住以紧急解除…" : "紧急解除 · 按住 3 秒")
                    .font(.system(size: 13)).padding(.horizontal, 22).padding(.vertical, 12)
                    .background(.white.opacity(holding ? 0.18 : 0.07), in: Capsule())
                    .contentShape(Capsule())
                    .onLongPressGesture(minimumDuration: 3, maximumDistance: 35, pressing: { holding = $0 }, perform: { model.escape() })
                    .accessibilityLabel("紧急解除，按住三秒；也可同时按住 Control Option Command Escape 三秒")
            }.foregroundStyle(.white).padding(.horizontal, 40)
        }
    }
}
final class CoverWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    var session = Session()
    let model = RestModel()
    let music = RestMusic()
    var item: NSStatusItem!
    var windows: [NSWindow] = []
    var timer: Timer?
    var assertion: IOPMAssertionID = 0
    var oldPresentation: NSApplication.PresentationOptions = []
    var previousApp: NSRunningApplication?
    var systemSleeping = false
    var sessionInactive = false
    var displaysSleeping = false
    var suspended: Bool { systemSleeping || sessionInactive || displaysSleeping }
    var locked = false
    var enabled = true
    var holdStart: Date?
    var warning: NSPanel?
    var viewingReminder: NSPanel?
    var viewingReminderLabel: NSTextField?
    var warned = false
    var isPreview = false
    var savedSession: Session?
    var localMonitor: Any?
    let smoke = CommandLine.arguments.contains("--smoke-test")
    var smokeStarted = false
    var currentTime: () -> Date = { Date() }
    var inputIdle: () -> TimeInterval = {
        CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~UInt32(0))!)
    }
    var activitySnapshot: @MainActor () -> (asleep: Bool?, onConsole: Bool?) = AppDelegate.readActivitySnapshot

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        let d = UserDefaults.standard
        if d.double(forKey: "work") >= 60 { session.workDuration = d.double(forKey: "work") }
        if d.double(forKey: "rest") >= 60 { session.restDuration = d.double(forKey: "rest") }
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(systemSymbolName: "leaf", accessibilityDescription: "歇一会")
        item.button?.imagePosition = .imageLeading
        model.escape = { [weak self] in self?.endRest() }
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(self, selector: #selector(systemWillSleep), name: NSWorkspace.willSleepNotification, object: nil)
        center.addObserver(self, selector: #selector(systemDidWake), name: NSWorkspace.didWakeNotification, object: nil)
        center.addObserver(self, selector: #selector(sessionResigned), name: NSWorkspace.sessionDidResignActiveNotification, object: nil)
        center.addObserver(self, selector: #selector(sessionActivated), name: NSWorkspace.sessionDidBecomeActiveNotification, object: nil)
        center.addObserver(self, selector: #selector(displaysDidSleep), name: NSWorkspace.screensDidSleepNotification, object: nil)
        center.addObserver(self, selector: #selector(displaysDidWake), name: NSWorkspace.screensDidWakeNotification, object: nil)
        DistributedNotificationCenter.default().addObserver(self, selector: #selector(screenLocked), name: NSNotification.Name("com.apple.screenIsLocked"), object: nil, suspensionBehavior: .deliverImmediately)
        DistributedNotificationCenter.default().addObserver(self, selector: #selector(screenUnlocked), name: NSNotification.Name("com.apple.screenIsUnlocked"), object: nil, suspensionBehavior: .deliverImmediately)
        NotificationCenter.default.addObserver(self, selector: #selector(screensChanged), name: NSApplication.didChangeScreenParametersNotification, object: nil)
        center.addObserver(self, selector: #selector(spaceChanged), name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp, .flagsChanged]) { [weak self] event in
            let swallow = MainActor.assumeIsolated {
                guard let self, !self.windows.isEmpty else { return false }
                let mods: NSEvent.ModifierFlags = [.control, .option, .command]
                if event.type == .keyDown && event.keyCode == 53 && event.modifierFlags.contains(mods) {
                    if self.holdStart == nil { self.holdStart = Date() }
                } else if event.type == .keyUp || !event.modifierFlags.contains(mods) { self.holdStart = nil }
                return true
            }
            return swallow ? nil : event
        }
        startTimer(interval: 1)
        rebuildMenu()
        if CommandLine.arguments.contains("--performance-check") { runPerformanceChecks(); return }
        if CommandLine.arguments.contains("--activity-check") { runActivityChecks(); return }
        if CommandLine.arguments.contains("--music-check") { Task { await runMusicChecks() }; return }
        if CommandLine.arguments.contains("--viewing-check") { Task { await runViewingChecks() }; return }
        if CommandLine.arguments.contains("--pause-check") { runPauseChecks(); return }
        if smoke {
            isPreview = true; savedSession = session; smokeStarted = true
            session.beginRest(now: Date(), duration: 4); tick()
        } else if CommandLine.arguments.contains("--preview") { preview() }
    }
    func runActivityChecks() {
        let center = NSWorkspace.shared.notificationCenter
        let base = Date(timeIntervalSince1970: 10000)
        var time = base
        currentTime = { time }
        activitySnapshot = { (nil, nil) }
        inputIdle = { 0 }
        session = Session(); session.workDuration = 3600
        session.tick(now: time, active: true, hasInput: true)
        for second in 1...30 { time = base.addingTimeInterval(Double(second)); tick() }
        let before = session.elapsed
        center.post(name: NSWorkspace.screensDidSleepNotification, object: NSWorkspace.shared)
        for second in 31...630 { time = base.addingTimeInterval(Double(second)); tick() }
        let away = session.elapsed
        center.post(name: NSWorkspace.screensDidWakeNotification, object: NSWorkspace.shared)
        tick()
        let after = session.elapsed
        let passed = away <= before && after == 0
        print("ACTIVITY display-sleep 10min: before=\(before) away=\(away) after=\(after) \(passed ? "PASS" : "FAIL")")
        var results = [passed]
        func prepare() {
            session = Session(); session.workDuration = 3600
            systemSleeping = false; sessionInactive = false; displaysSleeping = false; locked = false
            activitySnapshot = { (nil, nil) }; inputIdle = { 0 }
            time = base
            session.tick(now: time, active: true, hasInput: true)
            for second in 1...30 { time = base.addingTimeInterval(Double(second)); tick() }
        }
        func check(_ label: String, _ ok: Bool) {
            print("ACTIVITY \(label): \(ok ? "PASS" : "FAIL")"); results.append(ok)
        }
        prepare()
        center.post(name: NSWorkspace.screensDidSleepNotification, object: NSWorkspace.shared)
        time = base.addingTimeInterval(40)
        center.post(name: NSWorkspace.screensDidWakeNotification, object: NSWorkspace.shared); tick()
        check("short display sleep preserves 30 seconds", session.elapsed == 30)

        prepare()
        // No workspace notification: the production snapshot reconciliation must stop counting.
        activitySnapshot = { (true, true) }
        for second in 31...630 { time = base.addingTimeInterval(Double(second)); tick() }
        check("missed notification fallback resets while away", session.elapsed == 0 && !session.started)
        activitySnapshot = { (false, true) }; tick()
        check("fallback wake starts fresh", session.elapsed == 0)

        prepare()
        center.post(name: NSWorkspace.sessionDidResignActiveNotification, object: NSWorkspace.shared)
        center.post(name: NSWorkspace.willSleepNotification, object: NSWorkspace.shared)
        center.post(name: NSWorkspace.didWakeNotification, object: NSWorkspace.shared)
        for second in 31...40 { time = base.addingTimeInterval(Double(second)); tick() }
        check("system wake cannot clear inactive session", session.elapsed == 30 && suspended)

        prepare()
        screenLocked()
        center.post(name: NSWorkspace.screensDidSleepNotification, object: NSWorkspace.shared)
        screenUnlocked()
        for second in 31...40 { time = base.addingTimeInterval(Double(second)); tick() }
        check("unlock cannot clear sleeping display", session.elapsed == 30 && suspended)

        prepare()
        screenLocked()
        for second in 31...630 { time = base.addingTimeInterval(Double(second)); tick() }
        check("long lock resets before unlock", session.elapsed == 0)
        screenUnlocked(); tick()
        check("unlock stays fresh", session.elapsed == 0)
        prepare()
        for second in 31...89 {
            time = base.addingTimeInterval(Double(second)); inputIdle = { Double(second - 30) }; tick()
        }
        let beforeIdle = session.elapsed
        time = base.addingTimeInterval(90); inputIdle = { 60 }; tick()
        check("idle minute keeps counting and shows idle", session.elapsed == beforeIdle + 1 && item.button?.title == " 空闲")
        for second in 91...329 {
            time = base.addingTimeInterval(Double(second)); inputIdle = { Double(second - 30) }; tick()
        }
        check("299 idle seconds still accumulate", session.elapsed == 329 && session.started)
        time = base.addingTimeInterval(330); inputIdle = { 300 }; tick()
        check("five idle minutes reset without lock", session.elapsed == 0 && !session.started)
        time = base.addingTimeInterval(331); inputIdle = { 301 }; tick()
        check("continued idle stays at zero", session.elapsed == 0 && !session.started)
        time = base.addingTimeInterval(331); inputIdle = { 0 }; tick()
        check("first input after idle begins fresh", session.elapsed == 0 && session.started)
        time = base.addingTimeInterval(332); tick()
        check("fresh session resumes counting", session.elapsed == 1)
        exit(results.allSatisfy { $0 } ? 0 : 1)
    }
    static func readActivitySnapshot() -> (asleep: Bool?, onConsole: Bool?) {
        var count: UInt32 = 0
        var asleep: Bool?
        if CGGetOnlineDisplayList(0, nil, &count) == .success && count > 0 {
            var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
            if CGGetOnlineDisplayList(count, &ids, &count) == .success && count > 0 {
                asleep = ids.prefix(Int(count)).allSatisfy { CGDisplayIsAsleep($0) != 0 }
            }
        }
        let info = CGSessionCopyCurrentDictionary() as? [String: Any]
        return (asleep, info?[kCGSessionOnConsoleKey as String] as? Bool)
    }
    func recordAbsence() {
        if suspended || locked {
            if enabled || session.restEnd != nil {
                session.tick(now: currentTime(), active: false, hasInput: false)
            }
            music.update(remaining: session.restEnd?.timeIntervalSince(currentTime()) ?? 0, suspended: true)
            hideWarning()
            hideViewingReminder()
        }
    }
    @objc func systemWillSleep() { systemSleeping = true; recordAbsence() }
    @objc func systemDidWake() { systemSleeping = false }
    @objc func sessionResigned() { sessionInactive = true; recordAbsence() }
    @objc func sessionActivated() { sessionInactive = false }
    @objc func displaysDidSleep() { displaysSleeping = true; recordAbsence() }
    @objc func displaysDidWake() { displaysSleeping = false }
    @objc func screenLocked() { locked = true; recordAbsence() }
    @objc func screenUnlocked() { locked = false }
    @objc func screensChanged() { if !windows.isEmpty { makeWindows() } }
    @objc func spaceChanged() { if !windows.isEmpty && !locked && !suspended { windows.forEach { $0.orderFrontRegardless() } } }
    func startTimer(interval: TimeInterval) {
        timer?.invalidate()
        let next = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        next.tolerance = interval * 0.1
        timer = next
        RunLoop.main.add(next, forMode: .common)
    }
    func updateTimerInterval() {
        // Keep quick escape-key checks and smooth music fades during a break.
        let interval: TimeInterval = session.restEnd == nil ? 1 : 0.25
        // Checks that invalidate the timer must remain in control of their clock.
        if let timer, timer.isValid && timer.timeInterval != interval { startTimer(interval: interval) }
    }
    func tick() {
        defer { updateTimerInterval() }
        let now = currentTime()
        let idle = inputIdle()
        let snapshot = activitySnapshot()
        if let asleep = snapshot.asleep { displaysSleeping = asleep }
        if let onConsole = snapshot.onConsole { sessionInactive = !onConsole }
        if suspended || locked { hideWarning(); hideViewingReminder() }
        if let start = holdStart, now.timeIntervalSince(start) >= 3 { endRest(); return }
        if enabled || session.restEnd != nil {
            session.tick(now: now, active: !suspended && !locked, hasInput: idle < 2, idleDuration: idle)
            if !session.viewingMode && idle >= session.idleIndicatorDuration { hideWarning() }
        }
        if let end = session.restEnd {
            let remaining = max(0, Int(ceil(end.timeIntervalSince(now))))
            if model.remaining != remaining { model.remaining = remaining }
            if windows.isEmpty && !locked && !suspended { showRest() }
            music.update(remaining: end.timeIntervalSince(now), suspended: locked || suspended)
        } else if !windows.isEmpty || isPreview {
            cleanup(); if isPreview { restorePreview() }
            if smoke && smokeStarted {
                print("SMOKE recovery: windows=\(windows.count) assertion=\(assertion) presentationRestored=\(NSApp.presentationOptions == oldPresentation) musicStopped=\(music.player == nil && !music.active)")
                NSApp.terminate(nil); return
            }
        }
        if session.elapsed == 0 { warned = false }
        if enabled && !session.viewingMode && !locked && !suspended && idle < session.idleIndicatorDuration && session.restEnd == nil && session.elapsed >= session.workDuration - 60 && !warned {
            warned = true; showWarning()
        }
        if enabled && !locked && !suspended && session.viewingReminderDue {
            showViewingReminder()
        } else { hideViewingReminder() }
        let minutes = Int(ceil(session.secondsUntilReminder / 60))
        let away = suspended || locked || (!session.viewingMode && idle.isFinite && idle >= session.idleIndicatorDuration)
        let status = session.restEnd != nil ? "休息" : (enabled ? (away ? "空闲" : (session.viewingReminderDue ? "待休息" : "\(minutes)")) : "暂停")
        let title = session.viewingMode ? " 观影 · \(status)" : " \(status)"
        // AppKit redraws the status item (and its display replicas) even for equal titles.
        if item.button?.title != title { item.button?.title = title }
    }
    func rebuildMenu() {
        let menu = NSMenu()
        func add(_ title: String, _ action: Selector?) -> NSMenuItem {
            let m = NSMenuItem(title: title, action: action, keyEquivalent: ""); m.target = self; menu.addItem(m); return m
        }
        func section(_ title: String) {
            menu.addItem(.separator())
            let header = add(title, nil)
            header.isEnabled = false
            header.attributedTitle = NSAttributedString(string: title, attributes: [
                .font: NSFont.systemFont(ofSize: 11, weight: .semibold),
                .foregroundColor: NSColor.secondaryLabelColor
            ])
        }
        _ = add("歇一会 · RestPause", nil)
        section("使用模式")
        let viewingToggle = add("观影模式", #selector(toggleViewingMode))
        viewingToggle.state = session.viewingMode ? .on : .off
        _ = add(enabled ? "暂停计时" : "继续计时", #selector(toggle))
        section("休息")
        _ = add("现在休息", #selector(restNow))
        _ = add("预览遮罩（10 秒）", #selector(preview))
        section("时长设置")
        for (label, values, action, current) in [("连续使用", [25,45,60,90], #selector(setWork(_:)), session.workDuration), ("休息时长", [1,3,5,10], #selector(setRest(_:)), session.restDuration)] {
            let parent = add(label, nil); let child = NSMenu(); parent.submenu = child
            for value in values { let m = NSMenuItem(title: "\(value) 分钟", action: action, keyEquivalent: ""); m.target = self; m.tag = value; m.state = Int(current) == value * 60 ? .on : .off; child.addItem(m) }
        }
        section("音乐")
        let musicToggle = add("休息时播放音乐", #selector(toggleMusic))
        musicToggle.state = music.enabled ? .on : .off
        let volumeMenu = NSMenu()
        add("音乐音量", nil).submenu = volumeMenu
        for (title, value) in [("轻柔 · 15%", 15), ("适中 · 25%", 25), ("清晰 · 40%", 40)] {
            let option = NSMenuItem(title: title, action: #selector(setMusicVolume(_:)), keyEquivalent: "")
            option.target = self; option.tag = value
            option.state = Int((music.volume * 100).rounded()) == value ? .on : .off
            volumeMenu.addItem(option)
        }
        _ = add("音乐来源与署名", #selector(showMusicCredits))
        menu.addItem(.separator())
        _ = add("退出歇一会", #selector(quit))
        item.menu = menu
    }
    @objc func setWork(_ sender: NSMenuItem) { session.workDuration = Double(sender.tag * 60); session.reset(); warned = false; hideWarning(); hideViewingReminder(); UserDefaults.standard.set(session.workDuration, forKey: "work"); rebuildMenu() }
    @objc func setRest(_ sender: NSMenuItem) { session.restDuration = Double(sender.tag * 60); UserDefaults.standard.set(session.restDuration, forKey: "rest"); rebuildMenu() }
    @objc func toggleMusic() { music.enabled.toggle(); rebuildMenu() }
    @objc func setMusicVolume(_ sender: NSMenuItem) { music.volume = Float(sender.tag) / 100; rebuildMenu() }
    @objc func showMusicCredits() { if let url = RestMusic.resource("Credits", extension: "txt") { NSWorkspace.shared.open(url) } }
    @objc func toggleViewingMode() {
        session.setViewingMode(!session.viewingMode)
        hideWarning(); hideViewingReminder(); warned = false
        rebuildMenu(); tick()
    }
    @objc func snoozeViewingReminder() { session.snoozeViewingReminder(); hideViewingReminder(); tick() }
    @objc func toggle() {
        enabled.toggle()
        if enabled { session.resumeTiming(now: currentTime()) }
        warned = false
        hideWarning(); hideViewingReminder()
        rebuildMenu(); tick()
    }
    @objc func quit() { cleanup(); NSApp.terminate(nil) }
    @objc func restNow() { session.beginRest(now: currentTime()); tick() }
    @objc func preview() { guard session.restEnd == nil else { return }; savedSession = session; isPreview = true; session.beginRest(now: Date(), duration: 10); tick() }
    func restorePreview() { if let saved = savedSession { session = saved }; savedSession = nil; isPreview = false }
    func showRest() {
        hideViewingReminder()
        hideWarning(); previousApp = NSWorkspace.shared.frontmostApplication
        oldPresentation = NSApp.presentationOptions
        model.chooseMessage()
        var aid: IOPMAssertionID = 0
        let result = IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleSystemSleep as CFString, IOPMAssertionLevel(kIOPMAssertionLevelOn), "RestPause: keep background work running during break" as CFString, &aid)
        if result == kIOReturnSuccess { assertion = aid; model.keepingAwake = true } else { model.keepingAwake = false }
        NSApp.activate(ignoringOtherApps: true)
        NSApp.presentationOptions = [.hideDock, .hideMenuBar, .disableProcessSwitching, .disableHideApplication]
        makeWindows()
        music.start(remaining: session.restEnd?.timeIntervalSince(currentTime()) ?? 0)
        if smoke {
            print("SMOKE coverage: screens=\(NSScreen.screens.count) windows=\(windows.count) awake=\(model.keepingAwake) musicPlaying=\(music.player?.isPlaying == true) track=\(music.currentTrack?.title ?? "none")")
            for (index, window) in windows.enumerated() { print("SMOKE window \(index): \(window.frame) visible=\(window.isVisible) level=\(window.level.rawValue)") }
        }
    }
    func makeWindows() {
        windows.forEach { $0.orderOut(nil) }; windows.removeAll()
        for screen in NSScreen.screens {
            let window = CoverWindow(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false)
            window.level = .screenSaver
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            window.isOpaque = true; window.backgroundColor = .black; window.hasShadow = false
            window.isReleasedWhenClosed = false; window.hidesOnDeactivate = false
            window.contentView = NSHostingView(rootView: RestView(model: model))
            window.setFrame(screen.frame, display: true); window.orderFrontRegardless(); windows.append(window)
        }
        windows.first?.makeKeyAndOrderFront(nil)
    }
    func endRest() { session.reset(); cleanup(); if isPreview { restorePreview() }; warned = false; updateTimerInterval() }
    func cleanup() {
        hideViewingReminder()
        music.stop()
        holdStart = nil
        windows.forEach { $0.orderOut(nil) }; windows.removeAll()
        NSApp.presentationOptions = oldPresentation
        if assertion != 0 { IOPMAssertionRelease(assertion); assertion = 0 }
        model.keepingAwake = false
        previousApp?.activate(options: []); previousApp = nil
    }
    func showWarning() {
        guard let screen = NSScreen.main else { return }
        let frame = NSRect(x: screen.visibleFrame.maxX - 424, y: screen.visibleFrame.maxY - 188, width: 400, height: 164)
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

        let leaf = NSImageView(frame: NSRect(x: 24, y: 115, width: 19, height: 19))
        leaf.image = NSImage(systemSymbolName: "leaf", accessibilityDescription: nil)
        leaf.contentTintColor = RestStyle.accent
        background.addSubview(leaf)
        let heading = NSTextField(labelWithString: "还有 1 分钟休息")
        heading.font = .systemFont(ofSize: 24, weight: .medium)
        heading.textColor = .white
        heading.frame = NSRect(x: 24, y: 64, width: 352, height: 34)
        background.addSubview(heading)
        let detail = NSTextField(labelWithString: "请保存内容，准备起身活动。")
        detail.font = .systemFont(ofSize: 13)
        detail.textColor = .white.withAlphaComponent(0.65)
        detail.frame = NSRect(x: 24, y: 32, width: 352, height: 21)
        background.addSubview(detail)
        panel.orderFrontRegardless()
        warning = panel
    }
    func hideWarning() { warning?.orderOut(nil); warning = nil }
    func applicationWillTerminate(_ notification: Notification) { cleanup() }
}
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
