import Foundation

public struct MotifNote: Codable, Equatable, Sendable {
    public let sourceNoteID: UInt64
    public let note: UInt8
    public let velocity: UInt8
    public let relativeOnsetBeats: Double
    public let durationBeats: Double
    public let restBeforeBeats: Double
    public let accent: Double
    public let releaseWasInferred: Bool

    public init(
        sourceNoteID: UInt64,
        note: UInt8,
        velocity: UInt8,
        relativeOnsetBeats: Double,
        durationBeats: Double,
        restBeforeBeats: Double,
        accent: Double,
        releaseWasInferred: Bool
    ) {
        self.sourceNoteID = sourceNoteID
        self.note = note
        self.velocity = velocity
        self.relativeOnsetBeats = relativeOnsetBeats
        self.durationBeats = durationBeats
        self.restBeforeBeats = restBeforeBeats
        self.accent = min(1, max(0, accent))
        self.releaseWasInferred = releaseWasInferred
    }
}

public struct MotifFeatures: Codable, Equatable, Sendable {
    public let pitchIntervals: [Int]
    public let accentedNoteIndices: [Int]
    public let restedNoteIndices: [Int]
    public let characteristicIntervalIndices: [Int]

    public init(
        pitchIntervals: [Int],
        accentedNoteIndices: [Int],
        restedNoteIndices: [Int],
        characteristicIntervalIndices: [Int]
    ) {
        self.pitchIntervals = pitchIntervals
        self.accentedNoteIndices = accentedNoteIndices
        self.restedNoteIndices = restedNoteIndices
        self.characteristicIntervalIndices = characteristicIntervalIndices
    }
}

public struct Motif: Codable, Equatable, Sendable {
    public let id: UInt64
    public let notes: [MotifNote]
    public let durationBeats: Double
    public let boundaryConfidence: Double
    public let melodyConfidence: Double
    public let features: MotifFeatures
    public let finalizedAtMicroseconds: UInt64

    public init(
        id: UInt64,
        notes: [MotifNote],
        durationBeats: Double,
        boundaryConfidence: Double,
        melodyConfidence: Double,
        features: MotifFeatures,
        finalizedAtMicroseconds: UInt64
    ) {
        self.id = id
        self.notes = notes
        self.durationBeats = durationBeats
        self.boundaryConfidence = boundaryConfidence
        self.melodyConfidence = melodyConfidence
        self.features = features
        self.finalizedAtMicroseconds = finalizedAtMicroseconds
    }

    public func legacyMemory(ageBars: Int = 0) -> HumanPhraseMemory {
        HumanPhraseMemory(
            notes: notes.map { note in
                HumanPhraseNote(
                    note: note.note,
                    velocity: note.velocity,
                    positionBeats: note.relativeOnsetBeats,
                    durationBeats: note.durationBeats,
                    restBeforeBeats: note.restBeforeBeats,
                    accent: note.accent,
                    releaseWasInferred: note.releaseWasInferred
                )
            },
            ageBars: ageBars
        )
    }
}

public struct MotifMemory: Sendable {
    public let maximumMotifs: Int
    public let minimumMelodyNotes: Int
    public let minimumMelodyConfidence: Double

    private var nextID: UInt64 = 1
    private var storedMotifs: [Motif] = []

    public var motifs: [Motif] {
        storedMotifs
    }

    public init(
        maximumMotifs: Int = 8,
        minimumMelodyNotes: Int = 2,
        minimumMelodyConfidence: Double = 0.55
    ) {
        precondition((1...64).contains(maximumMotifs))
        precondition((1...16).contains(minimumMelodyNotes))
        precondition((0...1).contains(minimumMelodyConfidence))
        self.maximumMotifs = maximumMotifs
        self.minimumMelodyNotes = minimumMelodyNotes
        self.minimumMelodyConfidence = minimumMelodyConfidence
    }

    public mutating func remember(
        _ observation: PhraseObservation,
        musicalStateConfiguration: MusicalStateConfiguration
    ) -> Motif? {
        guard observation.melodyNotes.count >= minimumMelodyNotes,
              observation.melodyConfidence >= minimumMelodyConfidence,
              let first = observation.melodyNotes.first else {
            return nil
        }
        let beatMicroseconds = 60_000_000 / musicalStateConfiguration.tempoBPM
        let maximumVelocity = observation.melodyNotes.map(\.velocity).max() ?? 1
        var previousRelease = first.onsetMicroseconds
        let motifNotes = observation.melodyNotes.map { note in
            let rest = note.onsetMicroseconds > previousRelease
                ? Double(note.onsetMicroseconds - previousRelease) / beatMicroseconds
                : 0
            defer { previousRelease = max(previousRelease, note.releaseMicroseconds) }
            return MotifNote(
                sourceNoteID: note.id,
                note: note.note,
                velocity: note.velocity,
                relativeOnsetBeats: Double(note.onsetMicroseconds - first.onsetMicroseconds)
                    / beatMicroseconds,
                durationBeats: Double(note.durationMicroseconds) / beatMicroseconds,
                restBeforeBeats: rest,
                accent: Double(note.velocity) / Double(maximumVelocity),
                releaseWasInferred: note.release != .observed
            )
        }
        let intervals = zip(motifNotes.dropFirst(), motifNotes).map { later, earlier in
            Int(later.note) - Int(earlier.note)
        }
        let averageAccent = motifNotes.map(\.accent).reduce(0, +) / Double(motifNotes.count)
        let features = MotifFeatures(
            pitchIntervals: intervals,
            accentedNoteIndices: motifNotes.indices.filter {
                motifNotes[$0].accent >= max(0.85, averageAccent + 0.08)
            },
            restedNoteIndices: motifNotes.indices.filter {
                motifNotes[$0].restBeforeBeats >= 0.25
            },
            characteristicIntervalIndices: intervals.indices.filter {
                abs(intervals[$0]) >= 5
            }
        )
        let phraseEnd = observation.melodyNotes.map(\.releaseMicroseconds).max()
            ?? first.releaseMicroseconds
        let motif = Motif(
            id: nextID,
            notes: motifNotes,
            durationBeats: Double(phraseEnd - first.onsetMicroseconds) / beatMicroseconds,
            boundaryConfidence: observation.boundaryConfidence,
            melodyConfidence: observation.melodyConfidence,
            features: features,
            finalizedAtMicroseconds: observation.finalizedAtMicroseconds
        )
        nextID += 1
        storedMotifs.append(motif)
        if storedMotifs.count > maximumMotifs {
            storedMotifs.removeFirst(storedMotifs.count - maximumMotifs)
        }
        return motif
    }
}
