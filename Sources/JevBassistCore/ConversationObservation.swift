import Foundation

public enum ConversationIntent: String, Codable, Equatable, Sendable {
    case acknowledge
    case continueIdea
    case question
    case support
    case settle
    case wait
}

public enum ConversationTurnState: String, Codable, Equatable, Sendable {
    case listening
    case preparing
    case responding
    case overlapping
    case yielding
    case awaitingReply
    case settling
}

public enum InteractionKind: String, Codable, Equatable, Sendable {
    case imitation
    case rhythmicReply
    case continuation
    case selfRepetition
    case newProposal
    case ambiguous
}

public struct ConversationMaterialSummary: Codable, Equatable, Sendable {
    public let id: UInt64
    public let pitches: [UInt8]
    public let relativeOnsets: [Double]
    public let durations: [Double]
    public let accents: [Double]

    public init(motif: Motif, maximumNotes: Int = 12) {
        let notes = Array(motif.notes.prefix(maximumNotes))
        id = motif.id
        pitches = notes.map(\.note)
        relativeOnsets = notes.map(\.relativeOnsetBeats)
        durations = notes.map(\.durationBeats)
        accents = notes.map(\.accent)
    }

    public init(
        id: UInt64,
        response: [ConversationResponseNote],
        maximumNotes: Int = 12
    ) {
        let notes = Array(response.prefix(maximumNotes))
        self.id = id
        pitches = notes.map(\.note)
        relativeOnsets = notes.map(\.relativeOnsetBeats)
        durations = notes.map(\.durationBeats)
        accents = notes.map { Double($0.velocity) / 127 }
    }
}

public struct InteractionEvidence: Codable, Equatable, Sendable {
    public let kind: InteractionKind
    public let confidence: Double
    public let pitchContour: Double
    public let intervalShape: Double
    public let rhythm: Double
    public let duration: Double
    public let responseDelayBeats: Double

    public init(
        kind: InteractionKind,
        confidence: Double,
        pitchContour: Double,
        intervalShape: Double,
        rhythm: Double,
        duration: Double,
        responseDelayBeats: Double
    ) {
        self.kind = kind
        self.confidence = Self.unit(confidence)
        self.pitchContour = Self.unit(pitchContour)
        self.intervalShape = Self.unit(intervalShape)
        self.rhythm = Self.unit(rhythm)
        self.duration = Self.unit(duration)
        self.responseDelayBeats = max(0, responseDelayBeats)
    }

    public static let unavailable = InteractionEvidence(
        kind: .ambiguous,
        confidence: 0,
        pitchContour: 0,
        intervalShape: 0,
        rhythm: 0,
        duration: 0,
        responseDelayBeats: 0
    )

    private static func unit(_ value: Double) -> Double {
        min(1, max(0, value.isFinite ? value : 0))
    }
}

public struct ConversationStateSummary: Codable, Equatable, Sendable {
    public let themeRevision: UInt64
    public let intent: ConversationIntent
    public let turnState: ConversationTurnState
    public let interaction: InteractionEvidence
    public let origin: ConversationMaterialSummary
    public let sharedTheme: ConversationMaterialSummary
    public let latestHuman: ConversationMaterialSummary
    public let previousResponse: ConversationMaterialSummary?

    public init(
        themeRevision: UInt64,
        intent: ConversationIntent,
        turnState: ConversationTurnState,
        interaction: InteractionEvidence,
        origin: ConversationMaterialSummary,
        sharedTheme: ConversationMaterialSummary,
        latestHuman: ConversationMaterialSummary,
        previousResponse: ConversationMaterialSummary?
    ) {
        self.themeRevision = themeRevision
        self.intent = intent
        self.turnState = turnState
        self.interaction = interaction
        self.origin = origin
        self.sharedTheme = sharedTheme
        self.latestHuman = latestHuman
        self.previousResponse = previousResponse
    }
}

