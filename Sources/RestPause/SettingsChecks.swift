import AppKit

private actor SettingsCheckGate {
    private var continuation: CheckedContinuation<PhoneLinkSettings.Check, Never>?
    private(set) var calls = 0
    func check() async -> PhoneLinkSettings.Check {
        calls += 1
        return await withCheckedContinuation { continuation = $0 }
    }
    func finish() { continuation?.resume(returning: .available); continuation = nil }
}

extension AppDelegate {
    func runSettingsChecks() async {
        timer?.invalidate()
        let suite = "local.restpause.settings-check.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        var failed = false
        func check(_ label: String, _ passed: Bool) {
            print("SETTINGS \(label): \(passed ? "PASS" : "FAIL")")
            if !passed { failed = true }
        }
        var reports = 0
        let gate = SettingsCheckGate()
        let phone = PhoneLinkSettings(defaults: defaults, check: { await gate.check() }, report: { _ in reports += 1 })
        phoneLinkSettings = phone
        phone.onChange = { [weak self] in self?.phoneLinkSettingChanged() }
        rebuildMenu()
        func phoneItem() -> NSMenuItem? { item.menu?.items.first { $0.action == #selector(togglePhoneLink) } }
        check("phone link defaults off", !phone.enabled && phoneItem()?.state == .off)
        togglePhoneLink()
        for _ in 0..<50 {
            if await gate.calls > 0 { break }
            try? await Task.sleep(for: .milliseconds(10))
        }
        check("checking does not enable or persist prematurely", phone.checking && !phone.enabled && !defaults.bool(forKey: PhoneLinkSettings.preferenceKey))
        await phone.toggle()
        check("repeated activation has one check in flight", await gate.calls == 1)
        await gate.finish()
        for _ in 0..<50 {
            if !phone.checking { break }
            try? await Task.sleep(for: .milliseconds(10))
        }
        check("available shortcuts enable without a confirmation", phone.enabled && phoneItem()?.state == .on && reports == 0)
        let restored = PhoneLinkSettings(defaults: defaults, check: { .failed }, report: { _ in })
        check("phone preference survives recreation", restored.enabled)
        await phone.toggle()
        let inspectionCount = await gate.calls
        check("disabling saves off without another system check", !phone.enabled && phoneItem()?.state == .off && !defaults.bool(forKey: PhoneLinkSettings.preferenceKey) && inspectionCount == 1)

        let missing = PhoneLinkSettings(defaults: defaults, check: { .missing(["歇一会-结束"]) }, report: { result in
            if case .missing(let names) = result, names == ["歇一会-结束"] { reports += 1 }
        })
        await missing.toggle()
        check("missing shortcut reports and keeps link off", !missing.enabled && !missing.checking && reports == 1 && !defaults.bool(forKey: PhoneLinkSettings.preferenceKey))
        let unreadable = PhoneLinkSettings(defaults: defaults, check: { .failed }, report: { _ in reports += 1 })
        await unreadable.toggle()
        check("failed inspection keeps link off", !unreadable.enabled && reports == 2)
        if case .available = PhoneLinkSettings.evaluate(names: "其他指令\n歇一会-开始\r\n歇一会-结束\n") {
            check("exact names and line endings recognized", true)
        } else { check("exact names and line endings recognized", false) }
        if case .missing(let names) = PhoneLinkSettings.evaluate(names: "歇一会-开始副本\n歇一会-结束\n") {
            check("similar names do not pass inspection", names == ["歇一会-开始"])
        } else { check("similar names do not pass inspection", false) }

        var loginState: LoginItemSettings.State = .off
        loginItemSettings = LoginItemSettings(read: { loginState }, register: { loginState = .on }, unregister: { loginState = .off })
        rebuildMenu()
        func loginItem() -> NSMenuItem? { item.menu?.items.first { $0.action == #selector(toggleLoginItem) } }
        toggleLoginItem()
        check("login menu action registers and reflects system state", loginState == .on && loginItem()?.state == .on)
        toggleLoginItem()
        check("login menu action unregisters", loginState == .off && loginItem()?.state == .off)
        loginState = .needsApproval
        menuWillOpen(item.menu!)
        check("external login state refreshes and approval is not shown as enabled", loginItem()?.state == .mixed)
        try? loginItemSettings.toggle()
        check("pending approval can be disabled", loginState == .off)
        let rejected = LoginItemSettings(read: { .off }, register: { throw NSError(domain: "settings-check", code: 1) }, unregister: {})
        do {
            try rejected.toggle(); check("registration errors preserve actual state", false)
        } catch { check("registration errors preserve actual state", rejected.menuState == .off) }

        // Opt-in integration checks must run from the installed app bundle.
        // Phone preferences use the temporary suite; the original login state is restored.
        if ProcessInfo.processInfo.environment["RESTPAUSE_CHECK_SYSTEM_SETTINGS"] == "1" {
            let installedPhone = PhoneLinkSettings(defaults: defaults, report: { _ in reports += 1 })
            await installedPhone.toggle()
            check("system shortcut list enables the installed pair", installedPhone.enabled)
            let installedLogin = LoginItemSettings()
            let original = installedLogin.state
            if original == .off || original == .unavailable {
                do {
                    try installedLogin.toggle()
                    check("system login registration is enabled", installedLogin.state == .on)
                    try installedLogin.toggle()
                    check("system login unregistration restores off", installedLogin.state == .off || installedLogin.state == .unavailable)
                } catch {
                    if installedLogin.state == .on || installedLogin.state == .needsApproval { try? installedLogin.toggle() }
                    check("system login registration and restoration", false)
                    print("SETTINGS system login error: \(error.localizedDescription)")
                }
            } else {
                print("SETTINGS system login registration not changed: original=\(original)")
            }
        }

        defaults.removePersistentDomain(forName: suite)
        exit(failed ? 1 : 0)
    }
}
