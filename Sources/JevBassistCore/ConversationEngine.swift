import Foundation

public enum ConversationRelationship: String, Codable, Equatable, Sendable {
    case rest
    case echo
    case tailVariation
    case hold
}

public struct ConversationResponseNote: Codable, Equatable, Sendable {
    public let note: UInt8
    public let velocity: UInt8
    public let relativeOnsetBeats: Double
    public let durationBeats: Double

    public init(
        note: UInt8,
        velocity: UInt8,
        relativeOnsetBeats: Double,
        durationBeats: Double
    ) {
        self.note = note
        self.velocity = velocity
        self.relativeOnsetBeats = relativeOnsetBeats
        self.durationBeats = durationBeats
    }
}

public struct ConversationScore: Codable, Equatable, Sendable {
    public let recognition: Double
    public let space: Double
    public let voiceLeading: Double
    public let modalFit: Double

    public var total: Double {
        recognition * 0.45 + space * 0.2 + voiceLeading * 0.2 + modalFit * 0.15
    }

    public init(
        recognition: Double,
        space: Double,
        voiceLeading: Double,
        modalFit: Double
    ) {
        self.recognition = min(1, max(0, recognition))
        self.space = min(1, max(0, space))
        self.voiceLeading = min(1, max(0, voiceLeading))
        self.modalFit = min(1, max(0, modalFit))
    }
}

public struct ConversationResponseCandidate: Codable, Equatable, Sendable {
    public let id: String
    public let relationship: ConversationRelationship
    public let notes: [ConversationResponseNote]
    public let score: ConversationScore

    public init(
        id: String,
        relationship: ConversationRelationship,
        notes: [ConversationResponseNote],
        score: ConversationScore
    ) {
        self.id = id
        self.relationship = relationship
        self.notes = notes
        self.score = score
    }
}

public struct ModalPitchContext: Equatable, Sendable {
    public let mode: MusicalMode
    public let tonalCenterPitchClass: UInt8

    public init(mode: MusicalMode, tonalCenterPitchClass: UInt8) {
        self.mode = mode
        self.tonalCenterPitchClass = tonalCenterPitchClass % 12
    }

    public func contains(_ note: UInt8) -> Bool {
        let relative = (Int(note % 12) - Int(tonalCenterPitchClass) + 12) % 12
        return mode.intervals.contains(relative)
    }

    public func conservativeProjection(_ note: UInt8) -> UInt8 {
        let folded = fold(Int(note), into: 55...79)
        guard !contains(UInt8(folded)) else { return UInt8(folded) }
        let candidates = (-2...2)
            .map { folded + $0 }
            .filter { (55...79).contains($0) && contains(UInt8($0)) }
        let projected = candidates.min {
            let left = abs($0 - folded)
            let right = abs($1 - folded)
            return left == right ? $0 < $1 : left < right
        } ?? folded
        return UInt8(projected)
    }

    public func neighboringScaleTone(from note: UInt8, direction: Int) -> UInt8 {
        let start = Int(conservativeProjection(note))
        let step = direction >= 0 ? 1 : -1
        for distance in 1...4 {
            let candidate = start + step * distance
            if (55...79).contains(candidate), contains(UInt8(candidate)) {
                return UInt8(candidate)
            }
        }
        return UInt8(start)
    }

    private func fold(_ note: Int, into range: ClosedRange<Int>) -> Int {
        var result = note
        while result < range.lowerBound { result += 12 }
        while result > range.upperBound { result -= 12 }
        return result
    }
}

public struct ResponseCandidateGenerator: Sendable {
    public init() {}

