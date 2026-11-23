# CRG9 Control

Native SwiftUI macOS app and standalone CLI for Samsung CRG9 input switching on Apple Silicon. No browser, Electron, server, Homebrew dependency, or running GUI is needed for the CLI.

## Build and run

Requires Xcode or Apple's Swift command-line tools, macOS 13 or later, and an Apple Silicon Mac.

```sh
./Scripts/build.sh
open 'build/CRG9 Control.app'
./bin/crg9-control status --json
```

Open `Package.swift` in Xcode to work on the Swift targets. Use `Scripts/build.sh` to produce the complete app bundle with its native DDC helper, icon, and ad-hoc signature. The bundle can be moved to Applications; its CLI lives at `CRG9 Control.app/Contents/MacOS/crg9-control`. The repository's `bin/crg9-control` launcher targets the repository build. Put `/Users/dan/repos/crg9-control/bin` on PATH to use the short command name.

The main window includes the current input, monitor picker, refresh, and three input buttons. Command-1, Command-2, and Command-3 switch DP1, DP2, and HDMI while the app is active. A menu-bar item gives quick access. These are app shortcuts, not system-wide hotkeys. Right-click an input to copy its CLI command. The selected monitor is shared with the CLI.

## CLI

```sh
crg9-control list --json
crg9-control status --json
crg9-control input dp1
crg9-control input dp2 --json
crg9-control hdmi --display H1AK500000 --json
```

`--display auto` selects the only detected CRG9 and ignores the saved selection. This is useful when an inactive input reports a placeholder EDID serial. It fails if multiple CRG9 monitors are detected.

`--display` otherwise accepts an EDID serial or `serial=SERIAL`. Omit it to use the app selection or automatically select the only connected CRG9. Ambiguous monitors cause an error; unrelated displays are never selected. The helper enumerates DDC services by EDID serial, including monitors that remain reachable while showing another computer. Whether an inactive input accepts commands still depends on the monitor and cable.

Writes are followed by readback. Exit status **0** means success, **1** a communication error, **2** invalid arguments, and **3** a command sent without a verified input change. JSON exposes `writeAccepted`, `verified`, `observedInput`, and any warning. `--no-verify` deliberately sends without readback, reports `verified` as absent, and exits 0 after a successful transport write. This does not prove the monitor changed inputs. Error JSON goes to stdout; human-readable errors go to stderr.

The app and CLI serialize their DDC transactions with a per-user file lock. They can run independently. Preferences contain only the selected hardware serial; no display UUID is hardcoded. No daemon, Accessibility permission, or Screen Recording permission is required.

## Firmware and limits

Samsung CRG9 input values are **DP1 = 9, DP2 = 10, HDMI = 6** (VCP 0x60). Stock CCAA 1007.2 lacks the DP2 setter. DP2 requires the independently developed modified 1007.3 firmware discussed at https://github.com/emulvihill/samsung-crg9-firmware. This app does not include, install, or flash firmware. It cannot infer the full installed firmware version from the monitor's standard version query.

PBP control is not exposed. The prepared DP2 firmware patch does not add it. Brightness, volume, presets, and arbitrary service commands are deliberately outside this app's scope.

## Validation

```sh
swift test
python3 Scripts/test-cli.py
./bin/crg9-control list --json
./bin/crg9-control status --json
```

Tests cover model filtering, inactive displays, ambiguous identities, Samsung's input codes, invalid replies, ignored writes, disconnection after switching, and unverified-send semantics. Hardware smoke testing should switch to the input already reported by `status` to avoid interrupting the desktop. Test real cross-input switching with the monitor joystick accessible for recovery.

The app and CLI share `Sources/CRG9Core`. `Vendor/m1ddc` is unmodified MIT-licensed upstream code for Apple's private native IOAVService DDC transport. The exact revision is in `Vendor/UPSTREAM-COMMIT`. Future macOS updates may affect private API compatibility. Swift project code is MIT licensed; see `LICENSE` and the vendored license.