public struct InteractionMatcher: Sendable {
    public init() {}

    public func compare(
        human: Motif,
        response: [ConversationResponseNote],
        responseEndedAtMicroseconds: UInt64?,
        beatMicroseconds: Double
    ) -> InteractionEvidence {
        let humanNotes = Array(human.notes.prefix(32))
        let responseNotes = Array(response.prefix(32))
        guard !humanNotes.isEmpty, !responseNotes.isEmpty else { return .unavailable }

        let pitch = sequenceSimilarity(
            humanNotes.map { Double($0.note) },
            responseNotes.map { Double($0.note) },
            normalizer: 7,
            translationInvariant: true
        )
        let humanIntervals = intervals(humanNotes.map { Double($0.note) })
        let responseIntervals = intervals(responseNotes.map { Double($0.note) })
        let contour = contourSimilarity(humanIntervals, responseIntervals)
        let intervalShape = sequenceSimilarity(
            humanIntervals.map(abs),
            responseIntervals.map(abs),
            normalizer: 7,
            translationInvariant: false
        )
        let rhythm = sequenceSimilarity(
            normalizedGaps(humanNotes.map(\.relativeOnsetBeats)),
            normalizedGaps(responseNotes.map(\.relativeOnsetBeats)),
            normalizer: 0.75,
            translationInvariant: false
        )
        let duration = sequenceSimilarity(
            normalize(humanNotes.map(\.durationBeats)),
            normalize(responseNotes.map(\.durationBeats)),
            normalizer: 0.75,
            translationInvariant: false
        )
        let humanDurationMicroseconds = UInt64(
            max(0, human.durationBeats * max(1, beatMicroseconds)).rounded()
        )
        let humanStartedAt = human.finalizedAtMicroseconds >= humanDurationMicroseconds
            ? human.finalizedAtMicroseconds - humanDurationMicroseconds
            : 0
        let delay = responseEndedAtMicroseconds.map {
            humanStartedAt >= $0
                ? Double(humanStartedAt - $0) / max(1, beatMicroseconds)
                : 0
        } ?? 0
        let temporal = max(0, 1 - delay / 8)
        let confidence = (pitch * 0.12 + contour * 0.28 + intervalShape * 0.23
            + rhythm * 0.25 + duration * 0.07 + temporal * 0.05)
            * min(human.melodyConfidence, human.boundaryConfidence)
        let kind: InteractionKind
        if confidence >= 0.68, rhythm >= 0.58, contour >= 0.58 {
            kind = .imitation
        } else if rhythm >= 0.72, confidence >= 0.48 {
            kind = .rhythmicReply
        } else if contour >= 0.58, confidence >= 0.46 {
            kind = .continuation
        } else if confidence < 0.28 {
            kind = .newProposal
        } else {
            kind = .ambiguous
        }
        return InteractionEvidence(
            kind: kind,
            confidence: confidence,
            pitchContour: contour,
            intervalShape: intervalShape,
            rhythm: rhythm,
            duration: duration,
            responseDelayBeats: delay
        )
    }

    public func similarity(_ left: Motif, _ right: Motif) -> Double {
        let leftNotes = Array(left.notes.prefix(32))
        let rightNotes = Array(right.notes.prefix(32))
        guard !leftNotes.isEmpty, !rightNotes.isEmpty else { return 0 }
        let contour = contourSimilarity(
            intervals(leftNotes.map { Double($0.note) }),
            intervals(rightNotes.map { Double($0.note) })
        )
        let intervalsScore = sequenceSimilarity(
            intervals(leftNotes.map { Double($0.note) }).map(abs),
            intervals(rightNotes.map { Double($0.note) }).map(abs),
            normalizer: 7,
            translationInvariant: false
        )
        let rhythm = sequenceSimilarity(
            normalizedGaps(leftNotes.map(\.relativeOnsetBeats)),
            normalizedGaps(rightNotes.map(\.relativeOnsetBeats)),
            normalizer: 0.75,
            translationInvariant: false
        )
        return contour * 0.4 + intervalsScore * 0.35 + rhythm * 0.25
    }

