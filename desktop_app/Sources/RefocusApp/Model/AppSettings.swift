import Foundation

struct AppSettings: Codable {
    var workDurationMinutes: Int = 25
    var breakDurationMinutes: Int = 5
    var graceSeconds: Int = 15
    var playSound: Bool = true
    var hardModeEnabled: Bool = false
    var overlayEnabled: Bool = true
    var blockedDomains: [String] = [
        "youtube.com",
        "twitter.com",
        "x.com",
        "mobile.twitter.com",
        "news.ycombinator.com",
        "reddit.com",
        "instagram.com",
        "facebook.com",
        "tiktok.com",
        "netflix.com",
        "discord.com"
    ]
    var hasCompletedOnboarding: Bool = false

    var workDuration: TimeInterval { TimeInterval(workDurationMinutes * 60) }
    var breakDuration: TimeInterval { TimeInterval(breakDurationMinutes * 60) }
}
