import Foundation

public enum GrooveStyle: String, Codable, CaseIterable, Equatable, Sendable {
    case off
    case riot
}

public struct GrooveTiming: Codable, Equatable, Sendable {
    public let swing: Double
    public let strength: Double

    public init(swing: Double = 0.58, strength: Double = 0.72) {
        self.swing = min(0.68, max(0.5, swing.isFinite ? swing : 0.58))
        self.strength = min(1, max(0, strength.isFinite ? strength : 0.72))
    }

    public func alignedBeat(_ beat: Double) -> Double {
        guard beat.isFinite, beat >= 0 else { return 0 }
        let quarter = floor(beat)
        let candidates = [
            max(0, quarter - 1 + swing), quarter,
            quarter + swing, quarter + 1
        ]
        let target = candidates.min { abs($0 - beat) < abs($1 - beat) } ?? beat
        return beat + (target - beat) * strength
    }

    public func nextOpportunity(after beat: Double, minimumLeadBeats: Double) -> Double {
        let threshold = beat + max(0, minimumLeadBeats)
        let quarter = floor(threshold)
        for candidate in [quarter, quarter + swing, quarter + 1] where candidate >= threshold {
            return candidate
        }
        return quarter + 1
    }

    /// A finer, still swung grid for conversational entrances. The rhythm box
    /// keeps its sparse eighth-note skeleton, while a reply may enter between
    /// those attacks instead of waiting an entire long or short subdivision.
    public func nextConversationOpportunity(
        after beat: Double,
        minimumLeadBeats: Double
    ) -> Double {
        let threshold = beat + max(0, minimumLeadBeats)
        let quarter = floor(threshold)
        let candidates = [
            quarter,
            quarter + swing * 0.5,
            quarter + swing,
            quarter + (1 + swing) * 0.5,
            quarter + 1
        ]
        return candidates.first(where: { $0 >= threshold }) ?? quarter + 1
    }
}

public struct RiotGroovePlan: Equatable, Sendable {
    public let barIndex: Int
    public let drumMessages: [ScheduledMIDIMessage]
    public let textureMessages: [ScheduledMIDIMessage]

    public var messages: [ScheduledMIDIMessage] {
        (drumMessages + textureMessages).sorted(by: Self.messageOrder)
    }

    public init(
        barIndex: Int,
        drumMessages: [ScheduledMIDIMessage],
        textureMessages: [ScheduledMIDIMessage]
    ) {
        self.barIndex = barIndex
        self.drumMessages = drumMessages
        self.textureMessages = textureMessages
    }

    private static func messageOrder(
        _ left: ScheduledMIDIMessage,
        _ right: ScheduledMIDIMessage
    ) -> Bool {
        if left.offsetMicroseconds != right.offsetMicroseconds {
            return left.offsetMicroseconds < right.offsetMicroseconds
        }
        if left.kind != right.kind {
            return left.kind == .noteOff
        }
        if left.channel != right.channel { return left.channel < right.channel }
        return left.note < right.note
    }
}

/// A deliberately small, deterministic rhythm-box ensemble. It supplies a
/// shared pulse; it does not ask Jev to invent percussion or harmony.
public struct RiotGrooveGenerator: Sendable {
    public let musicalState: MusicalStateConfiguration
    public let drumChannel: UInt8
    public let textureChannel: UInt8

    public init(
        musicalState: MusicalStateConfiguration,
        drumChannel: UInt8 = 10,
        textureChannel: UInt8 = 2
    ) {
        self.musicalState = musicalState
        self.drumChannel = drumChannel
        self.textureChannel = textureChannel
    }

    public func plan(
        barIndex: Int,
        humanDensity: Double,
        tonalCenterPitchClass: UInt8?,
        mode: MusicalMode?,
        swing: Double = 0.58,
        intensity: Double = 0.65
    ) -> RiotGroovePlan {
        let timing = GrooveTiming(swing: swing, strength: 1)
        let level = min(1, max(0, intensity.isFinite ? intensity : 0.65))
        let density = min(4, max(0, humanDensity.isFinite ? humanDensity : 0))
        guard level > 0.01 else {
            return RiotGroovePlan(
                barIndex: barIndex,
                drumMessages: [],
                textureMessages: []
            )
        }
        let barStartBeat = Double(max(0, barIndex) * musicalState.beatsPerBar)
        var drums: [ScheduledMIDIMessage] = []

        for beat in 0..<musicalState.beatsPerBar {
            let beatPosition = barStartBeat + Double(beat)
            appendHit(note: 42, velocity: velocity(38, level, humanDensity: density), beat: beatPosition, to: &drums)
            if level > 0.24, density < 2.7 {
                appendHit(
                    note: 42,
                    velocity: velocity(29, level, humanDensity: density),
                    beat: barStartBeat + Double(beat) + timing.swing,
                    to: &drums
                )
            }
        }

        appendHit(note: 36, velocity: velocity(76, level, humanDensity: density), beat: barStartBeat, to: &drums)
        if musicalState.beatsPerBar >= 3 {
            let kickBeat = barStartBeat + (barIndex.isMultiple(of: 2) ? 2.0 : 2.0 + timing.swing)
            appendHit(note: 36, velocity: velocity(58, level, humanDensity: density), beat: kickBeat, to: &drums)
        }
        for beat in stride(from: 1, to: musicalState.beatsPerBar, by: 2) {
            appendHit(
                note: 37,
                velocity: velocity(63, level, humanDensity: density),
                beat: barStartBeat + Double(beat),
                to: &drums
            )
        }
        if level > 0.62, density < 1.45, musicalState.beatsPerBar >= 4 {
            appendHit(
                note: barIndex.isMultiple(of: 2) ? 64 : 63,
                velocity: velocity(43, level, humanDensity: density),
                beat: barStartBeat + 3 + timing.swing,
                to: &drums
            )
        }

        let texture = textureMessages(
            barStartBeat: barStartBeat,
            barIndex: barIndex,
            tonalCenterPitchClass: tonalCenterPitchClass,
            mode: mode,
            humanDensity: density,
            timing: timing,
            intensity: level
        )
        return RiotGroovePlan(
            barIndex: barIndex,
            drumMessages: drums.sorted(by: messageOrder),
            textureMessages: texture.sorted(by: messageOrder)
        )
    }