    public func candidates(
        for motif: Motif,
        pitchContext: ModalPitchContext
    ) -> [ConversationResponseCandidate] {
        let source = Array(motif.notes.prefix(6))
        guard source.count >= 2 else {
            return [restCandidate(confidence: motif.melodyConfidence)]
        }
        let echoNotes = source.map {
            ConversationResponseNote(
                note: pitchContext.conservativeProjection($0.note),
                velocity: softenedVelocity($0.velocity),
                relativeOnsetBeats: $0.relativeOnsetBeats,
                durationBeats: max(0.08, $0.durationBeats)
            )
        }
        var tailNotes = echoNotes
        if let last = tailNotes.last {
            tailNotes[tailNotes.count - 1] = ConversationResponseNote(
                note: pitchContext.neighboringScaleTone(
                    from: last.note,
                    direction: motif.features.pitchIntervals.last.map { $0 >= 0 ? 1 : -1 } ?? 1
                ),
                velocity: last.velocity,
                relativeOnsetBeats: last.relativeOnsetBeats,
                durationBeats: last.durationBeats
            )
        }
        let held = ConversationResponseNote(
            note: echoNotes.last?.note ?? echoNotes[0].note,
            velocity: UInt8(max(24, Int(echoNotes.last?.velocity ?? 48) - 8)),
            relativeOnsetBeats: 0,
            durationBeats: min(2, max(0.75, motif.durationBeats * 0.5))
        )
        let clarity = motif.melodyConfidence * motif.boundaryConfidence
        return [
            restCandidate(confidence: clarity),
            ConversationResponseCandidate(
                id: "echo",
                relationship: .echo,
                notes: echoNotes,
                score: ConversationScore(
                    recognition: 0.96,
                    space: 0.78,
                    voiceLeading: voiceLeading(echoNotes),
                    modalFit: 1
                )
            ),
            ConversationResponseCandidate(
                id: "tail",
                relationship: .tailVariation,
                notes: tailNotes,
                score: ConversationScore(
                    recognition: 0.82,
                    space: 0.76,
                    voiceLeading: voiceLeading(tailNotes),
                    modalFit: 1
                )
            ),
            ConversationResponseCandidate(
                id: "hold",
                relationship: .hold,
                notes: [held],
                score: ConversationScore(
                    recognition: 0.42,
                    space: 0.92,
                    voiceLeading: 0.9,
                    modalFit: 1
                )
            )
        ]
    }

    private func restCandidate(confidence: Double) -> ConversationResponseCandidate {
        ConversationResponseCandidate(
            id: "rest",
            relationship: .rest,
            notes: [],
            score: ConversationScore(
                recognition: confidence < 0.55 ? 1 : 0.18,
                space: 1,
                voiceLeading: 1,
                modalFit: 1
            )
        )
    }

    private func softenedVelocity(_ velocity: UInt8) -> UInt8 {
        UInt8(min(92, max(28, (Double(velocity) * 0.72).rounded())))
    }

    private func voiceLeading(_ notes: [ConversationResponseNote]) -> Double {
        guard notes.count > 1 else { return 1 }
        let intervals = zip(notes.dropFirst(), notes).map { later, earlier in
            abs(Int(later.note) - Int(earlier.note))
        }
        let average = Double(intervals.reduce(0, +)) / Double(intervals.count)
        return max(0, 1 - average / 12)
    }
}

public struct ResponseArbiter: Sendable {
    public init() {}

    public func choose(
        from candidates: [ConversationResponseCandidate]
    ) -> ConversationResponseCandidate? {
        candidates.max {
            if $0.score.total != $1.score.total {
                return $0.score.total < $1.score.total
            }
            return $0.id > $1.id
        }
    }
}

public struct ConversationEngine: Sendable {
    public let musicalStateConfiguration: MusicalStateConfiguration
    public let mode: MusicalMode
    public let outputChannel: UInt8

    private let generator = ResponseCandidateGenerator()
    private let arbiter = ResponseArbiter()

    public init(
        musicalStateConfiguration: MusicalStateConfiguration,
        mode: MusicalMode,
        outputChannel: UInt8
    ) {
        self.musicalStateConfiguration = musicalStateConfiguration
        self.mode = mode
        self.outputChannel = outputChannel
    }

