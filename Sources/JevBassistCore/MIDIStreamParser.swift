import Foundation

public struct MIDIStreamParser<StreamID: Hashable & Sendable>: Sendable {
    private var parsers: [StreamID: MIDIByteParser] = [:]

    public init() {}

    public mutating func parse(
        _ bytes: [UInt8],
        streamID: StreamID,
        hostTime: UInt64,
        receivedAt: Date
    ) -> [MIDIEvent] {
        var parser = parsers[streamID] ?? MIDIByteParser()
        let events = parser.parse(
            bytes,
            hostTime: hostTime,
            receivedAt: receivedAt
        )
        parsers[streamID] = parser
        return events
    }

    public mutating func reset(streamID: StreamID) {
        parsers.removeValue(forKey: streamID)
    }
}
