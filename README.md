# Refocus

Refocus locks Chrome into your work session. A SwiftUI menu bar app owns timers, rules, and enforcement; a Chrome extension reports every active tab via a Rust native-messaging host. When you land on a forbidden domain outside of a break window, Refocus escalates from notifications to a full-screen overlay and, in hard mode, force-closes Chrome.

## Components

| Piece | Path | Purpose |
| --- | --- | --- |
| macOS app | `desktop_app/` | Session timer, rules, overlay, notifications |
| Native host | `native_host/` | Receives tab JSON from Chrome and forwards to the app over `/tmp/refocus.sock` |
| Chrome extension | `chrome_extension/` | Monitors tab activation, URL changes, and window focus |

Data stays on your Mac. There is no cloud service, login, or analytics.

The Rust native host binary is bundled inside the `.app` at `Refocus.app/Contents/Helpers/refocus_native_host`; the install script below tells Chrome to launch that helper.

## Installation

1. **Build and install the macOS app (bundled native host included)**

   ```bash
   ./scripts/reinstall_refocus_app.sh
   ```

   The script runs the Release build, copies the app to `~/Applications/Refocus.app`, and (via a Run Script phase in Xcode) builds the Rust native host into
   `Refocus.app/Contents/Helpers/refocus_native_host`. Set `REFOCUS_INSTALL_DIR=/Applications` if you want the system-wide folder, or `DERIVED_DATA_PATH` if you need a custom build directory.
   Building the Xcode target inside Xcode.app produces the same bundled helper automatically, so you can also press Run in Xcode without touching the script.

2. **Install the native messaging manifest**

   ```bash
   ./scripts/install_native_host.sh
   ```

   This drops `com.refocus.native_host.json` into Chrome’s `NativeMessagingHosts` directory and rewrites the `path` field so it points at the helper bundled inside your Refocus.app. If you installed the app somewhere unusual, set `REFOCUS_APP_PATH=/path/to/Refocus.app` (or `REFOCUS_INSTALL_DIR` to match step 1) before running the script. Restart Chrome so it reloads the manifest. The manifest trusts the stable extension ID `ggkajgncinmdnpdpoplgaakbfedgbadm`.

3. **Load the Chrome extension**

   - Open `chrome://extensions`
   - Enable **Developer mode**
   - Choose **Load unpacked** and select the `chrome_extension/` folder
   - Pin the Refocus icon; it shows a red `!` if Chrome can’t talk to the native host yet

4. **Run (and reinstall) the macOS app**

   Fast path for CLI users:

   ```bash
   ./scripts/reinstall_refocus_app.sh
   ```

   That script runs the Release build and copies the output to `~/Applications/Refocus.app`, so every time you rerun it you’re testing the exact bits you just compiled. If you’d rather invoke Xcode manually, double-click `desktop_app/RefocusApp.xcodeproj` and hit Run, or run `xcodebuild …` yourself and copy the generated `.app` from DerivedData into `/Applications`.
   (Set `REFOCUS_INSTALL_DIR=/Applications` when running the script if you want the system-wide location instead.)

5. **Complete onboarding**

   On first launch the app shows a quick intro explaining what is collected, asks for notification permission, optional sound, and links to the extension instructions above.

### Building a `.pkg` installer

If you want a drag-and-drop installer experience, run:

```bash
./scripts/build_pkg.sh
```

That script rebuilds Refocus, stages the `.app` in `dist/pkgroot`, and invokes `pkgbuild` with a postinstall script that drops the Chrome native-messaging manifest into `/Library/Google/Chrome/NativeMessagingHosts` pointing at the bundled helper. The unsigned package is emitted to `dist/Refocus-<version>.pkg`; sign/notarize it with your Developer ID before distributing.

## Usage

- Start a work session from the menu bar to begin enforcement (25 min default)
- Start a break (5 min default) when you intentionally want to browse freely
- Violations trigger:
  1. Notification + optional sound (“Wrong tab. Get back to work.”)
  2. Full-screen overlay with a countdown across all displays
  3. Optional hard mode: when the countdown reaches zero Chrome is terminated
- Session state, remaining time, and break countdown are always visible in the menu bar title. Settings cover durations, grace period, sound, hard mode, and a simple domain blacklist — anything not listed stays allowed, so you only curate the distractions.

## Privacy

Refocus never transmits URLs anywhere. Native messaging JSON is piped directly into `/tmp/refocus.sock`, consumed by the local macOS app, and discarded. Logs are disabled by default.

## Development

- Native host tests: `cd native_host && cargo test`
- IPC socket path: `/tmp/refocus.sock` (override with `REFOCUS_SOCKET` for tests)
- The Swift app listens continuously; if it's not running, the native host simply drops messages.
- CLI status: `./scripts/refocusctl.py status` queries the running app via the same socket and prints current mode plus recent tabs (add `--json` for raw output).
