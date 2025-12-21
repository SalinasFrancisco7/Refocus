import Foundation

enum RuleDecision {
    case allowed
    case blocked(String)
}

struct RuleEvaluator {
    func evaluate(urlString: String, settings: AppSettings) -> RuleDecision {
        guard let url = URL(string: urlString), let host = url.host?.lowercased() else {
            return .blocked("Unknown site")
        }

        if matches(host: host, against: settings.blockedDomains) {
            return .blocked(host)
        }

        return .allowed
    }

    private func matches(host: String, against patterns: [String]) -> Bool {
        patterns.contains(where: { pattern in
            host == pattern || host.hasSuffix(".\(pattern)")
        })
    }
}
