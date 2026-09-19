import Foundation
import Darwin

/// Serializes Shortcuts calls without blocking the cover, countdown, or emergency unlock.
@MainActor final class RestFocusLink {
    typealias Run = @Sendable (String, Date?) async -> Bool
    private let run: Run
    private var tail: Task<Void, Never>?
    private var generation = 0
    private var active = false
    private(set) var pending = 0
    var enabled = true
    var onFailure: @MainActor (String) -> Void = { _ in }

    init(run: @escaping Run = { name, end in
        await Task.detached { execute(name: name, end: end) }.value
    }) { self.run = run }

    func begin(until end: Date) {
        guard enabled, !active else { return }
        active = true
        generation += 1
        let request = generation
        enqueue { [weak self] in
            guard let self, self.active, self.generation == request, end > Date() else { return }
            if await !self.run("歇一会-开始", end) { self.onFailure("歇一会-开始") }
        }
    }

    func end() {
        guard active else { return }
        active = false
        generation += 1
        enqueue { [weak self] in
            guard let self else { return }
            if await !self.run("歇一会-结束", nil) { self.onFailure("歇一会-结束") }
        }
    }

    func finish() async { await tail?.value }

    private func enqueue(_ operation: @escaping @MainActor () async -> Void) {
        let previous = tail
        pending += 1
        tail = Task { [weak self] in
            await previous?.value
            await operation()
            self?.pending -= 1
        }
    }

    nonisolated private static func execute(name: String, end: Date?) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
        process.arguments = ["run", name]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        var input: URL?
        defer { if let input { try? FileManager.default.removeItem(at: input) } }
        do {
            if let end {
                guard end > Date() else { return false }
                let url = FileManager.default.temporaryDirectory.appendingPathComponent("restpause-focus-\(UUID().uuidString).txt")
                input = url
                // The shortcut explicitly converts this local ISO timestamp to a date.
                let formatter = ISO8601DateFormatter()
                formatter.timeZone = .current
                try formatter.string(from: end).write(to: url, atomically: true, encoding: .utf8)
                process.arguments! += ["-i", url.path]
            }
            let success = runProcess(process)
            if !success { print("FOCUS shortcut failed or timed out: \(name)") }
            return success
        } catch {
            print("FOCUS shortcut could not run: \(name)")
            return false
        }
    }

    /// Runs on a background thread; bounded even when Shortcuts waits for user input.
    nonisolated static func runProcess(_ process: Process) -> Bool {
        do { try process.run() } catch { return false }
        let exited = DispatchSemaphore(value: 0)
        DispatchQueue.global(qos: .utility).async {
            process.waitUntilExit()
            exited.signal()
        }
        if exited.wait(timeout: .now() + 15) == .timedOut {
            if process.isRunning { process.terminate() }
            if exited.wait(timeout: .now() + 1) == .timedOut {
                if process.isRunning { kill(process.processIdentifier, SIGKILL) }
                exited.wait()
            }
            return false
        }
        return process.terminationStatus == 0
    }
}
