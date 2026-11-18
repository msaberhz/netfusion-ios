import Foundation

enum ConnectionMode: String, CaseIterable {
    case smart = "SMART"
    case bonding = "BONDING"
}

enum TunnelStatus: String {
    case disconnected, connecting, connectedBonded, connectedSmart, error
}

enum AppLanguage: String, CaseIterable {
    case english = "en"
    case persianAF = "fa-AF"

    var displayName: String {
        switch self {
        case .english: return "English"
        case .persianAF: return "فارسی (افغانستان)"
        }
    }
}

struct InterfaceHealth {
    var available: Bool = false
    var rttMs: Int = -1
    var stabilityScore: Int = 0
}

struct SpeedTestEntry: Identifiable, Codable {
    var id = UUID()
    let date: Date
    let downloadMbps: Double
    let uploadMbps: Double
    let pingMs: Int
}
