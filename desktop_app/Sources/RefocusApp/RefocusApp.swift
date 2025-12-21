import SwiftUI
import AppKit

@main
struct RefocusApp: App {
    @StateObject private var appState = AppState()

    init() {
        NSApplication.shared.setActivationPolicy(.accessory)
    }

    var body: some Scene {
        MenuBarExtra {
            menuContent
        } label: {
            Label {
                Text(appState.menuTitle)
            } icon: {
                Image(systemName: appState.mode.symbolName)
                    .foregroundStyle(appState.mode.color)
            }
        }
        .menuBarExtraStyle(.menu)

        Settings {
            SettingsView(settingsStore: appState.settingsStore)
        }
    }

    private var menuContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(appState.statusLine)
                .font(.headline)

            HStack(spacing: 6) {
                Image(systemName: appState.extensionStatus.symbolName)
                    .foregroundColor(appState.extensionStatus.swiftUIColor)
                Text(appState.extensionStatus.description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Divider()
            Button(appState.sessionButtonTitle) {
                appState.toggleSession()
            }
            Divider()
            Toggle("Hard mode", isOn: appState.hardModeBinding)
            Toggle("Overlay", isOn: appState.overlayBinding)
            Toggle("Play sound", isOn: appState.playSoundBinding)
            Toggle("Notifications", isOn: appState.notificationsBinding)
            Toggle("Launch at login", isOn: appState.launchAtLoginBinding)
            Divider()
            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding(8)
        .frame(minWidth: 240)
    }
}
