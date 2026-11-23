import SwiftUI
import AppKit
import CRG9Core

@MainActor final class MonitorModel: ObservableObject {
    @Published var monitors: [Monitor] = []
    @Published var selected: String = Preferences.target ?? ""
    @Published var current: InputState?
    @Published var busy = false
    @Published var message = "Looking for your CRG9…"
    @Published var hasError = false
    @Published var lastUpdated: Date?
    var selectedMonitor: Monitor? { monitors.first { $0.selector == selected } }
    var cliPath: String { Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/crg9-control").path }
    func refresh() {
        guard !busy else { return }
        busy = true; hasError = false
        let target = selected.isEmpty ? nil : selected
        Task {
            do {
                let result = try await Task.detached { () throws -> ([Monitor], MonitorStatus) in
                    let control = try MonitorControl()
                    let found = try control.displays()
                    let resolved = try MonitorControl.select(found, target: found.count == 1 ? nil : target)
                    return (found, try control.status(target: resolved.selector))
                }.value
                monitors = result.0; selected = result.1.display.selector
                Preferences.target = selected
                current = result.1.input; message = "Ready"; lastUpdated = Date()
            } catch {
                // Keep the discovered list usable if one of the monitors fails to answer status.
                let found = await Task.detached { try? MonitorControl().displays() }.value
                monitors = found ?? []; current = nil; message = error.localizedDescription; hasError = true
            }
            busy = false
        }
    }
    func choose(_ selector: String) { selected = selector; Preferences.target = selector.isEmpty ? nil : selector; refresh() }
    func switchTo(_ input: MonitorInput) {
        guard !busy, !selected.isEmpty else { return }
        busy = true; hasError = false; message = "Switching to \(input.title)…"
        let target = selected
        Task {
            do {
                let result = try await Task.detached { try MonitorControl().setInput(input, target: target) }.value
                current = result.observedInput
                if result.verified == true { message = "Switched to \(input.title)"; hasError = false }
                else { message = result.warning ?? "Command sent; input not verified."; hasError = true }
                lastUpdated = Date()
            } catch { current = nil; message = error.localizedDescription; hasError = true }
            busy = false
        }
    }
    func copyCommand(_ input: MonitorInput? = nil) {
        func quote(_ s: String) -> String { "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'" }
        var text = quote(cliPath) + (input.map { " input \($0.rawValue)" } ?? " status --json")
        if !selected.isEmpty { text += " --display " + quote(selected) }
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text, forType: .string)
    }
}

struct SourceButton: View {
    let input: MonitorInput
    let active: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 13) {
                HStack {
                    Image(systemName: input == .hdmi ? "cable.connector" : "display").font(.title2)
                    Spacer()
                    if active { Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.accentColor) }
                }
                Text(input.title).font(.headline)
                Text(active ? "Current input" : "Switch input").font(.caption).foregroundStyle(.secondary)
            }
            .padding(18).frame(maxWidth: .infinity, alignment: .leading)
            .background(active ? Color.accentColor.opacity(0.10) : Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 13))
            .overlay(RoundedRectangle(cornerRadius: 13).strokeBorder(active ? Color.accentColor.opacity(0.65) : Color.secondary.opacity(0.18), lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: 13))
        }.buttonStyle(.plain).accessibilityLabel("Switch to \(input.title)")
    }
}

