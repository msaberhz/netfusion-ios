import Foundation

@MainActor
final class SpeedTestService: ObservableObject {
    @Published var isRunning = false
    @Published var downloadMbps: Double = 0
    @Published var uploadMbps: Double = 0
    @Published var pingMs: Int = 0
    @Published var history: [SpeedTestEntry] = []

    func runTest() async {
        guard !isRunning else { return }
        isRunning = true
        defer { isRunning = false }

        // 1. Ping
        let pingStart = Date()
        if let url = URL(string: "https://speed.cloudflare.com/__down?bytes=1024") {
            _ = try? await URLSession.shared.data(from: url)
            pingMs = max(1, Int(Date().timeIntervalSince(pingStart) * 1000))
        }

        // 2. Download 5 MB
        let dlStart = Date()
        if let url = URL(string: "https://speed.cloudflare.com/__down?bytes=5000000"),
           let (data, _) = try? await URLSession.shared.data(from: url) {
            let elapsed = max(0.05, Date().timeIntervalSince(dlStart))
            downloadMbps = (Double(data.count) * 8.0) / (elapsed * 1_000_000.0)
        }

        // 3. Upload 2 MB
        let ulStart = Date()
        if let url = URL(string: "https://speed.cloudflare.com/__up") {
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            let payload = Data(repeating: 0x4E, count: 2_000_000)
            if let _ = try? await URLSession.shared.upload(for: req, from: payload) {
                let elapsed = max(0.05, Date().timeIntervalSince(ulStart))
                uploadMbps = (Double(payload.count) * 8.0) / (elapsed * 1_000_000.0)
            }
        }

        history.insert(SpeedTestEntry(date: Date(), downloadMbps: downloadMbps, uploadMbps: uploadMbps, pingMs: pingMs), at: 0)
    }
}
