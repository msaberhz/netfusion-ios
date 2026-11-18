import XCTest

final class NfmpCryptoTests: XCTestCase {
    func testAesGcmEncryptDecryptRoundTrip() {
        let crypto = PacketCrypto(sharedSecret: "test-ios-token")
        let hdr = NfmpHeader(
            type: NfmpProtocol.typeData,
            sessionId: 123456789,
            seqNum: 7,
            pathId: NfmpProtocol.pathWiFi,
            flags: NfmpProtocol.flagEncrypted,
            timestampMs: 5000
        )
        let payload = Data("NetFusion iOS Multipath".utf8)
        let encrypted = crypto.encryptDataPacket(header: hdr, plaintext: payload)
        XCTAssertNotNil(encrypted)

        let decHdr = NfmpHeader.decode(encrypted!)
        XCTAssertEqual(decHdr?.seqNum, 7)
        let decrypted = crypto.decryptDataPacket(raw: encrypted!, header: decHdr!)
        XCTAssertEqual(decrypted, payload)
    }

    func testReorderBufferReassemblesOutOfOrder() {
        let rb = ReorderBuffer(maxHoldbackMs: 100)
        XCTAssertEqual(rb.push(seq: 1, payload: Data([1]), nowMs: 100).count, 1)
        XCTAssertEqual(rb.push(seq: 3, payload: Data([3]), nowMs: 110).count, 0)
        let out = rb.push(seq: 2, payload: Data([2]), nowMs: 120)
        XCTAssertEqual(out, [Data([2]), Data([3])])
    }
}
