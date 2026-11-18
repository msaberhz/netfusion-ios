import Foundation
import Network
import NetworkExtension

final class PacketTunnelProvider: NEPacketTunnelProvider {
    private var wifiConn: NWConnection?
    private var cellConn: NWConnection?
    private var crypto: PacketCrypto?
    private let reorderBuffer = ReorderBuffer()
    private var sessionId: UInt64 = UInt64.random(in: 1...UInt64.max)
    private var txSeq: UInt32 = 1
    private var toggle: UInt32 = 0
    private var isRunning = false
    private let queue = DispatchQueue(label: "com.netfusion.tunnel.queue")
    private var flushTimer: DispatchSourceTimer?

    override func startTunnel(options: [String: NSObject]?, completionHandler: @escaping (Error?) -> Void) {
        let cfg = (protocolConfiguration as? NETunnelProviderProtocol)?.providerConfiguration ?? [:]
        let host = (cfg["host"] as? String) ?? ""
        let port = UInt16((cfg["port"] as? Int) ?? 51880)
        let token = (cfg["token"] as? String) ?? ""
        let dns = (cfg["dns"] as? String) ?? "1.1.1.1"

        guard !host.isEmpty, let nwPort = NWEndpoint.Port(rawValue: port) else {
            completionHandler(NSError(domain: "NetFusion", code: -1, userInfo: [NSLocalizedDescriptionKey: "Bonding server host is not configured."]))
            return
        }

        self.crypto = PacketCrypto(sharedSecret: token)

        let settings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: host)
        let ipv4 = NEIPv4Settings(addresses: ["10.88.0.2"], subnetMasks: ["255.255.255.0"])
        ipv4.includedRoutes = [NEIPv4Route.default()]
        settings.ipv4Settings = ipv4
        settings.dnsSettings = NEDNSSettings(servers: [dns])
        settings.mtu = 1360

        setTunnelNetworkSettings(settings) { [weak self] error in
            guard let self else { return }
            if let error {
                completionHandler(error)
                return
            }
            self.isRunning = true
            self.setupPathConnections(host: host, port: nwPort)
            self.startFlushTimer()
            self.readFromTun()
            completionHandler(nil)
        }
    }

    private func setupPathConnections(host: String, port: NWEndpoint.Port) {
        let endpoint = NWEndpoint.hostPort(host: NWEndpoint.Host(host), port: port)

        // Wi-Fi bound UDP connection
        let wifiParams = NWParameters.udp
        wifiParams.requiredInterfaceType = .wifi
        let wConn = NWConnection(to: endpoint, using: wifiParams)
        wConn.stateUpdateHandler = { [weak self] state in
            if case .ready = state {
                self?.sendHello(over: wConn, pathId: NfmpProtocol.pathWiFi)
                self?.receiveLoop(on: wConn)
            }
        }
        wConn.start(queue: queue)
        self.wifiConn = wConn

        // Cellular bound UDP connection
        let cellParams = NWParameters.udp
        cellParams.requiredInterfaceType = .cellular
        let cConn = NWConnection(to: endpoint, using: cellParams)
        cConn.stateUpdateHandler = { [weak self] state in
            if case .ready = state {
                self?.sendHello(over: cConn, pathId: NfmpProtocol.pathCellular)
                self?.receiveLoop(on: cConn)
            }
        }
        cConn.start(queue: queue)
        self.cellConn = cConn
    }

    private func sendHello(over conn: NWConnection, pathId: UInt8) {
        guard let crypto else { return }
        let ts = UInt32(truncatingIfNeeded: Int64(Date().timeIntervalSince1970 * 1000))
        let hdr = NfmpHeader(type: NfmpProtocol.typeHello, sessionId: sessionId, seqNum: 0, pathId: pathId, flags: 0, timestampMs: ts)
        var pkt = hdr.encode()
        pkt.append(crypto.computeAuthTag(sessionId: sessionId, timestampMs: ts))
        conn.send(content: pkt, completion: .contentProcessed({ _ in }))
    }

    private func readFromTun() {
        packetFlow.readPackets { [weak self] packets, protocols in
            guard let self, self.isRunning else { return }
            self.queue.async {
                for pkt in packets {
                    self.sendIpPacket(pkt)
                }
                self.readFromTun()
            }
        }
    }

    private func sendIpPacket(_ ipPacket: Data) {
        guard let crypto else { return }
        let wReady = wifiConn?.state == .ready
        let cReady = cellConn?.state == .ready

        let selected: (NWConnection, UInt8)?
        if wReady && cReady {
            toggle &+= 1
            selected = (toggle % 2 == 0) ? (wifiConn!, NfmpProtocol.pathWiFi) : (cellConn!, NfmpProtocol.pathCellular)
        } else if wReady {
            selected = (wifiConn!, NfmpProtocol.pathWiFi)
        } else if cReady {
            selected = (cellConn!, NfmpProtocol.pathCellular)
        } else {
            selected = nil
        }

        guard let (conn, pathId) = selected else { return }
        let seq = txSeq
        txSeq &+= 1
        let ts = UInt32(truncatingIfNeeded: Int64(Date().timeIntervalSince1970 * 1000))
        let hdr = NfmpHeader(type: NfmpProtocol.typeData, sessionId: sessionId, seqNum: seq, pathId: pathId, flags: NfmpProtocol.flagEncrypted, timestampMs: ts)
        if let encrypted = crypto.encryptDataPacket(header: hdr, plaintext: ipPacket) {
            conn.send(content: encrypted, completion: .contentProcessed({ _ in }))
        }
    }

    private func receiveLoop(on conn: NWConnection) {
        conn.receiveMessage { [weak self] content, _, _, error in
            guard let self, self.isRunning else { return }
            if let data = content, let hdr = NfmpHeader.decode(data), hdr.sessionId == self.sessionId {
                if hdr.type == NfmpProtocol.typeData, let plain = self.crypto?.decryptDataPacket(raw: data, header: hdr) {
                    let ordered = self.reorderBuffer.push(seq: hdr.seqNum, payload: plain)
                    if !ordered.isEmpty {
                        let protos = Array(repeating: NSNumber(value: AF_INET), count: ordered.count)
                        self.packetFlow.writePackets(ordered, withProtocols: protos)
                    }
                }
            }
            if error == nil {
                self.receiveLoop(on: conn)
            }
        }
    }

    private func startFlushTimer() {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + .milliseconds(25), repeating: .milliseconds(25))
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            let flushed = self.reorderBuffer.flushExpired()
            if !flushed.isEmpty {
                let protos = Array(repeating: NSNumber(value: AF_INET), count: flushed.count)
                self.packetFlow.writePackets(flushed, withProtocols: protos)
            }
        }
        timer.resume()
        self.flushTimer = timer
    }

    override func stopTunnel(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) {
        isRunning = false
        flushTimer?.cancel()
        wifiConn?.cancel()
        cellConn?.cancel()
        reorderBuffer.reset()
        completionHandler()
    }
}
