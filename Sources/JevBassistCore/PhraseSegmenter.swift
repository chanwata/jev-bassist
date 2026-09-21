import Foundation

public struct PhraseObservation: Codable, Equatable, Sendable {
    public let notes: [PerformedNote]
    public let melodyNotes: [PerformedNote]
    public let simultaneousNoteGroups: [[UInt64]]
    public let startMicroseconds: UInt64
    public let endMicroseconds: UInt64
    public let finalizedAtMicroseconds: UInt64
    public let boundaryConfidence: Double
    public let melodyConfidence: Double

    public init(
        notes: [PerformedNote],
        melodyNotes: [PerformedNote],
        simultaneousNoteGroups: [[UInt64]],
        startMicroseconds: UInt64,
        endMicroseconds: UInt64,
        finalizedAtMicroseconds: UInt64,
        boundaryConfidence: Double,
        melodyConfidence: Double
    ) {
        self.notes = notes
        self.melodyNotes = melodyNotes
        self.simultaneousNoteGroups = simultaneousNoteGroups
        self.startMicroseconds = startMicroseconds
        self.endMicroseconds = endMicroseconds
        self.finalizedAtMicroseconds = finalizedAtMicroseconds
        self.boundaryConfidence = min(1, max(0, boundaryConfidence))
        self.melodyConfidence = min(1, max(0, melodyConfidence))
    }
}

public enum PhraseSegmenterError: Error, CustomStringConvertible, Equatable {
    case tooManyPendingNotes(Int)
    case nonMonotonicAdvance(offsetMicroseconds: UInt64)
    case advanceAfterFinish

    public var description: String {
        switch self {
        case let .tooManyPendingNotes(value):
            return "Phrase segmenter exceeded its \(value)-note pending limit."
        case let .nonMonotonicAdvance(offset):
            return "Phrase clock advance to \(offset) microseconds is earlier than the preceding advance."
        case .advanceAfterFinish:
            return "Cannot advance the phrase segmenter after finish."
        }
    }
}

public struct PhraseSegmenter: Sendable {
    public let musicalStateConfiguration: MusicalStateConfiguration
    public let maximumPendingNotes: Int
    public let simultaneityWindowMicroseconds: UInt64
    public let maximumContinuousNotes: Int

    private var pendingNotes: [PerformedNote] = []
    private var lastAdvanceOffset: UInt64?
    private var finished = false

    public init(
        musicalStateConfiguration: MusicalStateConfiguration,
        maximumPendingNotes: Int = 64,
        simultaneityWindowMicroseconds: UInt64 = 40_000,
        maximumContinuousNotes: Int = 32
    ) {
        precondition((2...512).contains(maximumPendingNotes))
        precondition((2...maximumPendingNotes).contains(maximumContinuousNotes))
        self.musicalStateConfiguration = musicalStateConfiguration
        self.maximumPendingNotes = maximumPendingNotes
        self.simultaneityWindowMicroseconds = simultaneityWindowMicroseconds
        self.maximumContinuousNotes = maximumContinuousNotes
    }

    public mutating func ingest(
        completedNotes: [PerformedNote]
    ) throws {
        guard pendingNotes.count + completedNotes.count <= maximumPendingNotes else {
            throw PhraseSegmenterError.tooManyPendingNotes(maximumPendingNotes)
        }
        pendingNotes.append(contentsOf: completedNotes)
        pendingNotes.sort(by: Self.noteOrder)
    }

    public mutating func advance(
        through offsetMicroseconds: UInt64,
        hasActiveNotes: Bool
    ) throws -> [PhraseObservation] {
        guard !finished else {
            throw PhraseSegmenterError.advanceAfterFinish
        }
        try validateAdvance(offsetMicroseconds)
        return finalizeIfSilent(
            through: offsetMicroseconds,
            hasActiveNotes: hasActiveNotes
        )
    }

    public mutating func observeEvent(
        at offsetMicroseconds: UInt64,
        hasActiveNotes: Bool
    ) throws -> [PhraseObservation] {
        guard !finished else {
            throw PhraseSegmenterError.advanceAfterFinish
        }
        return finalizeIfSilent(
            through: offsetMicroseconds,
            hasActiveNotes: hasActiveNotes
        )
    }

    private mutating func finalizeIfSilent(
        through offsetMicroseconds: UInt64,
        hasActiveNotes: Bool
    ) -> [PhraseObservation] {
        if pendingNotes.count >= maximumContinuousNotes,
           let lastRelease = pendingNotes.map(\.releaseMicroseconds).max(),
           offsetMicroseconds >= lastRelease {
            return [finalize(at: lastRelease, boundaryConfidence: 0.65)]
        }
        guard !hasActiveNotes,
              let lastRelease = pendingNotes.map(\.releaseMicroseconds).max() else {
            return []
        }
        let boundary = lastRelease + silenceThresholdMicroseconds()
        guard offsetMicroseconds >= boundary else {
            return []
        }
        return [finalize(at: boundary, boundaryConfidence: 0.9)]
    }

