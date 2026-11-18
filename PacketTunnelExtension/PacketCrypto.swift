import Foundation
import CryptoKit

enum NfmpProtocol {
    static let magic0: UInt8 = 0x4E
    static let magic1: UInt8 = 0x46
    static let version: UInt8 = 0x01
    static let headerSize = 24

    static let typeHello: UInt8 = 1
    static let typeWelcome: UInt8 = 2
    static let typeData: UInt8 = 3
    static let typeProbe: UInt8 = 4
    static let typeProbeAck: UInt8 = 5
    static let typeClose: UInt8 = 6

    static let pathWiFi: UInt8 = 0
    static let pathCellular: UInt8 = 1

    static let flagEncrypted: UInt8 = 0x01
}

struct NfmpHeader {
    var type: UInt8
    var sessionId: UInt64
    var seqNum: UInt32
    var pathId: UInt8
    var flags: UInt8
    var timestampMs: UInt32

    func encode() -> Data {
        var data = Data(count: NfmpProtocol.headerSize)
        data[0] = NfmpProtocol.magic0
        data[1] = NfmpProtocol.magic1
        data[2] = NfmpProtocol.version
        data[3] = type
        withUnsafeBytes(of: sessionId.bigEndian) { data.replaceSubrange(4..<12, with: $0) }
        withUnsafeBytes(of: seqNum.bigEndian) { data.replaceSubrange(12..<16, with: $0) }
        data[16] = pathId
        data[17] = flags
        data[18] = 0
        data[19] = 0
        withUnsafeBytes(of: timestampMs.bigEndian) { data.replaceSubrange(20..<24, with: $0) }
        return data
    }

    static func decode(_ data: Data) -> NfmpHeader? {
        guard data.count >= NfmpProtocol.headerSize,
              data[0] == NfmpProtocol.magic0,
              data[1] == NfmpProtocol.magic1,
              data[2] == NfmpProtocol.version else { return nil }

        let sessionId = data.subdata(in: 4..<12).withUnsafeBytes { $0.load(as: UInt64.self).bigEndian }
        let seqNum = data.subdata(in: 12..<16).withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
        let ts = data.subdata(in: 20..<24).withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }

        return NfmpHeader(
            type: data[3],
            sessionId: sessionId,
            seqNum: seqNum,
            pathId: data[16],
            flags: data[17],
            timestampMs: ts
        )
    }
}

final class PacketCrypto {
    private let aesKey: SymmetricKey
    private let hmacKey: SymmetricKey

    init(sharedSecret: String) {
        let secret = sharedSecret.isEmpty ? "netfusion-default-key" : sharedSecret
        let keyHash = SHA256.hash(data: Data(secret.utf8))
        self.aesKey = SymmetricKey(data: Data(keyHash))
        let macHash = SHA256.hash(data: Data(("nfmp-auth:" + secret).utf8))
        self.hmacKey = SymmetricKey(data: Data(macHash))
    }

    func computeAuthTag(sessionId: UInt64, timestampMs: UInt32) -> Data {
        var msg = Data(count: 12)
        withUnsafeBytes(of: sessionId.bigEndian) { msg.replaceSubrange(0..<8, with: $0) }
        withUnsafeBytes(of: timestampMs.bigEndian) { msg.replaceSubrange(8..<12, with: $0) }
        let mac = HMAC<SHA256>.authenticationCode(for: msg, using: hmacKey)
        return Data(mac)
    }

    private func buildNonce(pathId: UInt8, sessionId: UInt64, seqNum: UInt32) -> AES.GCM.Nonce {
        var bytes = Data(count: 12)
        bytes[0] = pathId
        let sessLow = UInt32(truncatingIfNeeded: sessionId).bigEndian
        withUnsafeBytes(of: sessLow) { bytes.replaceSubrange(4..<8, with: $0) }
        withUnsafeBytes(of: seqNum.bigEndian) { bytes.replaceSubrange(8..<12, with: $0) }
        return try! AES.GCM.Nonce(data: bytes)
    }

    func encryptDataPacket(header: NfmpHeader, plaintext: Data) -> Data? {
        let headerData = header.encode()
        let nonce = buildNonce(pathId: header.pathId, sessionId: header.sessionId, seqNum: header.seqNum)
        guard let sealed = try? AES.GCM.seal(plaintext, using: aesKey, nonce: nonce, authenticating: headerData) else {
            return nil
        }
        var out = Data()
        out.append(headerData)
        out.append(sealed.ciphertext)
        out.append(sealed.tag)
        return out
    }

    func decryptDataPacket(raw: Data, header: NfmpHeader) -> Data? {
        guard raw.count > NfmpProtocol.headerSize + 16 else { return nil }
        let headerData = raw.prefix(NfmpProtocol.headerSize)
        let cipherAndTag = raw.dropFirst(NfmpProtocol.headerSize)
        let ciphertext = cipherAndTag.dropLast(16)
        let tag = cipherAndTag.suffix(16)
        let nonce = buildNonce(pathId: header.pathId, sessionId: header.sessionId, seqNum: header.seqNum)
        guard let box = try? AES.GCM.SealedBox(nonce: nonce, ciphertext: ciphertext, tag: tag) else {
            return nil
        }
        return try? AES.GCM.open(box, using: aesKey, authenticating: headerData)
    }
}
