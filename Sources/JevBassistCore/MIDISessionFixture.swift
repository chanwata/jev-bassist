import Foundation

public struct SessionMIDIEvent: Codable, Equatable, Sendable {
    public let offsetMicroseconds: UInt64
    public let hostTime: UInt64
    public let channel: UInt8
    public let kind: MIDIEvent.Kind
    public let note: UInt8
    public let velocity: UInt8

    public init(
        offsetMicroseconds: UInt64,
        hostTime: UInt64,
        channel: UInt8,
        kind: MIDIEvent.Kind,
        note: UInt8,
        velocity: UInt8
    ) {
        self.offsetMicroseconds = offsetMicroseconds
        self.hostTime = hostTime
        self.channel = channel
        self.kind = kind
        self.note = note
        self.velocity = velocity
    }

    public func midiEvent(relativeTo startedAt: Date) -> MIDIEvent {
        MIDIEvent(
            receivedAt: startedAt.addingTimeInterval(Double(offsetMicroseconds) / 1_000_000),
            hostTime: hostTime,
            channel: channel,
            kind: kind,
            note: note,
            velocity: velocity
        )
    }
}

public struct MIDISessionFixture: Codable, Equatable, Sendable {
    public static let currentFormatVersion = 1

    public let formatVersion: Int
    public let startedAt: Date
    public let durationMicroseconds: UInt64
    public let sourceNames: [String]
    public let events: [SessionMIDIEvent]

    public init(
        formatVersion: Int = currentFormatVersion,
        startedAt: Date,
        durationMicroseconds: UInt64,
        sourceNames: [String],
        events: [SessionMIDIEvent]
    ) throws {
        self.formatVersion = formatVersion
        self.startedAt = startedAt
        self.durationMicroseconds = durationMicroseconds
        self.sourceNames = sourceNames
        self.events = events
        try validate()
    }

    public func replayedEvents() -> [MIDIEvent] {
        events.map { $0.midiEvent(relativeTo: startedAt) }
    }

    public func validate() throws {
        guard formatVersion == Self.currentFormatVersion else {
            throw MIDISessionFixtureError.unsupportedFormatVersion(formatVersion)
        }

        var previousOffset: UInt64 = 0
        for (index, event) in events.enumerated() {
            guard event.channel >= 1, event.channel <= 16 else {
                throw MIDISessionFixtureError.invalidChannel(index: index, value: event.channel)
            }
            guard event.note <= 127 else {
                throw MIDISessionFixtureError.invalidNote(index: index, value: event.note)
            }
            guard event.velocity <= 127 else {
                throw MIDISessionFixtureError.invalidVelocity(index: index, value: event.velocity)
            }
            if index > 0, event.offsetMicroseconds < previousOffset {
                throw MIDISessionFixtureError.nonMonotonicEvent(index: index)
            }
            guard event.offsetMicroseconds <= durationMicroseconds else {
                throw MIDISessionFixtureError.eventAfterSessionEnd(index: index)
            }
            previousOffset = event.offsetMicroseconds
        }
    }

    private enum CodingKeys: String, CodingKey {
        case formatVersion
        case startedAt
        case durationMicroseconds
        case sourceNames
        case events
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        do {
            try self.init(
                formatVersion: container.decode(Int.self, forKey: .formatVersion),
                startedAt: container.decode(Date.self, forKey: .startedAt),
                durationMicroseconds: container.decode(UInt64.self, forKey: .durationMicroseconds),
                sourceNames: container.decode([String].self, forKey: .sourceNames),
                events: container.decode([SessionMIDIEvent].self, forKey: .events)
            )
        } catch let error as MIDISessionFixtureError {
            throw DecodingError.dataCorrupted(
                .init(codingPath: decoder.codingPath, debugDescription: error.description)
            )
        }
    }
}

public enum MIDISessionFixtureError: Error, CustomStringConvertible, Equatable {
    case unsupportedFormatVersion(Int)
    case invalidChannel(index: Int, value: UInt8)
    case invalidNote(index: Int, value: UInt8)
    case invalidVelocity(index: Int, value: UInt8)
    case nonMonotonicEvent(index: Int)
    case eventAfterSessionEnd(index: Int)

    public var description: String {
        switch self {
        case let .unsupportedFormatVersion(version):
            return "Unsupported MIDI session fixture format version \(version)."
        case let .invalidChannel(index, value):
            return "Event \(index) has invalid MIDI channel \(value)."
        case let .invalidNote(index, value):
            return "Event \(index) has invalid MIDI note \(value)."
        case let .invalidVelocity(index, value):
            return "Event \(index) has invalid MIDI velocity \(value)."
        case let .nonMonotonicEvent(index):
            return "Event \(index) is earlier than the preceding event."
        case let .eventAfterSessionEnd(index):
            return "Event \(index) occurs after the session duration."
        }
    }
}

public enum MIDISessionFixtureCodec {
    public static func encode(_ fixture: MIDISessionFixture) throws -> Data {
        try fixture.validate()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(timestampFormatter.string(from: date))
        }
        return try encoder.encode(fixture)
    }

    public static func decode(_ data: Data) throws -> MIDISessionFixture {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)
            guard let date = timestampFormatter.date(from: value) else {
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "Invalid ISO 8601 timestamp '\(value)'."
                )
            }
            return date
        }
        return try decoder.decode(MIDISessionFixture.self, from: data)
    }

    public static func write(
        _ fixture: MIDISessionFixture,
        to url: URL
    ) throws {
        let data = try encode(fixture)
        try data.write(to: url, options: .withoutOverwriting)
    }

    private static var timestampFormatter: ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }
}

/// Collects events from the MIDI processing queue while allowing the control
/// thread to finish and serialize a consistent session snapshot.
public final class MIDISessionCapture: @unchecked Sendable {
    public let startedAt: Date

    private let lock = NSLock()
    private var recordedEvents: [SessionMIDIEvent] = []

    public init(startedAt: Date = Date()) {
        self.startedAt = startedAt
    }

    public func append(_ event: MIDIEvent) {
        lock.lock()
        defer { lock.unlock() }

        let measuredOffset = Self.microseconds(from: startedAt, to: event.receivedAt)
        let offset = max(recordedEvents.last?.offsetMicroseconds ?? 0, measuredOffset)
        recordedEvents.append(
            SessionMIDIEvent(
                offsetMicroseconds: offset,
                hostTime: event.hostTime,
                channel: event.channel,
                kind: event.kind,
                note: event.note,
                velocity: event.velocity
            )
        )
    }

    public func fixture(
        sourceNames: [String],
        endedAt: Date = Date()
    ) throws -> MIDISessionFixture {
        lock.lock()
        defer { lock.unlock() }

        let measuredDuration = Self.microseconds(from: startedAt, to: endedAt)
        let duration = max(recordedEvents.last?.offsetMicroseconds ?? 0, measuredDuration)
        return try MIDISessionFixture(
            startedAt: startedAt,
            durationMicroseconds: duration,
            sourceNames: sourceNames,
            events: recordedEvents
        )
    }

    private static func microseconds(from start: Date, to end: Date) -> UInt64 {
        let interval = max(0, end.timeIntervalSince(start))
        let microseconds = (interval * 1_000_000).rounded()
        guard microseconds < Double(UInt64.max) else {
            return UInt64.max
        }
        return UInt64(microseconds)
    }
}