    public func plan(for motif: Motif) -> BassBarPlan? {
        let legacy = motif.legacyMemory()
        guard let center = ModalHarmonyPlanner(mode: mode).inferTonalCenter(from: legacy.notes) else {
            return nil
        }
        let context = ModalPitchContext(mode: mode, tonalCenterPitchClass: center)
        let candidates = generator.candidates(for: motif, pitchContext: context)
        guard let selected = arbiter.choose(from: candidates) else { return nil }
        let beatMicroseconds = 60_000_000 / musicalStateConfiguration.tempoBPM
        let start = nextBeat(after: motif.finalizedAtMicroseconds, beat: beatMicroseconds)
        let phrase = render(selected, startMicroseconds: start, beatMicroseconds: beatMicroseconds)
        let barLength = musicalStateConfiguration.boundaryMicroseconds(
            afterBeats: musicalStateConfiguration.beatsPerBar
        )
        let decision = decision(for: selected.relationship)
        return BassBarPlan(
            sourceBarIndex: Int(motif.finalizedAtMicroseconds / barLength),
            targetBarIndex: Int(start / barLength),
            chord: nil,
            usedHeldChord: false,
            decision: decision,
            decisionSource: .rules,
            developmentStage: nil,
            tonalCenterPitchClass: center,
            phrase: phrase,
            expression: expression(for: selected)
        )
    }

    private func render(
        _ candidate: ConversationResponseCandidate,
        startMicroseconds: UInt64,
        beatMicroseconds: Double
    ) -> BassPhrase {
        let ordered = candidate.notes.sorted { $0.relativeOnsetBeats < $1.relativeOnsetBeats }
        var messages: [ScheduledMIDIMessage] = []
        for index in ordered.indices {
            let note = ordered[index]
            let onset = startMicroseconds
                + UInt64((note.relativeOnsetBeats * beatMicroseconds).rounded())
            let desiredRelease = onset
                + UInt64((note.durationBeats * beatMicroseconds).rounded())
            let release: UInt64
            if index + 1 < ordered.count {
                let nextOnset = startMicroseconds
                    + UInt64((ordered[index + 1].relativeOnsetBeats * beatMicroseconds).rounded())
                release = min(desiredRelease, max(onset + 1, nextOnset - 1))
            } else {
                release = desiredRelease
            }
            messages.append(
                ScheduledMIDIMessage(
                    offsetMicroseconds: onset,
                    kind: .noteOn,
                    channel: outputChannel,
                    note: note.note,
                    velocity: note.velocity
                )
            )
            messages.append(
                ScheduledMIDIMessage(
                    offsetMicroseconds: release,
                    kind: .noteOff,
                    channel: outputChannel,
                    note: note.note,
                    velocity: 0
                )
            )
        }
        messages.sort {
            if $0.offsetMicroseconds != $1.offsetMicroseconds {
                return $0.offsetMicroseconds < $1.offsetMicroseconds
            }
            return $0.kind == .noteOff && $1.kind == .noteOn
        }
        let end = messages.map(\.offsetMicroseconds).max() ?? startMicroseconds
        let barLength = musicalStateConfiguration.boundaryMicroseconds(
            afterBeats: musicalStateConfiguration.beatsPerBar
        )
        return BassPhrase(
            barIndex: Int(startMicroseconds / barLength),
            startMicroseconds: startMicroseconds,
            endMicroseconds: end,
            messages: messages
        )
    }

    private func nextBeat(after offset: UInt64, beat: Double) -> UInt64 {
        let beatIndex = floor(Double(offset) / beat) + 1
        return UInt64((beatIndex * beat).rounded())
    }

    private func decision(for relationship: ConversationRelationship) -> BassDecision {
        switch relationship {
        case .rest:
            return BassDecision(activity: .rest, relationship: .hold, motion: .root, fill: false, confidence: 1)
        case .echo:
            return BassDecision(activity: .normal, relationship: .follow, motion: .step, fill: false, confidence: 0.9)
        case .tailVariation:
            return BassDecision(activity: .normal, relationship: .contrast, motion: .step, fill: false, confidence: 0.82)
        case .hold:
            return BassDecision(activity: .sparse, relationship: .hold, motion: .root, fill: false, confidence: 0.78)
        }
    }

    private func expression(
        for candidate: ConversationResponseCandidate
    ) -> EnsembleExpression {
        EnsembleExpression(
            memory: candidate.relationship == .echo ? 0.92 : 0.72,
            tension: candidate.relationship == .tailVariation ? 0.48 : 0.28,
            activity: min(1, Double(candidate.notes.count) / 6),
            resonance: candidate.relationship == .hold ? 0.8 : 0.52
        )
    }
}
