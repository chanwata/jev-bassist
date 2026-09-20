import Foundation

public struct MIDIEvent: Equatable, Sendable {
    public enum Kind: String, Codable, Equatable, Sendable {
        case noteOn
        case noteOff
    }

    public let receivedAt: Date
    public let hostTime: UInt64
    public let channel: UInt8
    public let kind: Kind
    public let note: UInt8
    public let velocity: UInt8

    public init(
        receivedAt: Date,
        hostTime: UInt64,
        channel: UInt8,
        kind: Kind,
        note: UInt8,
        velocity: UInt8
    ) {
        self.receivedAt = receivedAt
        self.hostTime = hostTime
        self.channel = channel
        self.kind = kind
        self.note = note
        self.velocity = velocity
    }
}

public enum MIDINoteName {
    private static let pitchClasses = [
        "C", "C#", "D", "D#", "E", "F",
        "F#", "G", "G#", "A", "A#", "B"
    ]

    public static func name(for note: UInt8) -> String {
        let value = Int(note)
        return "\(pitchClasses[value % 12])\(value / 12 - 1)"
    }
}