struct ControlView: View {
    @ObservedObject var model: MonitorModel
    @State private var automation = false
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("CRG9 Control").font(.largeTitle.weight(.semibold))
                    Text("Your ultrawide. One click away.").foregroundStyle(.secondary)
                }
                Spacer()
                Button { model.refresh() } label: { Image(systemName: "arrow.clockwise") }
                    .help("Refresh monitor status (⌘R)").disabled(model.busy).keyboardShortcut("r")
            }
            HStack {
                Picker("Monitor", selection: Binding(get: { model.selected }, set: { model.choose($0) })) {
                    Text("Choose a monitor").tag("")
                    ForEach(model.monitors) { display in Text("\(display.name) · \(display.serial)").tag(display.selector) }
                }.labelsHidden().disabled(model.busy).frame(maxWidth: 360)
                Spacer()
                if model.busy { ProgressView().controlSize(.small) }
                else { Label(model.current == nil ? "Unavailable" : "Connected", systemImage: model.current == nil ? "circle" : "circle.fill")
                        .font(.caption).foregroundStyle(model.current == nil ? Color.secondary : Color.green) }
            }
            VStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12).fill(LinearGradient(colors: [Color.accentColor.opacity(0.2), Color.accentColor.opacity(0.05)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    RoundedRectangle(cornerRadius: 12).strokeBorder(Color.secondary.opacity(0.25))
                    VStack(spacing: 6) {
                        Text(model.current?.title ?? (model.busy ? "Reading monitor…" : "No input readback"))
                            .font(.title2.weight(.medium))
                        Text("SAMSUNG CRG9").font(.system(size: 10, weight: .semibold, design: .rounded)).tracking(3).foregroundStyle(.secondary)
                    }
                }.frame(height: 112)
                Capsule().fill(Color.secondary.opacity(0.3)).frame(width: 72, height: 4)
            }.padding(.horizontal, 30).accessibilityElement(children: .combine)
            HStack(spacing: 12) {
                ForEach(Array(MonitorInput.allCases.enumerated()), id: \.element.id) { index, input in
                    SourceButton(input: input, active: model.current?.value == input.value) { model.switchTo(input) }
                        .keyboardShortcut(KeyEquivalent(Character(String(index + 1))), modifiers: .command)
                        .contextMenu { Button("Copy CLI command") { model.copyCommand(input) } }
                }
            }.disabled(model.busy || model.selected.isEmpty || model.selectedMonitor == nil)
            VStack(alignment: .leading, spacing: 8) {
                Label(model.message, systemImage: model.hasError ? "exclamationmark.circle" : "info.circle")
                    .font(.callout).foregroundStyle(model.hasError ? Color.orange : Color.secondary)
                    .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                Text("DP2 needs the modified 1007.3 firmware. PBP controls are unavailable.")
                    .font(.caption).foregroundStyle(.secondary)
            }.frame(maxWidth: .infinity, minHeight: 48, alignment: .topLeading)
            Divider()
            HStack {
                Text("⌘1  DP1     ⌘2  DP2     ⌘3  HDMI").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Automation…") { automation.toggle() }.buttonStyle(.link)
                    .popover(isPresented: $automation) { automationView.padding(22).frame(width: 420) }
            }
        }.padding(26).frame(width: 650)
        .task { model.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in model.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSWorkspace.didWakeNotification)) { _ in model.refresh() }
    }
    var automationView: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Call it from any app").font(.headline)
            Text("The CLI works without this window open. Right-click an input to copy its command.")
            Text("crg9-control input dp2 --json").font(.system(.callout, design: .monospaced)).textSelection(.enabled)
            Button("Copy status command") { model.copyCommand() }
            Text("A successful write is verified when the monitor answers. Some monitors stop answering after switching away from the Mac.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

struct TrayView: View {
    @ObservedObject var model: MonitorModel
    @Environment(\.openWindow) var openWindow
    var body: some View {
        Text(model.current?.title ?? "CRG9 Control")
        Divider()
        ForEach(MonitorInput.allCases) { input in
            Button(input.title) { model.switchTo(input) }.disabled(model.busy || model.selectedMonitor == nil)
        }
        Divider()
        Button("Refresh") { model.refresh() }.disabled(model.busy)
        Button("Open CRG9 Control") { openWindow(id: "control"); NSApp.activate(ignoringOtherApps: true) }
        Button("Quit CRG9 Control") { NSApp.terminate(nil) }
    }
}

@main struct CRG9Application: App {
    @StateObject private var model = MonitorModel()
    var body: some Scene {
        Window("CRG9 Control", id: "control") { ControlView(model: model) }
            .windowResizability(.contentSize)
        MenuBarExtra("CRG9 Control", systemImage: "display") { TrayView(model: model) }
    }
}
