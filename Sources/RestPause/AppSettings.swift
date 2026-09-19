import AppKit
import ServiceManagement

@MainActor final class PhoneLinkSettings {
    nonisolated static let preferenceKey = "phoneLinkEnabled"
    nonisolated static let shortcuts = ["歇一会-开始", "歇一会-结束"]
    enum Check: Sendable {
        case available
        case missing([String])
        case failed
    }
    private let defaults: UserDefaults
    private let check: @Sendable () async -> Check
    private let report: @MainActor (Check) -> Void
    private(set) var enabled: Bool
    private(set) var checking = false
    var onChange: @MainActor () -> Void = {}

    init(defaults: UserDefaults = .standard,
         check: @escaping @Sendable () async -> Check = {
             await Task.detached { checkShortcuts() }.value
         },
         report: @escaping @MainActor (Check) -> Void = reportCheck) {
        self.defaults = defaults; self.check = check; self.report = report
        enabled = defaults.bool(forKey: Self.preferenceKey)
    }

    func toggle() async {
        guard !checking else { return }
        if enabled { save(false); return }
        checking = true; onChange()
        defer { checking = false; onChange() }
        let result = await check()
        guard case .available = result else { report(result); return }
        save(true)
    }

    private func save(_ value: Bool) {
        enabled = value
        defaults.set(value, forKey: Self.preferenceKey)
        onChange()
    }

    nonisolated static func evaluate(names: String) -> Check {
        let installed = Set(names.split(whereSeparator: \.isNewline).map(String.init))
        let missing = shortcuts.filter { !installed.contains($0) }
        return missing.isEmpty ? .available : .missing(missing)
    }

    nonisolated private static func checkShortcuts() -> Check {
        let output = FileManager.default.temporaryDirectory.appendingPathComponent("restpause-shortcuts-\(UUID().uuidString).txt")
        defer { try? FileManager.default.removeItem(at: output) }
        guard FileManager.default.createFile(atPath: output.path, contents: nil),
              let handle = try? FileHandle(forWritingTo: output) else { return .failed }
        defer { try? handle.close() }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
        process.arguments = ["list"]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = handle
        process.standardError = FileHandle.nullDevice
        guard RestFocusLink.runProcess(process),
              let names = try? String(contentsOf: output, encoding: .utf8) else { return .failed }
        return evaluate(names: names)
    }

    private static func reportCheck(_ result: Check) {
        let alert = NSAlert()
        alert.messageText = "暂时无法开启手机联动"
        switch result {
        case .missing(let names):
            alert.informativeText = "未找到以下快捷指令：\n\n" + names.joined(separator: "\n") + "\n\n请在系统“快捷指令”中创建这些指令，名称须完全一致，并选择“歇一会”专注模式。配置完成后，再开启手机联动。"
        case .failed:
            alert.informativeText = "未能读取系统快捷指令列表。请打开“快捷指令”应用确认它能正常使用，再重试。手机联动保持关闭。"
        case .available: return
        }
        alert.addButton(withTitle: "打开快捷指令")
        alert.addButton(withTitle: "好")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn,
           let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.shortcuts") {
            NSWorkspace.shared.openApplication(at: url, configuration: .init())
        }
    }
}

@MainActor final class LoginItemSettings {
    enum State { case off, on, needsApproval, unavailable }
    private let read: () -> State
    private let register: () throws -> Void
    private let unregister: () throws -> Void
    var state: State { read() }

    init(read: @escaping () -> State = {
        switch SMAppService.mainApp.status {
        case .enabled: .on
        case .requiresApproval: .needsApproval
        case .notRegistered: .off
        case .notFound: .unavailable
        @unknown default: .unavailable
        }
    }, register: @escaping () throws -> Void = { try SMAppService.mainApp.register() },
         unregister: @escaping () throws -> Void = { try SMAppService.mainApp.unregister() }) {
        self.read = read; self.register = register; self.unregister = unregister
    }

    func toggle() throws {
        switch state {
        case .on, .needsApproval: try unregister()
        case .off, .unavailable: try register()
        }
    }

    var menuState: NSControl.StateValue {
        switch state {
        case .on: .on
        case .needsApproval: .mixed
        case .off, .unavailable: .off
        }
    }
}
