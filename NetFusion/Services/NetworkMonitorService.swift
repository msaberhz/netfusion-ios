import Foundation
import Network

@MainActor
final class NetworkMonitorService: ObservableObject {
    @Published var wifi = InterfaceHealth()
    @Published var cellular = InterfaceHealth()

    private let wifiMonitor = NWPathMonitor(requiredInterfaceType: .wifi)
    private let cellMonitor = NWPathMonitor(requiredInterfaceType: .cellular)
    private let queue = DispatchQueue(label: "com.netfusion.ios.netmon")

    func start() {
        wifiMonitor.pathUpdateHandler = { [weak self] path in
            let avail = path.status == .satisfied
            Task { @MainActor in
                self?.wifi.available = avail
                self?.wifi.stabilityScore = avail ? 85 : 0
            }
        }
        cellMonitor.pathUpdateHandler = { [weak self] path in
            let avail = path.status == .satisfied
            Task { @MainActor in
                self?.cellular.available = avail
                self?.cellular.stabilityScore = avail ? 75 : 0
            }
        }
        wifiMonitor.start(queue: queue)
        cellMonitor.start(queue: queue)
    }

    func stop() {
        wifiMonitor.cancel()
        cellMonitor.cancel()
    }
}
