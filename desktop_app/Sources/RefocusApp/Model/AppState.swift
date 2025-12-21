import AppKit
import Combine
import Foundation
import ServiceManagement
import SwiftUI

struct RecentTab: Identifiable {
    let id = UUID()
    let url: String
    let host: String
    let timestamp: Date
}

final class AppState: ObservableObject {
    @Published private(set) var mode: SessionMode = .idle
    @Published private(set) var menuTitle: String = "Idle"
    @Published private(set) var statusLine: String = "No session running"

    let settingsStore = SettingsStore()

    private let ipcServer = UnixSocketServer()
    private let overlayController = OverlayController()
    private let notificationManager = NotificationManager()
    private let evaluator = RuleEvaluator()

    @Published private(set) var recentTabs: [RecentTab] = []

    private var graceDeadline: Date?
    private var violationHost: String?
    private var tickTimer: Timer?
    private var cancellables: Set<AnyCancellable> = []

    var sessionButtonTitle: String {
        isSessionActive ? "Stop session" : "Start session"
    }

    var isSessionActive: Bool {
        switch mode {
        case .work, .violationGrace, .violationEnforced:
            return true
        default:
            return false
        }
    }

    func toggleSession() {
        if isSessionActive {
            stopSession()
        } else {
            startWork()
        }
    }

    var hardModeBinding: Binding<Bool> {
        Binding(
            get: { self.settingsStore.settings.hardModeEnabled },
            set: { [weak self] newValue in
                self?.settingsStore.update { $0.hardModeEnabled = newValue }
            }
        )
    }

    var isHardModeEnabled: Bool {
        settingsStore.settings.hardModeEnabled
    }

    var playSoundBinding: Binding<Bool> {
        Binding(
            get: { self.settingsStore.settings.playSound },
            set: { [weak self] newValue in
                self?.settingsStore.update { $0.playSound = newValue }
            }
        )
    }

    var overlayBinding: Binding<Bool> {
        Binding(
            get: { self.settingsStore.settings.overlayEnabled },
            set: { [weak self] newValue in
                self?.settingsStore.update { $0.overlayEnabled = newValue }
            }
        )
    }

