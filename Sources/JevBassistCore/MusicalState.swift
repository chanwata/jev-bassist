import Foundation

public struct MusicalStateConfiguration: Codable, Equatable, Sendable {
    public let tempoBPM: Double
    public let beatsPerBar: Int

    public init(tempoBPM: Double = 120, beatsPerBar: Int = 4) throws {
        guard tempoBPM.isFinite, (20...400).contains(tempoBPM) else {
            throw MusicalStateError.invalidTempo(tempoBPM)
        }
        guard (1...16).contains(beatsPerBar) else {
            throw MusicalStateError.invalidBeatsPerBar(beatsPerBar)
        }
        self.tempoBPM = tempoBPM
        self.beatsPerBar = beatsPerBar
    }

    func boundaryMicroseconds(afterBeats beatCount: Int) -> UInt64 {
        UInt64((Double(beatCount) * 60_000_000 / tempoBPM).rounded())
    }
}

public enum MusicalStateError: Error, CustomStringConvertible, Equatable {
    case invalidTempo(Double)
    case invalidBeatsPerBar(Int)
    case nonMonotonicEvent(offsetMicroseconds: UInt64)
    case eventAfterFinish

    public var description: String {
        switch self {
        case let .invalidTempo(tempo):
            return "Tempo must be between 20 and 400 BPM; received \(tempo)."
        case let .invalidBeatsPerBar(beats):
            return "Beats per bar must be between 1 and 16; received \(beats)."
        case let .nonMonotonicEvent(offset):
            return "MIDI event at \(offset) microseconds is earlier than the preceding event."
        case .eventAfterFinish:
            return "Cannot ingest events after the musical-state tracker has finished."
        }
    }
}

public enum MusicalStateBoundary: String, Codable, Equatable, Sendable {
    case beat
    case bar
}

public struct HeldNote: Codable, Equatable, Sendable {
    public let channel: UInt8
    public let note: UInt8
    public let velocity: UInt8
    public let startedAtMicroseconds: UInt64

    public init(
        channel: UInt8,
        note: UInt8,
        velocity: UInt8,
        startedAtMicroseconds: UInt64
    ) {
        self.channel = channel
        self.note = note
        self.velocity = velocity
        self.startedAtMicroseconds = startedAtMicroseconds
    }
}

public struct PulseEstimate: Codable, Equatable, Sendable {
    public let bpm: Double
    public let confidence: Double

    public init(bpm: Double, confidence: Double) {
        self.bpm = bpm
        self.confidence = confidence
    }
}

public enum ChordQuality: String, Codable, CaseIterable, Sendable {
    case major
    case minor
    case diminished

    fileprivate var intervals: [Int] {
        switch self {
        case .major:
            return [0, 4, 7]
        case .minor:
            return [0, 3, 7]
        case .diminished:
            return [0, 3, 6]
        }
    }
}

public struct ChordCandidate: Codable, Equatable, Sendable {
    public let rootPitchClass: UInt8
    public let quality: ChordQuality
    public let confidence: Double

    public init(rootPitchClass: UInt8, quality: ChordQuality, confidence: Double) {
        self.rootPitchClass = rootPitchClass
        self.quality = quality
        self.confidence = confidence
    }

    public var rootName: String {
        Self.pitchClassNames[Int(rootPitchClass % 12)]
    }

    public var displayName: String {
        "\(rootName) \(quality.rawValue)"
    }

    private static let pitchClassNames = [
        "C", "C#", "D", "D#", "E", "F",
        "F#", "G", "G#", "A", "A#", "B"
    ]
}

public struct MusicalState: Codable, Equatable, Sendable {
    public let noteOnCount: Int
    public let noteDensityPerBeat: Double
    public let averageVelocity: Double?
    public let averageNote: Double?
    public let lowestNote: UInt8?
    public let highestNote: UInt8?
    public let heldNotes: [HeldNote]
    public let pulse: PulseEstimate?
    public let chordCandidates: [ChordCandidate]

    public init(
        noteOnCount: Int,
        noteDensityPerBeat: Double,
        averageVelocity: Double?,
        averageNote: Double?,
        lowestNote: UInt8?,
        highestNote: UInt8?,
        heldNotes: [HeldNote],
        pulse: PulseEstimate?,
        chordCandidates: [ChordCandidate]
    ) {
        self.noteOnCount = noteOnCount
        self.noteDensityPerBeat = noteDensityPerBeat
        self.averageVelocity = averageVelocity
        self.averageNote = averageNote
        self.lowestNote = lowestNote
        self.highestNote = highestNote
        self.heldNotes = heldNotes
        self.pulse = pulse
        self.chordCandidates = chordCandidates
    }
}

public struct MusicalStateSnapshot: Codable, Equatable, Sendable {
    public let boundary: MusicalStateBoundary
    public let index: Int
    public let barIndex: Int
    public let beatInBar: Int?
    public let startMicroseconds: UInt64
    public let endMicroseconds: UInt64
    public let state: MusicalState

