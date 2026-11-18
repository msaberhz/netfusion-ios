import SwiftUI

struct ContentView: View {
    @EnvironmentObject var netMonitor: NetworkMonitorService
    @EnvironmentObject var tunnel: TunnelManager
    @EnvironmentObject var speedTest: SpeedTestService

    @AppStorage("serverHost") private var serverHost = ""
    @AppStorage("serverPort") private var serverPort = 51880
    @AppStorage("serverToken") private var serverToken = ""
    @AppStorage("customDns") private var customDns = "1.1.1.1"
    @AppStorage("appLanguage") private var langRaw = AppLanguage.english.rawValue
    @AppStorage("isDarkTheme") private var isDark = true
    @AppStorage("selectedMode") private var modeRaw = ConnectionMode.smart.rawValue

    private var isFa: Bool { langRaw == AppLanguage.persianAF.rawValue }

    var body: some View {
        TabView {
            dashboardTab
                .tabItem { Label(isFa ? "داشبورد" : "Dashboard", systemImage: "bolt.shield.fill") }

            connectionsTab
                .tabItem { Label(isFa ? "اتصال‌ها" : "Connections", systemImage: "wifi") }

            speedTestTab
                .tabItem { Label(isFa ? "تست سرعت" : "Speed Test", systemImage: "speedometer") }

            settingsTab
                .tabItem { Label(isFa ? "تنظیمات" : "Settings", systemImage: "gearshape.fill") }
        }
    }

    private var dashboardTab: some View {
        NavigationStack {
            VStack(spacing: 22) {
                Text(tunnel.status == .connectedBonded
                     ? (isFa ? "متصل • ترکیب وای‌فای + موبایل" : "Connected • Bonded")
                     : (isFa ? "قطع شده" : "Disconnected"))
                    .font(.headline)
                    .foregroundStyle(tunnel.status == .connectedBonded ? .green : .secondary)

                Button {
                    if tunnel.status == .disconnected || tunnel.status == .error {
                        Task { await tunnel.connect(host: serverHost, port: serverPort, token: serverToken, dns: customDns) }
                    } else {
                        tunnel.disconnect()
                    }
                } label: {
                    ZStack {
                        Circle()
                            .fill(LinearGradient(colors: [.cyan.opacity(0.25), .blue.opacity(0.15)], startPoint: .top, endPoint: .bottom))
                            .frame(width: 170, height: 170)
                            .overlay(Circle().stroke(tunnel.status == .connectedBonded ? Color.green : Color.cyan, lineWidth: 4))
                        VStack(spacing: 8) {
                            Image(systemName: "power")
                                .font(.system(size: 40, weight: .bold))
                            Text(tunnel.status == .disconnected ? (isFa ? "اتصال" : "Connect") : (isFa ? "قطع اتصال" : "Disconnect"))
                                .font(.title3.bold())
                        }
                    }
                }

                HStack(spacing: 12) {
                    statusCard(title: isFa ? "وای‌فای" : "Wi-Fi", icon: "wifi", available: netMonitor.wifi.available)
                    statusCard(title: isFa ? "انترنت موبایل" : "Mobile Data", icon: "antenna.radiowaves.left.and.right", available: netMonitor.cellular.available)
                }
                .padding(.horizontal)

                if let err = tunnel.lastError {
                    Text(err).font(.caption).foregroundStyle(.red).padding(.horizontal)
                }

                Spacer()
            }
            .padding(.top, 24)
            .navigationTitle("NetFusion")
        }
    }

    private func statusCard(title: String, icon: String, available: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: icon).foregroundStyle(available ? .green : .gray)
                Text(title).font(.headline)
            }
            Text(available ? (isFa ? "متصل و آماده" : "Ready") : (isFa ? "در دسترس نیست" : "Unavailable"))
                .font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private var connectionsTab: some View {
        NavigationStack {
            List {
                Section(isFa ? "حالت اتصال" : "Connection Mode") {
                    Picker(isFa ? "حالت" : "Mode", selection: $modeRaw) {
                        Text(isFa ? "حالت هوشمند (Smart)" : "Smart Mode").tag(ConnectionMode.smart.rawValue)
                        Text(isFa ? "حالت ترکیب (Bonding VPN)" : "Bonding Mode").tag(ConnectionMode.bonding.rawValue)
                    }
                    .pickerStyle(.segmented)
                }
                Section(isFa ? "نکته فنی آیفون" : "iOS Note") {
                    Text(isFa
                         ? "در آیفون، ترکیب واقعی وای‌فای و 4G/5G از طریق NEPacketTunnelProvider به سرور لینوکسی NetFusion انجام می‌شود و نیازمند حساب Apple Developer دارای مجوز NetworkExtension است."
                         : "On iOS, simultaneous Wi-Fi + Cellular bonding runs inside NEPacketTunnelProvider toward your NetFusion Linux server and requires an Apple Developer account with the NetworkExtension entitlement.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle(isFa ? "اتصال‌ها" : "Connections")
        }
    }

    private var speedTestTab: some View {
        NavigationStack {
            VStack(spacing: 16) {
                HStack(spacing: 24) {
                    VStack {
                        Text(isFa ? "دانلود" : "Download").font(.caption).foregroundStyle(.secondary)
                        Text(String(format: "%.1f Mbps", speedTest.downloadMbps)).font(.title2.bold())
                    }
                    VStack {
                        Text(isFa ? "آپلود" : "Upload").font(.caption).foregroundStyle(.secondary)
                        Text(String(format: "%.1f Mbps", speedTest.uploadMbps)).font(.title2.bold())
                    }
                    VStack {
                        Text(isFa ? "پینگ" : "Ping").font(.caption).foregroundStyle(.secondary)
                        Text("\(speedTest.pingMs) ms").font(.title2.bold())
                    }
                }
                Button(speedTest.isRunning ? (isFa ? "در حال آزمایش…" : "Testing…") : (isFa ? "شروع تست سرعت" : "Start Speed Test")) {
                    Task { await speedTest.runTest() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(speedTest.isRunning)

                List(speedTest.history) { item in
                    HStack {
                        Text(item.date, style: .time)
                        Spacer()
                        Text(String(format: "↓ %.1f  ↑ %.1f Mbps", item.downloadMbps, item.uploadMbps))
                            .font(.subheadline.monospacedDigit())
                    }
                }
            }
            .padding(.top)
            .navigationTitle(isFa ? "تست سرعت" : "Speed Test")
        }
    }

    private var settingsTab: some View {
        NavigationStack {
            Form {
                Section(isFa ? "زبان و ظاهر" : "Language & Theme") {
                    Picker(isFa ? "زبان" : "Language", selection: $langRaw) {
                        ForEach(AppLanguage.allCases, id: \.rawValue) { lang in
                            Text(lang.displayName).tag(lang.rawValue)
                        }
                    }
                    Toggle(isFa ? "پوسته تاریک" : "Dark Theme", isOn: $isDark)
                }
                Section(isFa ? "سرور ترکیب NetFusion" : "NetFusion Bonding Server") {
                    TextField(isFa ? "آی‌پی یا دامنه سرور" : "Server Host / IP", text: $serverHost)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                    TextField(isFa ? "پورت UDP" : "UDP Port", value: $serverPort, format: .number)
                        .keyboardType(.numberPad)
                    SecureField(isFa ? "توکن امنیتی" : "Auth Token", text: $serverToken)
                    TextField("DNS", text: $customDns)
                }
            }
            .navigationTitle(isFa ? "تنظیمات" : "Settings")
        }
    }
}