    var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { SMAppService.mainApp.status == .enabled },
            set: { newValue in
                do {
                    if newValue {
                        try SMAppService.mainApp.register()
                    } else {
                        try SMAppService.mainApp.unregister()
                    }
                } catch {
                    print("[Refocus] Failed to update launch at login: \(error)")
                }
            }
        )
    }

    @Published private(set) var notificationsEnabled = false

    var notificationsBinding: Binding<Bool> {
        Binding(
            get: { self.notificationsEnabled },
            set: { [weak self] newValue in
                if newValue {
                    self?.notificationManager.requestAuthorization { granted in
                        DispatchQueue.main.async {
                            self?.notificationsEnabled = granted
                            if !granted {
                                self?.notificationManager.openNotificationSettings()
                            }
                        }
                    }
                } else {
                    // Can't programmatically disable, open System Settings
                    self?.notificationManager.openNotificationSettings()
                }
            }
        )
    }

    func checkNotificationPermission() {
        notificationManager.checkAuthorization { [weak self] authorized in
            DispatchQueue.main.async {
                self?.notificationsEnabled = authorized
            }
        }
    }

    init() {
        observeSettings()
        ipcServer.onEvent = { [weak self] event in
            DispatchQueue.main.async {
                self?.handle(tabEvent: event)
            }
        }
        ipcServer.statusProvider = { [weak self] in
            self?.statusSnapshot()
        }
        ipcServer.start()
        startTick()
        checkNotificationPermission()
    }

    deinit {
        tickTimer?.invalidate()
    }

    func startWork() {
        mode = .work
        clearViolationState()
        updateStatus()
    }

    func stopSession() {
        mode = .idle
        clearViolationState()
        updateStatus()
    }

    private func startTick() {
        let timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.tick()
        }
        tickTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func tick() {
        updateStatus()
        let now = Date()
        switch mode {
        case .work:
            break
        case .violationGrace:
            guard let deadline = graceDeadline else { return }
            if now >= deadline {
                enterEnforcedState()
            } else if settingsStore.settings.overlayEnabled {
                let remaining = max(0, Int(deadline.timeIntervalSince(now)))
                overlayController.show(message: violationMessage(), countdown: "\(remaining)")
            }
        case .violationEnforced:
            if settingsStore.settings.overlayEnabled {
                overlayController.show(message: violationMessage(), countdown: "0")
            }
        default:
            break
        }
    }

    private func updateStatus() {
        switch mode {
        case .idle:
            menuTitle = "Idle"
            statusLine = "No session running"
        case .work:
            menuTitle = "Working"
            statusLine = "Session active"
        case .violationGrace:
            menuTitle = "Grace"
            statusLine = "Forbidden tab detected"
        case .violationEnforced:
            menuTitle = "Blocked"
            statusLine = "Chrome blocked until you comply"
        }
    }

    private func handle(tabEvent: TabEvent) {
        guard tabEvent.type == "TAB_EVENT" else { return }
        guard mode == .work || mode == .violationGrace || mode == .violationEnforced else {
            recordRecentTab(from: tabEvent)
            return
        }

        recordRecentTab(from: tabEvent)

        let decision = evaluator.evaluate(urlString: tabEvent.url, settings: settingsStore.settings)
        switch decision {
        case .allowed:
            if mode == .violationGrace || mode == .violationEnforced {
                resumeFromViolation()
            }
        case .blocked(let host):
            triggerViolation(for: host)
        }
    }

    private func triggerViolation(for host: String) {
        violationHost = host
        graceDeadline = Date().addingTimeInterval(TimeInterval(settingsStore.settings.graceSeconds))
        mode = .violationGrace
        notificationManager.send(
            title: "Wrong tab",
            body: "\(host) is not allowed during work.",
            playSound: settingsStore.settings.playSound
        )
        if settingsStore.settings.overlayEnabled {
            overlayController.show(message: violationMessage(), countdown: "\(settingsStore.settings.graceSeconds)")
        }
        updateStatus()
    }

    private func enterEnforcedState() {
        mode = .violationEnforced
        if settingsStore.settings.overlayEnabled {
            overlayController.show(message: violationMessage(), countdown: "0")
        }
        if isHardModeEnabled {
            forceCloseChrome()
        }
        updateStatus()
    }

    private func resumeFromViolation() {
        violationHost = nil
        graceDeadline = nil
        mode = .work
        overlayController.hide()
        updateStatus()
    }

    private func clearViolationState() {
        violationHost = nil
        graceDeadline = nil
        overlayController.hide()
    }

    private func recordRecentTab(from event: TabEvent) {
        let timestamp = Date()
        let host = URL(string: event.url)?.host ?? event.url
        let summary = RecentTab(
            url: event.url,
            host: host,
            timestamp: timestamp
        )

        recentTabs.removeAll(where: { $0.host == summary.host })
        recentTabs.insert(summary, at: 0)
        if recentTabs.count > 10 {
            recentTabs = Array(recentTabs.prefix(10))
        }
    }

    private func violationMessage() -> String {
        guard let host = violationHost else {
            return "Focus now."
        }
        return "\(host) is not allowed during work"
    }

    private func forceCloseChrome() {
        let apps = NSRunningApplication.runningApplications(withBundleIdentifier: "com.google.Chrome")
        for app in apps {
            if !app.terminate() {
                app.forceTerminate()
            }
        }
    }

    private func observeSettings() {
        settingsStore.objectWillChange
            .sink { [weak self] in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
    }

    private func statusSnapshot() -> CLIStatusResponse {
        let currentMode = mode
        let currentMenuTitle = menuTitle
        let currentStatusLine = statusLine
        let currentHardMode = settingsStore.settings.hardModeEnabled
        let currentGraceDeadline = graceDeadline
        let currentRecentTabs = recentTabs

        let remaining: Int?
        if let deadline = currentGraceDeadline, currentMode == .violationGrace {
            remaining = max(0, Int(deadline.timeIntervalSinceNow))
        } else {
            remaining = nil
        }

        let recent = currentRecentTabs.map { tab in
            CLIStatusResponse.Recent(
                host: tab.host,
                url: tab.url,
                timestamp: tab.timestamp.timeIntervalSince1970
            )
        }

        return CLIStatusResponse(
            mode: currentMode.displayName,
            menuTitle: currentMenuTitle,
            statusLine: currentStatusLine,
            hardModeEnabled: currentHardMode,
            workSecondsRemaining: remaining,
            recentTabs: recent
        )
    }
}

enum SessionMode {
    case idle
    case work
    case violationGrace
    case violationEnforced

    var symbolName: String {
        switch self {
        case .idle: return "pause.circle.fill"
        case .work: return "bolt.fill"
        case .violationGrace: return "exclamationmark.triangle.fill"
        case .violationEnforced: return "nosign"
        }
    }

    var displayName: String {
        switch self {
        case .idle: return "idle"
        case .work: return "work"
        case .violationGrace: return "violation_grace"
        case .violationEnforced: return "violation_enforced"
        }
    }
}