    public init(
        boundary: MusicalStateBoundary,
        index: Int,
        barIndex: Int,
        beatInBar: Int?,
        startMicroseconds: UInt64,
        endMicroseconds: UInt64,
        state: MusicalState
    ) {
        self.boundary = boundary
        self.index = index
        self.barIndex = barIndex
        self.beatInBar = beatInBar
        self.startMicroseconds = startMicroseconds
        self.endMicroseconds = endMicroseconds
        self.state = state
    }
}

public struct MusicalStateTracker: Sendable {
    public let configuration: MusicalStateConfiguration

    private var nextBeatNumber = 1
    private var beatOnsets: [NoteObservation] = []
    private var barOnsets: [NoteObservation] = []
    private var pulseOnsets: [UInt64] = []
    private var heldNotes: [NoteKey: HeldNote] = [:]
    private var lastEventOffset: UInt64?
    private var isFinished = false

    public init(configuration: MusicalStateConfiguration) {
        self.configuration = configuration
    }

    public mutating func ingest(
        _ event: SessionMIDIEvent
    ) throws -> [MusicalStateSnapshot] {
        guard !isFinished else {
            throw MusicalStateError.eventAfterFinish
        }
        if let lastEventOffset, event.offsetMicroseconds < lastEventOffset {
            throw MusicalStateError.nonMonotonicEvent(
                offsetMicroseconds: event.offsetMicroseconds
            )
        }

        let snapshots = advanceBoundaries(through: event.offsetMicroseconds)
        let key = NoteKey(channel: event.channel, note: event.note)

        switch event.kind {
        case .noteOn:
            let observation = NoteObservation(
                offsetMicroseconds: event.offsetMicroseconds,
                channel: event.channel,
                note: event.note,
                velocity: event.velocity
            )
            beatOnsets.append(observation)
            barOnsets.append(observation)
            pulseOnsets.append(event.offsetMicroseconds)
            heldNotes[key] = HeldNote(
                channel: event.channel,
                note: event.note,
                velocity: event.velocity,
                startedAtMicroseconds: event.offsetMicroseconds
            )
        case .noteOff:
            heldNotes.removeValue(forKey: key)
        }

        lastEventOffset = event.offsetMicroseconds
        return snapshots
    }

    public mutating func finish(
        through offsetMicroseconds: UInt64
    ) throws -> [MusicalStateSnapshot] {
        guard !isFinished else {
            return []
        }
        if let lastEventOffset, offsetMicroseconds < lastEventOffset {
            throw MusicalStateError.nonMonotonicEvent(
                offsetMicroseconds: offsetMicroseconds
            )
        }
        isFinished = true
        return advanceBoundaries(through: offsetMicroseconds)
    }

    private mutating func advanceBoundaries(
        through offsetMicroseconds: UInt64
    ) -> [MusicalStateSnapshot] {
        var snapshots: [MusicalStateSnapshot] = []

        while configuration.boundaryMicroseconds(afterBeats: nextBeatNumber) <= offsetMicroseconds {
            let beatIndex = nextBeatNumber - 1
            let beatStart = configuration.boundaryMicroseconds(afterBeats: beatIndex)
            let beatEnd = configuration.boundaryMicroseconds(afterBeats: nextBeatNumber)
            prunePulseOnsets(at: beatEnd)
            let pulse = estimatePulse()

            snapshots.append(
                MusicalStateSnapshot(
                    boundary: .beat,
                    index: beatIndex,
                    barIndex: beatIndex / configuration.beatsPerBar,
                    beatInBar: beatIndex % configuration.beatsPerBar + 1,
                    startMicroseconds: beatStart,
                    endMicroseconds: beatEnd,
                    state: makeState(
                        from: beatOnsets,
                        beatCount: 1,
                        pulse: pulse
                    )
                )
            )
            beatOnsets.removeAll(keepingCapacity: true)

            if nextBeatNumber.isMultiple(of: configuration.beatsPerBar) {
                let barIndex = beatIndex / configuration.beatsPerBar
                let barStart = configuration.boundaryMicroseconds(
                    afterBeats: barIndex * configuration.beatsPerBar
                )
                snapshots.append(
                    MusicalStateSnapshot(
                        boundary: .bar,
                        index: barIndex,
                        barIndex: barIndex,
                        beatInBar: nil,
                        startMicroseconds: barStart,
                        endMicroseconds: beatEnd,
                        state: makeState(
                            from: barOnsets,
                            beatCount: configuration.beatsPerBar,
                            pulse: pulse
                        )
                    )
                )
                barOnsets.removeAll(keepingCapacity: true)
            }

            nextBeatNumber += 1
        }

        return snapshots
    }

