import Foundation
import Darwin

public enum MonitorInput: String, Codable, CaseIterable, Identifiable, Sendable {
    case dp1, dp2, hdmi
    public var id: String { rawValue }
    public var value: Int { switch self { case .dp1: return 9; case .dp2: return 10; case .hdmi: return 6 } }
    public var title: String { switch self { case .dp1: return "DisplayPort 1"; case .dp2: return "DisplayPort 2"; case .hdmi: return "HDMI" } }
    public init?(value: Int) { guard let found = Self.allCases.first(where: { $0.value == value }) else { return nil }; self = found }
}
public struct Monitor: Codable, Equatable, Identifiable, Sendable {
    public var name: String
    public var serial: String
    public var selector: String
    public var online: Bool
    public var id: String { selector }
    public init(name: String, serial: String, selector: String, online: Bool) {
        self.name = name; self.serial = serial; self.selector = selector; self.online = online
    }
}
public struct InputState: Codable, Equatable, Sendable {
    public var name: String
    public var value: Int
    public init(value: Int) { self.value = value; name = MonitorInput(value: value)?.rawValue ?? "unknown" }
    public var title: String { MonitorInput(value: value)?.title ?? "Unknown input (\(value))" }
}
public struct MonitorStatus: Codable, Sendable {
    public let display: Monitor
    public let input: InputState
    public let timestamp: Date
}
public struct SwitchResult: Codable, Sendable {
    public let display: Monitor
    public let requested: MonitorInput
    public let writeAccepted: Bool
    public let verified: Bool?
    public let observedInput: InputState?
    public let warning: String?
}
public struct ControlError: LocalizedError {
    public let message: String
    public var errorDescription: String? { message }
    public init(_ message: String) { self.message = message }
}

public protocol CommandRunning {
    func run(_ arguments: [String]) throws -> String
}

/// All callers invoke a bundled helper with an argument array, never through a shell.
public struct Backend: CommandRunning {
    public let executable: URL
    public init(executable: URL? = nil) throws {
        if let executable { self.executable = executable; return }
        let binary = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
        let embedded = binary.deletingLastPathComponent().appendingPathComponent("../Resources/m1ddc").standardizedFileURL
        if FileManager.default.isExecutableFile(atPath: embedded.path) { self.executable = embedded; return }
        if let dev = ProcessInfo.processInfo.environment["CRG9_M1DDC_PATH"], FileManager.default.isExecutableFile(atPath: dev) {
            self.executable = URL(fileURLWithPath: dev); return
        }
        throw ControlError("The bundled display helper is missing. Run Scripts/build.sh to rebuild the app.")
    }
    public func run(_ arguments: [String]) throws -> String {
        let process = Process(); process.executableURL = executable; process.arguments = arguments
        // A file avoids pipe backpressure and keeps process output private to this user.
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        FileManager.default.createFile(atPath: temporary.path, contents: nil, attributes: [.posixPermissions: 0o600])
        defer { try? FileManager.default.removeItem(at: temporary) }
        let stream = try FileHandle(forWritingTo: temporary); defer { try? stream.close() }
        process.standardOutput = stream; process.standardError = stream
        let done = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in done.signal() }
        try process.run()
        if done.wait(timeout: .now() + 8) == .timedOut {
            process.terminate()
            if done.wait(timeout: .now() + 1) == .timedOut { kill(process.processIdentifier, SIGKILL); process.waitUntilExit() }
            throw ControlError("The monitor did not answer within 8 seconds. Check the display cable and try Refresh.")
        }
        let output = String(decoding: try Data(contentsOf: temporary), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        guard process.terminationStatus == 0 else { throw ControlError(output.isEmpty ? "Display communication failed." : output) }
        return output
    }
}

public enum Preferences {
    public static let defaults = UserDefaults(suiteName: "com.dan.crg9-control.shared")!
    public static var target: String? {
        get { defaults.string(forKey: "target") }
        set { if let newValue { defaults.set(newValue, forKey: "target") } else { defaults.removeObject(forKey: "target") } }
    }
}

