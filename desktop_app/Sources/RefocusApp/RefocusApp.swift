import SwiftUI

@main
struct RefocusApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        MenuBarExtra(appState.menuTitle) {
            Button("Start work session") {
                appState.startWork()
            }
            Button("Start break") {
                appState.startBreak()
            }
            Button("Stop session") {
                appState.stopSession()
            }
            Divider()
            Toggle("Hard mode", isOn: $appState.hardMode)
            Divider()
            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
        }
    }
}

final class AppState: ObservableObject {
    @Published var mode: SessionMode = .idle
    @Published var hardMode: Bool = false

    private let ipcServer = UnixSocketServer()

    var menuTitle: String {
        switch mode {
        case .idle: return "Idle"
        case .work: return "Work"
        case .break: return "Break"
        case .violationGrace: return "Grace"
        case .violationEnforced: return "Blocked"
        }
    }

    init() {
        ipcServer.onEvent = { event in
            print("Received tab event: \(event)")
        }
        ipcServer.start()
    }

    func startWork() {
        mode = .work
    }

    func startBreak() {
        mode = .break
    }

    func stopSession() {
        mode = .idle
    }
}

enum SessionMode {
    case idle
    case work
    case break
    case violationGrace
    case violationEnforced
}