    private func makeState(
        from onsets: [NoteObservation],
        beatCount: Int,
        pulse: PulseEstimate?
    ) -> MusicalState {
        let held = heldNotes.values.sorted {
            ($0.channel, $0.note) < ($1.channel, $1.note)
        }
        let velocities = onsets.map { Double($0.velocity) }
        let notes = onsets.map { Double($0.note) }

        return MusicalState(
            noteOnCount: onsets.count,
            noteDensityPerBeat: Double(onsets.count) / Double(beatCount),
            averageVelocity: velocities.average,
            averageNote: notes.average,
            lowestNote: onsets.map(\.note).min(),
            highestNote: onsets.map(\.note).max(),
            heldNotes: held,
            pulse: pulse,
            chordCandidates: chordCandidates(from: onsets, heldNotes: held)
        )
    }

    private mutating func prunePulseOnsets(at boundary: UInt64) {
        let windowBeats = max(configuration.beatsPerBar * 2, 8)
        let window = configuration.boundaryMicroseconds(afterBeats: windowBeats)
        let cutoff = boundary > window ? boundary - window : 0
        pulseOnsets.removeAll { $0 < cutoff }
    }

    private func estimatePulse() -> PulseEstimate? {
        guard pulseOnsets.count >= 2 else {
            return nil
        }

        var clustered: [UInt64] = []
        for onset in pulseOnsets {
            if let last = clustered.last, onset - last < 60_000 {
                continue
            }
            clustered.append(onset)
        }

        var candidates: [Double] = []
        for (first, second) in zip(clustered, clustered.dropFirst()) {
            let interval = second - first
            guard (200_000...2_000_000).contains(interval) else {
                continue
            }
            var bpm = 60_000_000 / Double(interval)
            while bpm < 60 {
                bpm *= 2
            }
            while bpm > 180 {
                bpm /= 2
            }
            candidates.append(bpm)
        }

        guard let bpm = candidates.median else {
            return nil
        }
        let deviations = candidates.map { abs($0 - bpm) }
        let medianDeviation = deviations.median ?? 0
        let consistency = max(0, 1 - medianDeviation / max(1, bpm * 0.2))
        let evidence = min(1, Double(candidates.count) / 4)
        return PulseEstimate(bpm: bpm, confidence: consistency * evidence)
    }

    private func chordCandidates(
        from onsets: [NoteObservation],
        heldNotes: [HeldNote]
    ) -> [ChordCandidate] {
        var histogram = Array(repeating: 0.0, count: 12)
        var observedKeys = Set<NoteKey>()

        for onset in onsets {
            histogram[Int(onset.note % 12)] += max(1, Double(onset.velocity)) / 127
            observedKeys.insert(NoteKey(channel: onset.channel, note: onset.note))
        }
        for held in heldNotes {
            let key = NoteKey(channel: held.channel, note: held.note)
            guard !observedKeys.contains(key) else {
                continue
            }
            histogram[Int(held.note % 12)] += 0.75 * max(1, Double(held.velocity)) / 127
        }

        let totalWeight = histogram.reduce(0, +)
        let uniquePitchClasses = histogram.filter { $0 > 0 }.count
        guard totalWeight > 0, uniquePitchClasses >= 2 else {
            return []
        }

        var candidates: [ChordCandidate] = []
        for root in 0..<12 {
            for quality in ChordQuality.allCases {
                let tones = quality.intervals.map { (root + $0) % 12 }
                let presentCount = tones.filter { histogram[$0] > 0 }.count
                guard presentCount >= 2 else {
                    continue
                }
                let chordWeight = tones.reduce(0.0) { $0 + histogram[$1] }
                let precision = chordWeight / totalWeight
                let coverage = Double(presentCount) / Double(tones.count)
                let confidence = 0.7 * precision + 0.3 * coverage
                guard confidence >= 0.55 else {
                    continue
                }
                candidates.append(
                    ChordCandidate(
                        rootPitchClass: UInt8(root),
                        quality: quality,
                        confidence: confidence
                    )
                )
            }
        }

        return candidates.sorted {
            if $0.confidence != $1.confidence {
                return $0.confidence > $1.confidence
            }
            if $0.rootPitchClass != $1.rootPitchClass {
                return $0.rootPitchClass < $1.rootPitchClass
            }
            return $0.quality.rawValue < $1.quality.rawValue
        }.prefix(3).map { $0 }
    }
}

private struct NoteKey: Hashable, Sendable {
    let channel: UInt8
    let note: UInt8
}

private struct NoteObservation: Sendable {
    let offsetMicroseconds: UInt64
    let channel: UInt8
    let note: UInt8
    let velocity: UInt8
}

private extension Array where Element == Double {
    var average: Double? {
        isEmpty ? nil : reduce(0, +) / Double(count)
    }

    var median: Double? {
        guard !isEmpty else {
            return nil
        }
        let sorted = sorted()
        let middle = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return (sorted[middle - 1] + sorted[middle]) / 2
        }
        return sorted[middle]
    }
}
