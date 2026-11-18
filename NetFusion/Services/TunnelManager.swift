import Foundation
import NetworkExtension

@MainActor
final class TunnelManager: ObservableObject {
    @Published var status: TunnelStatus = .disconnected
    @Published var lastError: String?

    func connect(host: String, port: Int, token: String, dns: String) async {
        lastError = "Free Sideload Build: NetworkExtension VPN requires a paid Apple Developer ($99/yr) entitlement. Speed Test, Wi-Fi/Cellular monitoring, and UI are active."
        status = .error
    }

    func disconnect() {
        lastError = nil
        status = .disconnected
    }
}
