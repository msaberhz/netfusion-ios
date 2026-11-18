import Foundation

final class ReorderBuffer {
    private struct BufferedPacket {
        let seq: UInt32
        let payload: Data
        let arrivalMs: Int64
    }

    private var pending: [UInt32: BufferedPacket] = [:]
    private var nextExpectedSeq: UInt32 = 1
    private var initialized = false
    private let maxHoldbackMs: Int64
    private let maxWindow: Int
    private let lock = NSLock()

    private(set) var reorderedCount: Int = 0
    private(set) var droppedLateCount: Int = 0

    init(maxHoldbackMs: Int64 = 45, maxWindow: Int = 256) {
        self.maxHoldbackMs = maxHoldbackMs
        self.maxWindow = maxWindow
    }

    func push(seq: UInt32, payload: Data, nowMs: Int64 = Int64(Date().timeIntervalSince1970 * 1000)) -> [Data] {
        lock.lock()
        defer { lock.unlock() }

        if !initialized {
            nextExpectedSeq = seq
            initialized = true
        }

        var ready: [Data] = []
        if seq < nextExpectedSeq {
            droppedLateCount += 1
            return ready
        }

        if seq == nextExpectedSeq {
            ready.append(payload)
            nextExpectedSeq += 1
            drainInOrder(into: &ready)
            return ready
        }

        if pending[seq] == nil {
            pending[seq] = BufferedPacket(seq: seq, payload: payload, arrivalMs: nowMs)
            reorderedCount += 1
        }
        flushExpiredLocked(nowMs: nowMs, into: &ready)
        return ready
    }

    func flushExpired(nowMs: Int64 = Int64(Date().timeIntervalSince1970 * 1000)) -> [Data] {
        lock.lock()
        defer { lock.unlock() }
        var out: [Data] = []
        flushExpiredLocked(nowMs: nowMs, into: &out)
        return out
    }

    private func flushExpiredLocked(nowMs: Int64, into out: inout [Data]) {
        let sortedKeys = pending.keys.sorted()
        for key in sortedKeys {
            guard let item = pending[key] else { continue }
            let age = nowMs - item.arrivalMs
            if key <= nextExpectedSeq || age >= maxHoldbackMs || pending.count > maxWindow {
                pending.removeValue(forKey: key)
                out.append(item.payload)
                nextExpectedSeq = key + 1
                drainInOrder(into: &out)
            } else {
                break
            }
        }
    }

    private func drainInOrder(into out: inout [Data]) {
        while let next = pending.removeValue(forKey: nextExpectedSeq) {
            out.append(next.payload)
            nextExpectedSeq += 1
        }
    }

    func reset() {
        lock.lock()
        defer { lock.unlock() }
        pending.removeAll()
        nextExpectedSeq = 1
        initialized = false
    }
}
