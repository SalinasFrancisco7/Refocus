import SwiftUI

struct SettingsView: View {
    @ObservedObject var settingsStore: SettingsStore

    @State private var blockedText: String
    @State private var workDuration: Double
    @State private var breakDuration: Double
    @State private var graceSeconds: Double
    @State private var playSound: Bool

    private let formatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.minimum = 1
        formatter.maximum = 999
        formatter.allowsFloats = false
        return formatter
    }()

    init(settingsStore: SettingsStore) {
        self.settingsStore = settingsStore
        let settings = settingsStore.settings
        _blockedText = State(initialValue: settings.blockedDomains.joined(separator: "\n"))
        _workDuration = State(initialValue: Double(settings.workDurationMinutes))
        _breakDuration = State(initialValue: Double(settings.breakDurationMinutes))
        _graceSeconds = State(initialValue: Double(settings.graceSeconds))
        _playSound = State(initialValue: settings.playSound)
    }

    var body: some View {
        Form {
            Section(header: Text("Timing")) {
                HStack {
                    Text("Work duration (minutes)")
                    Spacer()
                    TextField("", value: $workDuration, formatter: formatter)
                        .frame(width: 80)
                        .onChange(of: workDuration) { newValue in
                            let minutes = max(1, Int(newValue))
                            settingsStore.update { $0.workDurationMinutes = minutes }
                        }
                }
                HStack {
                    Text("Break duration (minutes)")
                    Spacer()
                    TextField("", value: $breakDuration, formatter: formatter)
                        .frame(width: 80)
                        .onChange(of: breakDuration) { newValue in
                            let minutes = max(1, Int(newValue))
                            settingsStore.update { $0.breakDurationMinutes = minutes }
                        }
                }
                HStack {
                    Text("Grace period (seconds)")
                    Spacer()
                    TextField("", value: $graceSeconds, formatter: formatter)
                        .frame(width: 80)
                        .onChange(of: graceSeconds) { newValue in
                            let seconds = max(5, Int(newValue))
                            settingsStore.update { $0.graceSeconds = seconds }
                        }
                }
            }

            Section(header: Text("Alerts")) {
                Toggle("Play sound", isOn: $playSound)
                    .onChange(of: playSound) { newValue in
                        settingsStore.update { $0.playSound = newValue }
                    }
                Toggle("Hard mode (close Chrome)", isOn: Binding(
                    get: { settingsStore.settings.hardModeEnabled },
                    set: { newValue in settingsStore.update { $0.hardModeEnabled = newValue } }
                ))
            }

            Section(header: Text("Blocked domains")) {
                VStack(alignment: .leading) {
                    Text("Optional blacklist (one domain per line)")
                    TextEditor(text: $blockedText)
                        .font(.system(.body, design: .monospaced))
                        .frame(height: 100)
                        .onChange(of: blockedText) { newValue in
                            settingsStore.update { $0.blockedDomains = Self.domains(from: newValue) }
                        }
                }
            }

            Section(header: Text("Privacy")) {
                Text("Refocus never sends your URLs anywhere. All enforcement, rules, and logs live on this Mac.")
                    .font(.footnote)
            }
        }
        .padding()
        .frame(width: 520, height: 520)
    }

    private static func domains(from text: String) -> [String] {
        text
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }
    }
}
