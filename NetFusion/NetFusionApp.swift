import SwiftUI

@main
struct NetFusionApp: App {
    @AppStorage("appLanguage") private var langRaw: String = AppLanguage.english.rawValue
    @AppStorage("isDarkTheme") private var isDark: Bool = true
    @StateObject private var netMonitor = NetworkMonitorService()
    @StateObject private var tunnel = TunnelManager()
    @StateObject private var speedTest = SpeedTestService()

    var body: some Scene {
        WindowGroup {
            let lang = AppLanguage(rawValue: langRaw) ?? .english
            ContentView()
                .environmentObject(netMonitor)
                .environmentObject(tunnel)
                .environmentObject(speedTest)
                .environment(\.locale, Locale(identifier: lang.rawValue))
                .environment(\.layoutDirection, lang == .persianAF ? .rightToLeft : .leftToRight)
                .preferredColorScheme(isDark ? .dark : .light)
                .onAppear { netMonitor.start() }
        }
    }
}
