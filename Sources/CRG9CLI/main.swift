import Foundation
import CRG9Core
import Darwin

let help = """
crg9-control — native Samsung CRG9 input control

Usage:
  crg9-control list [--json]
  crg9-control status [--display SERIAL] [--json]
  crg9-control input dp1|dp2|hdmi [--display SERIAL] [--json] [--no-verify]
  crg9-control dp1|dp2|hdmi [--display SERIAL] [--json] [--no-verify]
  crg9-control --help

--display auto selects the only detected CRG9, ignoring the saved selection.
--display otherwise accepts the EDID serial from 'list', or serial=SERIAL.
The app's selected monitor is used when --display is omitted.
DP2 requires modified CCAA 1007.3 firmware. PBP control is unavailable.
Exit codes: 0 success; 1 communication error; 2 invalid arguments;
            3 command sent but input change could not be verified.
"""
struct UsageError: Error { let text: String }
func json<T: Encodable>(_ value: T) throws {
    let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; encoder.dateEncodingStrategy = .iso8601
    print(String(decoding: try encoder.encode(value), as: UTF8.self))
}
var args = Array(CommandLine.arguments.dropFirst())
var asJSON = false
var target: String? = Preferences.target
var verify = true
var positional: [String] = []
do {
    if args == ["--help"] || args == ["-h"] || args.isEmpty { print(help); exit(0) }
    while !args.isEmpty {
        let arg = args.removeFirst()
        switch arg {
        case "--json": asJSON = true
        case "--no-verify": verify = false
        case "--display":
            guard let next = args.first, !next.hasPrefix("--"), !next.isEmpty else { throw UsageError(text: "--display requires a serial.") }
            target = args.removeFirst()
        default:
            guard !arg.hasPrefix("-") else { throw UsageError(text: "Unknown option: \(arg)") }
            positional.append(arg)
        }
    }
    let command = positional.first ?? ""
    let requested: MonitorInput?
    if command == "input" { guard positional.count == 2, let input = MonitorInput(rawValue: positional[1]) else { throw UsageError(text: "Use input dp1, input dp2, or input hdmi.") }; requested = input }
    else if let input = MonitorInput(rawValue: command), positional.count == 1 { requested = input }
    else if (command == "status" || command == "list") && positional.count == 1 { requested = nil }
    else { throw UsageError(text: "Unknown command or extra arguments. Run crg9-control --help.") }
    guard verify || requested != nil else { throw UsageError(text: "--no-verify is only valid when switching inputs.") }
    let control = try MonitorControl()
    if command == "list" {
        let displays = try control.displays()
        if asJSON { try json(displays) }
        else if displays.isEmpty { print("No CRG9 detected.") }
        else { for display in displays { print("\(display.name)  \(display.serial)  \(display.online ? "on Mac desktop" : "DDC reachable")") } }
    } else if let input = requested {
        let result = try control.setInput(input, target: target, verify: verify)
        if asJSON { try json(result) }
        else if let warning = result.warning { print(warning) }
        else { print(result.verified == true ? "Verified: \(input.title)" : "Sent: \(input.title) (verification disabled)") }
        if result.verified == false { exit(3) }
    } else {
        let status = try control.status(target: target)
        if asJSON { try json(status) } else { print("\(status.display.name) · \(status.display.serial): \(status.input.title) (\(status.input.value))") }
    }
} catch let error as UsageError {
    FileHandle.standardError.write(Data((error.text + "\n").utf8)); exit(2)
} catch {
    if asJSON { try? json(["error": error.localizedDescription]) }
    else { FileHandle.standardError.write(Data((error.localizedDescription + "\n").utf8)) }
    exit(1)
}