    private func textureMessages(
        barStartBeat: Double,
        barIndex: Int,
        tonalCenterPitchClass: UInt8?,
        mode: MusicalMode?,
        humanDensity: Double,
        timing: GrooveTiming,
        intensity: Double
    ) -> [ScheduledMIDIMessage] {
        guard let tonalCenterPitchClass, let mode,
              intensity >= 0.3, humanDensity < 2.3 else { return [] }
        let degrees = mode.intervals
        let anchorDegrees = [0, 4, 6, 4]
        let degree = degrees[anchorDegrees[barIndex % anchorDegrees.count]]
        let pitchClass = (Int(tonalCenterPitchClass) + degree) % 12
        let pitch = UInt8(nearestPitch(to: pitchClass, in: 55...72))
        let firstBeat = barStartBeat + timing.swing
        var result: [ScheduledMIDIMessage] = []
        appendNote(
            note: pitch,
            velocity: UInt8(42 + Int(intensity * 24)),
            beat: firstBeat,
            durationBeats: 0.18,
            channel: textureChannel,
            to: &result
        )
        if intensity > 0.72, humanDensity < 1.1, musicalState.beatsPerBar >= 4 {
            let responseDegrees = [4, 2, 4, 0]
            let nextDegree = degrees[responseDegrees[barIndex % responseDegrees.count]]
            let nextClass = (Int(tonalCenterPitchClass) + nextDegree) % 12
            let nextPitch = UInt8(nearestPitch(to: nextClass, in: 55...72))
            appendNote(
                note: nextPitch,
                velocity: UInt8(36 + Int(intensity * 22)),
                beat: barStartBeat + 2 + timing.swing,
                durationBeats: 0.14,
                channel: textureChannel,
                to: &result
            )
        }
        return result
    }

    private func velocity(_ base: Int, _ intensity: Double, humanDensity: Double) -> UInt8 {
        let room = 1 - min(0.42, humanDensity * 0.12)
        return UInt8(max(12, min(104, (Double(base) * (0.55 + intensity * 0.65) * room).rounded())))
    }

    private func nearestPitch(to pitchClass: Int, in range: ClosedRange<Int>) -> Int {
        range.min { left, right in
            let leftDistance = min(
                (left % 12 - pitchClass + 12) % 12,
                (pitchClass - left % 12 + 12) % 12
            )
            let rightDistance = min(
                (right % 12 - pitchClass + 12) % 12,
                (pitchClass - right % 12 + 12) % 12
            )
            if leftDistance != rightDistance { return leftDistance < rightDistance }
            return abs(left - 63) < abs(right - 63)
        } ?? range.lowerBound
    }

    private func appendHit(
        note: UInt8,
        velocity: UInt8,
        beat: Double,
        to messages: inout [ScheduledMIDIMessage]
    ) {
        appendNote(
            note: note,
            velocity: velocity,
            beat: beat,
            durationBeats: 0.055,
            channel: drumChannel,
            to: &messages
        )
    }

    private func appendNote(
        note: UInt8,
        velocity: UInt8,
        beat: Double,
        durationBeats: Double,
        channel: UInt8,
        to messages: inout [ScheduledMIDIMessage]
    ) {
        let beatMicroseconds = 60_000_000 / musicalState.tempoBPM
        let onset = UInt64(max(0, beat * beatMicroseconds).rounded())
        let release = onset + UInt64(max(1, durationBeats * beatMicroseconds).rounded())
        messages.append(ScheduledMIDIMessage(offsetMicroseconds: onset, kind: .noteOn, channel: channel, note: note, velocity: velocity))
        messages.append(ScheduledMIDIMessage(offsetMicroseconds: release, kind: .noteOff, channel: channel, note: note, velocity: 0))
    }

    private func messageOrder(_ left: ScheduledMIDIMessage, _ right: ScheduledMIDIMessage) -> Bool {
        if left.offsetMicroseconds != right.offsetMicroseconds {
            return left.offsetMicroseconds < right.offsetMicroseconds
        }
        return left.kind == .noteOff && right.kind == .noteOn
    }
}