public struct MonitorControl {
    private let runner: any CommandRunning
    public init(runner: any CommandRunning) { self.runner = runner }
    public init() throws { runner = try Backend() }
    public static func parseDisplays(_ text: String) -> [Monitor] {
        var results: [Monitor] = []
        var fields: [String: String] = [:]
        func finish() {
            guard let name = fields["Product name"], name.uppercased().contains("C49RG9"),
                  fields["Manufacturer"] == "SAM" else { return }
            let serial = fields["AN Serial"] ?? ""
            guard !serial.isEmpty, serial != "-", serial != "(null)" else { return }
            results.append(Monitor(name: name, serial: serial, selector: "serial=\(serial)", online: fields["Display ID"].flatMap(Int.init).map { $0 > 0 } ?? false))
        }
        for raw in text.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("[") { finish(); fields = [:] }
            else if line.hasPrefix("- "), let colon = line.firstIndex(of: ":") {
                let key = String(line[line.index(line.startIndex, offsetBy: 2)..<colon])
                fields[key] = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
            }
        }
        finish(); return results
    }
    public func displays() throws -> [Monitor] { try locked { try discover() } }
    private func discover() throws -> [Monitor] {
        let found = Self.parseDisplays(try runner.run(["display", "list", "all", "detailed"]))
        // Duplicate serials must never silently target an arbitrary panel.
        guard Set(found.map(\.selector)).count == found.count else { throw ControlError("Multiple CRG9 monitors report the same serial. Disconnect the other panel before controlling this one.") }
        return found
    }
    public static func select(_ monitors: [Monitor], target: String?) throws -> Monitor {
        let candidates = monitors.filter { target == nil || target == "auto" || $0.selector == target || $0.serial == target }
        guard candidates.count == 1, let monitor = candidates.first else {
            if monitors.isEmpty { throw ControlError("No CRG9 found. Check the display cable and wake the monitor, then refresh.") }
            if let target, candidates.isEmpty { throw ControlError("The selected CRG9 (\(target)) is unavailable. Refresh and choose a connected monitor.") }
            throw ControlError("More than one CRG9 is connected. Choose a display or pass --display SERIAL.")
        }
        return monitor
    }
    private func read(_ monitor: Monitor) throws -> InputState {
        let text = try runner.run(["display", monitor.selector, "get", "input"])
        guard let value = Int(text), (0...65535).contains(value) else { throw ControlError("The monitor returned an invalid input value: \(text)") }
        return InputState(value: value)
    }
    public func status(target: String? = nil) throws -> MonitorStatus {
        try locked { let monitor = try Self.select(discover(), target: target); return MonitorStatus(display: monitor, input: try read(monitor), timestamp: Date()) }
    }
    public func setInput(_ input: MonitorInput, target: String? = nil, verify: Bool = true) throws -> SwitchResult {
        try locked {
            let monitor = try Self.select(discover(), target: target)
            _ = try runner.run(["display", monitor.selector, "set", "input", String(input.value)])
            guard verify else { return SwitchResult(display: monitor, requested: input, writeAccepted: true, verified: nil, observedInput: nil, warning: nil) }
            Thread.sleep(forTimeInterval: 0.5)
            var observed: InputState?
            for attempt in 0..<2 {
                observed = try? read(monitor)
                if observed?.value == input.value { return SwitchResult(display: monitor, requested: input, writeAccepted: true, verified: true, observedInput: observed, warning: nil) }
                if attempt == 0 { Thread.sleep(forTimeInterval: 0.5) }
            }
            let warning: String
            if let observed {
                warning = "The command was sent, but the monitor still reports \(observed.title)." + (input == .dp2 ? " DP2 requires the modified 1007.3 firmware." : "")
            } else { warning = "The command was sent, but the monitor stopped answering. Verify the selected input on the monitor." }
            return SwitchResult(display: monitor, requested: input, writeAccepted: true, verified: false, observedInput: observed, warning: warning)
        }
    }
    /// Serialize DDC transactions between the desktop app and separate CLI processes.
    private func locked<T>(_ operation: () throws -> T) throws -> T {
        let folder = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Caches/com.dan.crg9-control")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let fd = open(folder.appendingPathComponent("ddc.lock").path, O_CREAT | O_RDWR | O_NOFOLLOW, S_IRUSR | S_IWUSR)
        guard fd >= 0 else { throw ControlError("Could not create the monitor communication lock.") }
        defer { close(fd) }
        let deadline = Date().addingTimeInterval(12)
        while flock(fd, LOCK_EX | LOCK_NB) != 0 {
            guard errno == EWOULDBLOCK, Date() < deadline else { throw ControlError("The monitor is busy in another app command. Try again shortly.") }
            Thread.sleep(forTimeInterval: 0.05)
        }
        defer { flock(fd, LOCK_UN) }
        return try operation()
    }
}
