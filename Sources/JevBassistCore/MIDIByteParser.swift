import Foundation

public struct MIDIByteParser: Sendable {
    private var runningStatus: UInt8?
    private var pendingData: [UInt8] = []
    private var isInsideSysEx = false

    public init() {}

    public mutating func parse(
        _ bytes: [UInt8],
        hostTime: UInt64,
        receivedAt: Date
    ) -> [MIDIEvent] {
        var events: [MIDIEvent] = []

        for byte in bytes {
            if byte >= 0xF8 {
                continue
            }

            if isInsideSysEx {
                if byte == 0xF7 {
                    isInsideSysEx = false
                }
                continue
            }

            if byte == 0xF0 {
                runningStatus = nil
                pendingData.removeAll(keepingCapacity: true)
                isInsideSysEx = true
                continue
            }

            if byte >= 0xF0 {
                runningStatus = nil
                pendingData.removeAll(keepingCapacity: true)
                continue
            }

            if byte & 0x80 != 0 {
                runningStatus = byte
                pendingData.removeAll(keepingCapacity: true)
                continue
            }

            guard let status = runningStatus else {
                continue
            }

            pendingData.append(byte)
            let expectedCount = dataByteCount(for: status)

            guard pendingData.count == expectedCount else {
                continue
            }

            if let event = makeEvent(
                status: status,
                data: pendingData,
                hostTime: hostTime,
                receivedAt: receivedAt
            ) {
                events.append(event)
            }

            pendingData.removeAll(keepingCapacity: true)
        }

        return events
    }

    private func dataByteCount(for status: UInt8) -> Int {
        switch status & 0xF0 {
        case 0xC0, 0xD0:
            return 1
        default:
            return 2
        }
    }

    private func makeEvent(
        status: UInt8,
        data: [UInt8],
        hostTime: UInt64,
        receivedAt: Date
    ) -> MIDIEvent? {
        guard data.count == 2 else {
            return nil
        }

        let channel = (status & 0x0F) + 1
        let message = status & 0xF0
        let note = data[0]
        let velocity = data[1]

        switch message {
        case 0x80:
            return MIDIEvent(
                receivedAt: receivedAt,
                hostTime: hostTime,
                channel: channel,
                kind: .noteOff,
                note: note,
                velocity: velocity
            )
        case 0x90:
            return MIDIEvent(
                receivedAt: receivedAt,
                hostTime: hostTime,
                channel: channel,
                kind: velocity == 0 ? .noteOff : .noteOn,
                note: note,
                velocity: velocity
            )
        default:
            return nil
        }
    }
}