    public func distance(
        origin: Motif,
        response: [ConversationResponseNote]
    ) -> Double {
        guard !response.isEmpty else { return 0 }
        let synthetic = Motif(
            id: 0,
            notes: response.enumerated().map { index, note in
                MotifNote(
                    sourceNoteID: UInt64(index + 1),
                    note: note.note,
                    velocity: note.velocity,
                    relativeOnsetBeats: note.relativeOnsetBeats,
                    durationBeats: note.durationBeats,
                    restBeforeBeats: 0,
                    accent: Double(note.velocity) / 127,
                    releaseWasInferred: false
                )
            },
            durationBeats: response.map { $0.relativeOnsetBeats + $0.durationBeats }.max() ?? 0,
            boundaryConfidence: 1,
            melodyConfidence: 1,
            features: MotifFeatures(
                pitchIntervals: intervals(response.map { Double($0.note) }).map { Int($0.rounded()) },
                accentedNoteIndices: [],
                restedNoteIndices: [],
                characteristicIntervalIndices: []
            ),
            finalizedAtMicroseconds: 0
        )
        let identity = similarity(origin, synthetic)
        let omission = 1 - Double(min(origin.notes.count, response.count))
            / Double(max(origin.notes.count, response.count))
        return min(1.5, (1 - identity) + omission * 0.35)
    }

    private func intervals(_ values: [Double]) -> [Double] {
        zip(values.dropFirst(), values).map { later, earlier in later - earlier }
    }

    private func normalizedGaps(_ values: [Double]) -> [Double] {
        normalize(intervals(values))
    }

    private func normalize(_ values: [Double]) -> [Double] {
        let positive = values.map { max(0, $0) }
        let scale = positive.filter { $0 > 0.0001 }.sorted()
        guard !scale.isEmpty else { return positive }
        let median = scale[scale.count / 2]
        return positive.map { $0 / max(0.0001, median) }
    }

    private func contourSimilarity(_ left: [Double], _ right: [Double]) -> Double {
        guard !left.isEmpty, !right.isEmpty else { return 0.5 }
        return alignedSimilarity(left, right) { a, b in
            if abs(a) < 0.01, abs(b) < 0.01 { return 1 }
            return direction(a) == direction(b) ? 1 : 0
        }
    }

    private func sequenceSimilarity(
        _ left: [Double],
        _ right: [Double],
        normalizer: Double,
        translationInvariant: Bool
    ) -> Double {
        guard !left.isEmpty, !right.isEmpty else { return left.isEmpty == right.isEmpty ? 1 : 0 }
        let leftValues: [Double]
        let rightValues: [Double]
        if translationInvariant {
            leftValues = left.map { $0 - left[0] }
            rightValues = right.map { $0 - right[0] }
        } else {
            leftValues = left
            rightValues = right
        }
        return alignedSimilarity(leftValues, rightValues) { a, b in
            max(0, 1 - abs(a - b) / max(0.0001, normalizer))
        }
    }

    private func alignedSimilarity(
        _ left: [Double],
        _ right: [Double],
        match: (Double, Double) -> Double
    ) -> Double {
        var table = Array(
            repeating: Array(repeating: 0.0, count: right.count + 1),
            count: left.count + 1
        )
        for i in 1...left.count {
            for j in 1...right.count {
                table[i][j] = max(
                    table[i - 1][j - 1] + match(left[i - 1], right[j - 1]),
                    max(table[i - 1][j] - 0.32, table[i][j - 1] - 0.32)
                )
            }
        }
        return min(1, max(0, table[left.count][right.count] / Double(max(left.count, right.count))))
    }

    private func direction(_ value: Double) -> Int {
        if value > 0.01 { return 1 }
        if value < -0.01 { return -1 }
        return 0
    }
}