    public mutating func finish(
        through offsetMicroseconds: UInt64
    ) throws -> [PhraseObservation] {
        if let lastAdvanceOffset, offsetMicroseconds < lastAdvanceOffset {
            throw PhraseSegmenterError.nonMonotonicAdvance(
                offsetMicroseconds: offsetMicroseconds
            )
        }
        guard !finished else { return [] }
        finished = true
        lastAdvanceOffset = offsetMicroseconds
        guard !pendingNotes.isEmpty else { return [] }

        let lastRelease = pendingNotes.map(\.releaseMicroseconds).max() ?? offsetMicroseconds
        let naturalBoundary = lastRelease + silenceThresholdMicroseconds()
        if offsetMicroseconds >= naturalBoundary {
            return [finalize(at: naturalBoundary, boundaryConfidence: 0.9)]
        }
        return [finalize(at: offsetMicroseconds, boundaryConfidence: 0.55)]
    }

    private mutating func validateAdvance(_ offsetMicroseconds: UInt64) throws {
        if let lastAdvanceOffset, offsetMicroseconds < lastAdvanceOffset {
            throw PhraseSegmenterError.nonMonotonicAdvance(
                offsetMicroseconds: offsetMicroseconds
            )
        }
        lastAdvanceOffset = offsetMicroseconds
    }

    private func silenceThresholdMicroseconds() -> UInt64 {
        let beat = 60_000_000 / musicalStateConfiguration.tempoBPM
        let onsets = onsetGroups().compactMap { group in
            group.first?.onsetMicroseconds
        }
        let intervals = zip(onsets.dropFirst(), onsets).map { later, earlier in
            Double(later - earlier)
        }.sorted()
        let typicalInterval: Double
        if intervals.isEmpty {
            typicalInterval = beat
        } else if intervals.count.isMultiple(of: 2) {
            let upper = intervals.count / 2
            typicalInterval = (intervals[upper - 1] + intervals[upper]) / 2
        } else {
            typicalInterval = intervals[intervals.count / 2]
        }
        let adaptive = typicalInterval * 0.75
        return UInt64(max(beat * 0.5, min(beat * 1.5, adaptive)).rounded())
    }

    private mutating func finalize(
        at finalizedAtMicroseconds: UInt64,
        boundaryConfidence: Double
    ) -> PhraseObservation {
        let notes = pendingNotes.sorted(by: Self.noteOrder)
        pendingNotes.removeAll(keepingCapacity: true)
        let groups = onsetGroups(for: notes)
        let melody = melodyCandidate(from: groups)
        let simultaneousGroupCount = groups.filter { $0.count > 1 }.count
        let simultaneousRatio = groups.isEmpty
            ? 0
            : Double(simultaneousGroupCount) / Double(groups.count)
        let inferredRatio = melody.isEmpty
            ? 0
            : Double(melody.filter { $0.release != .observed }.count) / Double(melody.count)
        let melodyConfidence = max(
            0,
            1 - simultaneousRatio * 0.5 - inferredRatio * 0.25
        )
        return PhraseObservation(
            notes: notes,
            melodyNotes: melody,
            simultaneousNoteGroups: groups.map { $0.map(\.id) },
            startMicroseconds: notes.first?.onsetMicroseconds ?? finalizedAtMicroseconds,
            endMicroseconds: notes.map(\.releaseMicroseconds).max() ?? finalizedAtMicroseconds,
            finalizedAtMicroseconds: finalizedAtMicroseconds,
            boundaryConfidence: boundaryConfidence,
            melodyConfidence: melodyConfidence
        )
    }

    private func onsetGroups() -> [[PerformedNote]] {
        onsetGroups(for: pendingNotes.sorted(by: Self.noteOrder))
    }

    private func onsetGroups(for notes: [PerformedNote]) -> [[PerformedNote]] {
        var groups: [[PerformedNote]] = []
        for note in notes {
            if let groupStart = groups.last?.first?.onsetMicroseconds,
               note.onsetMicroseconds - groupStart <= simultaneityWindowMicroseconds {
                groups[groups.count - 1].append(note)
            } else {
                groups.append([note])
            }
        }
        return groups
    }

    private func melodyCandidate(
        from groups: [[PerformedNote]]
    ) -> [PerformedNote] {
        var previous: PerformedNote?
        return groups.compactMap { group in
            let selected: PerformedNote?
            if let previous {
                selected = group.min { left, right in
                    let leftDistance = abs(Int(left.note) - Int(previous.note))
                    let rightDistance = abs(Int(right.note) - Int(previous.note))
                    if leftDistance != rightDistance {
                        return leftDistance < rightDistance
                    }
                    if left.velocity != right.velocity {
                        return left.velocity > right.velocity
                    }
                    return left.note > right.note
                }
            } else {
                selected = group.max { left, right in
                    if left.velocity != right.velocity {
                        return left.velocity < right.velocity
                    }
                    return left.note < right.note
                }
            }
            previous = selected
            return selected
        }
    }

    private static func noteOrder(_ left: PerformedNote, _ right: PerformedNote) -> Bool {
        if left.onsetMicroseconds != right.onsetMicroseconds {
            return left.onsetMicroseconds < right.onsetMicroseconds
        }
        return left.id < right.id
    }
}
