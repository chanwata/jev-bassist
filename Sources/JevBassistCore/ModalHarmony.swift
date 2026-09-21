import Foundation

public enum MusicalMode: String, Codable, CaseIterable, Equatable, Sendable {
    case ionian
    case dorian
    case phrygian
    case lydian
    case mixolydian
    case aeolian
    case locrian

    public var intervals: [Int] {
        switch self {
        case .ionian: return [0, 2, 4, 5, 7, 9, 11]
        case .dorian: return [0, 2, 3, 5, 7, 9, 10]
        case .phrygian: return [0, 1, 3, 5, 7, 8, 10]
        case .lydian: return [0, 2, 4, 6, 7, 9, 11]
        case .mixolydian: return [0, 2, 4, 5, 7, 9, 10]
        case .aeolian: return [0, 2, 3, 5, 7, 8, 10]
        case .locrian: return [0, 1, 3, 5, 6, 8, 10]
        }
    }
}

public struct ModalCenterAssessment: Codable, Equatable, Sendable {
    public let tonalCenterPitchClass: UInt8
    public let confidence: Double
    public let scoreMargin: Double

    public init(tonalCenterPitchClass: UInt8, confidence: Double, scoreMargin: Double) {
        self.tonalCenterPitchClass = tonalCenterPitchClass % 12
        self.confidence = min(1, max(0, confidence))
        self.scoreMargin = max(0, scoreMargin)
    }
}

/// Infers a stable tonal center from one subject, then derives one diatonic
/// triad for each formal development stage. No fixed chord list is required.
public struct ModalHarmonyPlanner: Sendable {
    public let mode: MusicalMode

    public init(mode: MusicalMode) {
        self.mode = mode
    }

    public func inferTonalCenter(from notes: [HumanPhraseNote]) -> UInt8? {
        assessTonalCenter(from: notes)?.tonalCenterPitchClass
    }

    public func assessTonalCenter(from notes: [HumanPhraseNote]) -> ModalCenterAssessment? {
        guard let first = notes.first else { return nil }
        let firstPitchClass = Int(first.note % 12)
        let lastPitchClass = Int(notes.last?.note ?? first.note) % 12
        let modeIntervals = Set(mode.intervals)
        let candidates = (0..<12).map { tonic -> (tonic: Int, score: Double) in
            var score = 0.0
            for (index, note) in notes.enumerated() {
                let relative = (Int(note.note % 12) - tonic + 12) % 12
                let weight = 1 + Double(note.velocity) / 254
                score += modeIntervals.contains(relative) ? weight : -weight * 4
                if relative == 0 {
                    if index == 0 {
                        score += 1
                    } else if index == notes.count - 1 {
                        score += 1.4
                    } else {
                        score += 0.45
                    }
                } else if relative == 7 {
                    score += 0.18
                }
            }
            if tonic == firstPitchClass { score += 4 }
            if tonic == lastPitchClass { score += 1.6 }
            return (tonic, score)
        }
        let ranked = candidates.sorted {
            if $0.score != $1.score { return $0.score > $1.score }
            let left = ($0.tonic - firstPitchClass + 12) % 12
            let right = ($1.tonic - firstPitchClass + 12) % 12
            return left < right
        }
        guard let best = ranked.first else { return nil }
        let runnerUp = ranked.dropFirst().first?.score ?? best.score
        let margin = max(0, best.score - runnerUp)
        let fitCount = notes.filter { note in
            let relative = (Int(note.note % 12) - best.tonic + 12) % 12
            return modeIntervals.contains(relative)
        }.count
        let fit = Double(fitCount) / Double(notes.count)
        let evidence = min(1, Double(notes.count) / 6)
        let confidence = fit * 0.45 + min(1, margin / 5) * 0.4 + evidence * 0.15
        return ModalCenterAssessment(
            tonalCenterPitchClass: UInt8(best.tonic),
            confidence: confidence,
            scoreMargin: margin
        )
    }

    public func chord(
        tonalCenterPitchClass: UInt8,
        stage: MotifDevelopmentStage
    ) -> ChordCandidate {
        let degree: Int
        switch stage {
        case .answer: degree = 4
        case .sequence: degree = 1
        case .inversion: degree = 5
        case .fragmentation: degree = 0
        case .augmentation: degree = 3
        case .diminution: degree = 4
        case .stretto: degree = 4
        case .returnOfSubject: degree = 0
        }
        let intervals = mode.intervals
        let root = intervals[degree]
        let third = intervals[(degree + 2) % 7] + (degree + 2 >= 7 ? 12 : 0) - root
        let fifth = intervals[(degree + 4) % 7] + (degree + 4 >= 7 ? 12 : 0) - root
        let quality: ChordQuality
        switch (third, fifth) {
        case (3, 6): quality = .diminished
        case (3, _): quality = .minor
        default: quality = .major
        }
        return ChordCandidate(
            rootPitchClass: UInt8((Int(tonalCenterPitchClass) + root) % 12),
            quality: quality,
            confidence: 1
        )
    }
}
