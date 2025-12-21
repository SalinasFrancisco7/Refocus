import Foundation
import Combine

final class SettingsStore: ObservableObject {
    @Published private(set) var settings: AppSettings {
        didSet {
            persist(settings)
        }
    }

    private let defaultsKey = "refocus.settings"

    init() {
        if let data = UserDefaults.standard.data(forKey: defaultsKey),
           let decoded = try? JSONDecoder().decode(AppSettings.self, from: data) {
            var adjusted = decoded
            let changed = SettingsStore.mergeDefaultBlockedDomains(into: &adjusted)
            settings = adjusted
            if changed {
                persist(adjusted)
            }
        } else {
            settings = AppSettings()
        }
    }

    func update(_ mutate: (inout AppSettings) -> Void) {
        var updated = settings
        mutate(&updated)
        updated.blockedDomains = Self.cleanedDomains(updated.blockedDomains)
        settings = updated
    }

    private func persist(_ settings: AppSettings) {
        guard let data = try? JSONEncoder().encode(settings) else {
            return
        }
        UserDefaults.standard.set(data, forKey: defaultsKey)
    }

    private static func cleanedDomains(_ domains: [String]) -> [String] {
        domains
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }
    }

    private static func mergeDefaultBlockedDomains(into settings: inout AppSettings) -> Bool {
        let defaults = AppSettings().blockedDomains
        var changed = false
        for domain in defaults where !settings.blockedDomains.contains(domain) {
            settings.blockedDomains.append(domain)
            changed = true
        }
        if changed {
            settings.blockedDomains = cleanedDomains(settings.blockedDomains)
        }
        return changed
    }
}
