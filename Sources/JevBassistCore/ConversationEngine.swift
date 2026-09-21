import Foundation

public enum ConversationRelationship: String, Codable, Equatable, Sendable {
    case rest
    case echo
    case tailVariation
    case hold
    case sequence
    case inversion
    case fragmentation
    case augmentation
    case originalReturn
}

public struct ConversationLineage: Codable, Equatable, Sendable {
    public let originMotifID: UInt64
    public let sourceMotifID: UInt64
    public let responseID: UInt64
    public let parentResponseID: UInt64?
    public let generation: Int
    public let relationship: ConversationRelationship

    public init(
        originMotifID: UInt64,
        sourceMotifID: UInt64,
        responseID: UInt64,
        parentResponseID: UInt64?,
        generation: Int,
        relationship: ConversationRelationship
    ) {
        self.originMotifID = originMotifID
        self.sourceMotifID = sourceMotifID
        self.responseID = responseID
        self.parentResponseID = parentResponseID
        self.generation = generation
        self.relationship = relationship
    }
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

    public func developmentCandidates(
        origin: Motif,
        current: Motif,
        pitchContext: ModalPitchContext
    ) -> [ConversationResponseCandidate] {
        var result = candidates(for: current, pitchContext: pitchContext)
        let source = Array(origin.notes.prefix(6))
        guard source.count >= 2 else { return result }
        let originStart = Int(source[0].note)
        let currentStart = Int(current.notes.first?.note ?? source[0].note)
        let transposition = max(-7, min(7, currentStart - originStart))

        let sequence = source.map {
            responseNote(
                from: $0,
                pitch: pitchContext.conservativeProjection(
                    UInt8(max(0, min(127, Int($0.note) + transposition)))
                )
            )
        }
        let inversion = source.map {
            responseNote(
                from: $0,
                pitch: pitchContext.conservativeProjection(
                    UInt8(max(0, min(127, originStart - (Int($0.note) - originStart))))
                )
            )
        }
        let fragmentSource = source.enumerated().filter { index, note in
            index == 0
                || origin.features.accentedNoteIndices.contains(index)
                || origin.features.characteristicIntervalIndices.contains(max(0, index - 1))
                || note.restBeforeBeats >= 0.25
        }.prefix(3)
        let fragment = fragmentSource.map { _, note in
            responseNote(from: note, pitch: pitchContext.conservativeProjection(note.note))
        }
        let augmentation = source.map {
            ConversationResponseNote(
                note: pitchContext.conservativeProjection($0.note),
                velocity: softenedVelocity($0.velocity),
                relativeOnsetBeats: $0.relativeOnsetBeats * 1.5,
                durationBeats: max(0.12, $0.durationBeats * 1.35)
            )
        }
        let original = source.map {
            responseNote(from: $0, pitch: pitchContext.conservativeProjection($0.note))
        }

        result += [
            developmentCandidate("sequence", .sequence, sequence, recognition: 0.78),
            developmentCandidate("inversion", .inversion, inversion, recognition: 0.7),
            developmentCandidate("fragment", .fragmentation, fragment, recognition: 0.68),
            developmentCandidate("augment", .augmentation, augmentation, recognition: 0.76),
            developmentCandidate("return", .originalReturn, original, recognition: 1)
        ]
        return result
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

    private func responseNote(from note: MotifNote, pitch: UInt8) -> ConversationResponseNote {
        ConversationResponseNote(
            note: pitch,
            velocity: softenedVelocity(note.velocity),
            relativeOnsetBeats: note.relativeOnsetBeats,
            durationBeats: max(0.08, note.durationBeats)
        )
    }

    private func developmentCandidate(
        _ id: String,
        _ relationship: ConversationRelationship,
        _ notes: [ConversationResponseNote],
        recognition: Double
    ) -> ConversationResponseCandidate {
        ConversationResponseCandidate(
            id: id,
            relationship: relationship,
            notes: notes,
            score: ConversationScore(
                recognition: recognition,
                space: relationship == .augmentation ? 0.72 : 0.76,
                voiceLeading: voiceLeading(notes),
                modalFit: 1
            )
        )
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

    public func choose(
        from candidates: [ConversationResponseCandidate],
        context: ConversationDevelopmentContext
    ) -> ConversationResponseCandidate? {
        if context.generation == 0 {
            return candidates.first { $0.relationship == .echo } ?? choose(from: candidates)
        }
        if context.accumulatedDivergence >= 1.35 {
            return candidates.first { $0.relationship == .originalReturn }
        }
        let preferred: ConversationRelationship
        if context.notesPerBeat >= 2.2 {
            preferred = .augmentation
        } else if context.registerShift >= 3 {
            preferred = .sequence
        } else if context.originSimilarity >= 0.78 {
            preferred = .inversion
        } else if context.originDurationBeats >= 2.5 {
            preferred = .fragmentation
        } else {
            preferred = .tailVariation
        }
        return candidates.first { $0.relationship == preferred } ?? choose(from: candidates)
    }
}

public struct ConversationDevelopmentContext: Codable, Equatable, Sendable {
    public let generation: Int
    public let accumulatedDivergence: Double
    public let originSimilarity: Double
    public let notesPerBeat: Double
    public let registerShift: Int
    public let originDurationBeats: Double

    public init(
        generation: Int,
        accumulatedDivergence: Double,
        originSimilarity: Double,
        notesPerBeat: Double,
        registerShift: Int,
        originDurationBeats: Double
    ) {
        self.generation = generation
        self.accumulatedDivergence = accumulatedDivergence
        self.originSimilarity = originSimilarity
        self.notesPerBeat = notesPerBeat
        self.registerShift = registerShift
        self.originDurationBeats = originDurationBeats
    }
}

public struct ConversationCandidateSummary: Codable, Equatable, Sendable {
    public let id: String
    public let relationship: ConversationRelationship
    public let noteCount: Int
    public let recognition: Double
    public let space: Double
    public let voiceLeading: Double

    public init(candidate: ConversationResponseCandidate) {
        id = candidate.id
        relationship = candidate.relationship
        noteCount = candidate.notes.count
        recognition = candidate.score.recognition
        space = candidate.score.space
        voiceLeading = candidate.score.voiceLeading
    }
}

public struct ConversationSelectionInput: Codable, Equatable, Sendable {
    public let revision: UInt64
    public let mode: MusicalMode
    public let originMotifID: UInt64
    public let sourceMotifID: UInt64
    public let context: ConversationDevelopmentContext
    public let candidates: [ConversationCandidateSummary]
    public let localCandidateID: String

    public init(
        revision: UInt64,
        mode: MusicalMode,
        originMotifID: UInt64,
        sourceMotifID: UInt64,
        context: ConversationDevelopmentContext,
        candidates: [ConversationCandidateSummary],
        localCandidateID: String
    ) {
        self.revision = revision
        self.mode = mode
        self.originMotifID = originMotifID
        self.sourceMotifID = sourceMotifID
        self.context = context
        self.candidates = candidates
        self.localCandidateID = localCandidateID
    }
}

public struct ConversationSelectionResolution: Equatable, Sendable {
    public let candidateID: String
    public let source: BassDecisionSource

    public init(candidateID: String, source: BassDecisionSource) {
        self.candidateID = candidateID
        self.source = source
    }
}

public protocol ConversationDecisionProvider: Sendable {
    func prepare(_ input: ConversationSelectionInput)
    func resolution(for input: ConversationSelectionInput) -> ConversationSelectionResolution?
    func expire(revision: UInt64)
    func cancelPendingDecisions()
}

public struct LocalConversationDecisionProvider: ConversationDecisionProvider {
    public init() {}

    public func prepare(_ input: ConversationSelectionInput) {}

    public func resolution(
        for input: ConversationSelectionInput
    ) -> ConversationSelectionResolution? {
        ConversationSelectionResolution(
            candidateID: input.localCandidateID,
            source: .rules
        )
    }

    public func expire(revision: UInt64) {}
    public func cancelPendingDecisions() {}
}

private struct PendingConversation: Sendable {
    let motif: Motif
    let tonalCenterPitchClass: UInt8
    let candidates: [ConversationResponseCandidate]
    let selectionInput: ConversationSelectionInput
    let responseStartMicroseconds: UInt64
    let selectionDeadlineMicroseconds: UInt64
}

public struct ConversationEngine: Sendable {
    public let musicalStateConfiguration: MusicalStateConfiguration
    public let mode: MusicalMode
    public let outputChannel: UInt8

    private let generator = ResponseCandidateGenerator()
    private let arbiter = ResponseArbiter()
    private let decisionProvider: any ConversationDecisionProvider
    private var originMotif: Motif?
    private var generation = 0
    private var accumulatedDivergence = 0.0
    private var nextResponseID: UInt64 = 1
    private var previousResponseID: UInt64?
    private var nextRevision: UInt64 = 1
    private var pendingConversation: PendingConversation?

    public init(
        musicalStateConfiguration: MusicalStateConfiguration,
        mode: MusicalMode,
        outputChannel: UInt8,
        decisionProvider: any ConversationDecisionProvider = LocalConversationDecisionProvider()
    ) {
        self.musicalStateConfiguration = musicalStateConfiguration
        self.mode = mode
        self.outputChannel = outputChannel
        self.decisionProvider = decisionProvider
    }

    public mutating func plan(
        for motif: Motif,
        availableAtMicroseconds: UInt64? = nil
    ) -> BassBarPlan? {
        let availableAt = max(
            motif.finalizedAtMicroseconds,
            availableAtMicroseconds ?? motif.finalizedAtMicroseconds
        )
        guard let prepared = prepareConversation(for: motif) else { return nil }
        let selected = prepared.localSelection
        let start = nextBeat(after: availableAt, beat: beatMicroseconds)
        return finalize(
            motif: motif,
            selected: selected,
            tonalCenterPitchClass: prepared.tonalCenterPitchClass,
            startMicroseconds: start,
            decisionSource: .rules
        )
    }

    public mutating func submit(
        _ motif: Motif,
        availableAtMicroseconds: UInt64
    ) -> BassBarPlan? {
        if let pendingConversation {
            decisionProvider.expire(revision: pendingConversation.selectionInput.revision)
            self.pendingConversation = nil
        }
        guard let prepared = prepareConversation(for: motif) else { return nil }
        let revision = nextRevision
        nextRevision += 1
        let input = ConversationSelectionInput(
            revision: revision,
            mode: mode,
            originMotifID: prepared.originMotifID,
            sourceMotifID: motif.id,
            context: prepared.developmentContext,
            candidates: prepared.candidates.map(ConversationCandidateSummary.init),
            localCandidateID: prepared.localSelection.id
        )
        decisionProvider.prepare(input)
        if let resolution = decisionProvider.resolution(for: input),
           let selected = prepared.candidates.first(where: {
               $0.id == resolution.candidateID
           }) {
            let start = nextBeat(after: availableAtMicroseconds, beat: beatMicroseconds)
            return finalize(
                motif: motif,
                selected: selected,
                tonalCenterPitchClass: prepared.tonalCenterPitchClass,
                startMicroseconds: start,
                decisionSource: resolution.source
            )
        }

        let earliestDecision = availableAtMicroseconds + 350_000
        let responseStart = nextBeat(after: earliestDecision, beat: beatMicroseconds)
        pendingConversation = PendingConversation(
            motif: motif,
            tonalCenterPitchClass: prepared.tonalCenterPitchClass,
            candidates: prepared.candidates,
            selectionInput: input,
            responseStartMicroseconds: responseStart,
            selectionDeadlineMicroseconds: responseStart > 100_000
                ? responseStart - 100_000
                : 0
        )
        return nil
    }

    public mutating func advance(through offsetMicroseconds: UInt64) -> BassBarPlan? {
        guard let pending = pendingConversation else { return nil }
        let resolution = decisionProvider.resolution(for: pending.selectionInput)
        if resolution == nil, offsetMicroseconds < pending.selectionDeadlineMicroseconds {
            return nil
        }
        pendingConversation = nil
        let selected: ConversationResponseCandidate
        let source: BassDecisionSource
        if let resolution,
           let resolved = pending.candidates.first(where: {
               $0.id == resolution.candidateID
           }) {
            selected = resolved
            source = resolution.source
        } else {
            decisionProvider.expire(revision: pending.selectionInput.revision)
            selected = pending.candidates.first {
                $0.id == pending.selectionInput.localCandidateID
            } ?? pending.candidates[0]
            source = .fallback
        }
        let start = offsetMicroseconds < pending.responseStartMicroseconds
            ? pending.responseStartMicroseconds
            : nextBeat(after: offsetMicroseconds, beat: beatMicroseconds)
        return finalize(
            motif: pending.motif,
            selected: selected,
            tonalCenterPitchClass: pending.tonalCenterPitchClass,
            startMicroseconds: start,
            decisionSource: source
        )
    }

    public mutating func yieldToHuman() {
        guard let pendingConversation else { return }
        decisionProvider.expire(revision: pendingConversation.selectionInput.revision)
        self.pendingConversation = nil
    }

    public func cancelPendingDecisions() {
        decisionProvider.cancelPendingDecisions()
    }

    private var beatMicroseconds: Double {
        60_000_000 / musicalStateConfiguration.tempoBPM
    }

    private mutating func prepareConversation(for motif: Motif) -> (
        originMotifID: UInt64,
        tonalCenterPitchClass: UInt8,
        developmentContext: ConversationDevelopmentContext,
        candidates: [ConversationResponseCandidate],
        localSelection: ConversationResponseCandidate
    )? {
        if originMotif == nil { originMotif = motif }
        guard let originMotif else { return nil }
        let legacy = originMotif.legacyMemory()
        guard let center = ModalHarmonyPlanner(mode: mode).inferTonalCenter(from: legacy.notes) else {
            return nil
        }
        let pitchContext = ModalPitchContext(mode: mode, tonalCenterPitchClass: center)
        let developmentContext = contextFor(origin: originMotif, current: motif)
        let candidates = generator.developmentCandidates(
            origin: originMotif,
            current: motif,
            pitchContext: pitchContext
        )
        guard let selected = arbiter.choose(from: candidates, context: developmentContext) else {
            return nil
        }
        return (originMotif.id, center, developmentContext, candidates, selected)
    }

    private mutating func finalize(
        motif: Motif,
        selected: ConversationResponseCandidate,
        tonalCenterPitchClass center: UInt8,
        startMicroseconds start: UInt64,
        decisionSource: BassDecisionSource
    ) -> BassBarPlan {
        let phrase = render(selected, startMicroseconds: start, beatMicroseconds: beatMicroseconds)
        let barLength = musicalStateConfiguration.boundaryMicroseconds(
            afterBeats: musicalStateConfiguration.beatsPerBar
        )
        let decision = decision(for: selected.relationship)
        let responseID = nextResponseID
        let lineage = ConversationLineage(
            originMotifID: originMotif?.id ?? motif.id,
            sourceMotifID: motif.id,
            responseID: responseID,
            parentResponseID: previousResponseID,
            generation: generation,
            relationship: selected.relationship
        )
        nextResponseID += 1
        previousResponseID = responseID
        generation += 1
        if selected.relationship == .originalReturn {
            accumulatedDivergence = 0
        } else {
            accumulatedDivergence += divergence(for: selected.relationship)
        }
        return BassBarPlan(
            sourceBarIndex: Int(motif.finalizedAtMicroseconds / barLength),
            targetBarIndex: Int(start / barLength),
            chord: nil,
            usedHeldChord: false,
            decision: decision,
            decisionSource: decisionSource,
            developmentStage: nil,
            tonalCenterPitchClass: center,
            conversationLineage: lineage,
            phrase: phrase,
            expression: expression(for: selected)
        )
    }

    private func contextFor(origin: Motif, current: Motif) -> ConversationDevelopmentContext {
        let originSigns = origin.features.pitchIntervals.map { $0.signum() }
        let currentSigns = current.features.pitchIntervals.map { $0.signum() }
        let comparisons = min(originSigns.count, currentSigns.count)
        let matches = zip(originSigns.prefix(comparisons), currentSigns.prefix(comparisons))
            .filter { left, right in left == right }.count
        let similarity = comparisons == 0 ? 0 : Double(matches) / Double(comparisons)
        let notesPerBeat = Double(current.notes.count) / max(0.25, current.durationBeats)
        let registerShift = abs(
            Int(current.notes.first?.note ?? 60) - Int(origin.notes.first?.note ?? 60)
        )
        return ConversationDevelopmentContext(
            generation: generation,
            accumulatedDivergence: accumulatedDivergence,
            originSimilarity: similarity,
            notesPerBeat: notesPerBeat,
            registerShift: registerShift,
            originDurationBeats: origin.durationBeats
        )
    }

    private func divergence(for relationship: ConversationRelationship) -> Double {
        switch relationship {
        case .rest, .hold: return 0.15
        case .echo: return 0.2
        case .tailVariation: return 0.35
        case .sequence: return 0.55
        case .fragmentation: return 0.6
        case .augmentation: return 0.65
        case .inversion: return 0.8
        case .originalReturn: return 0
        }
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
        case .sequence:
            return BassDecision(activity: .normal, relationship: .follow, motion: .step, fill: false, confidence: 0.82)
        case .inversion:
            return BassDecision(activity: .normal, relationship: .contrast, motion: .leap, fill: false, confidence: 0.78)
        case .fragmentation:
            return BassDecision(activity: .sparse, relationship: .contrast, motion: .step, fill: false, confidence: 0.76)
        case .augmentation:
            return BassDecision(activity: .sparse, relationship: .follow, motion: .step, fill: false, confidence: 0.8)
        case .originalReturn:
            return BassDecision(activity: .normal, relationship: .follow, motion: .root, fill: false, confidence: 0.94)
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
