import Foundation

public enum AccompanimentStyle: String, Codable, CaseIterable, Equatable, Sendable {
    case bass
    case ambient
    case memory
    case fugue
}

public struct HumanPhraseNote: Codable, Equatable, Sendable {
    public let note: UInt8
    public let velocity: UInt8
    public let positionBeats: Double
    public let durationBeats: Double
    public let restBeforeBeats: Double
    public let accent: Double
    public let releaseWasInferred: Bool

    public init(
        note: UInt8,
        velocity: UInt8,
        positionBeats: Double,
        durationBeats: Double = 0.5,
        restBeforeBeats: Double = 0,
        accent: Double = 1,
        releaseWasInferred: Bool = false
    ) {
        self.note = note
        self.velocity = velocity
        self.positionBeats = positionBeats
        self.durationBeats = durationBeats
        self.restBeforeBeats = restBeforeBeats
        self.accent = accent
        self.releaseWasInferred = releaseWasInferred
    }

    private enum CodingKeys: String, CodingKey {
        case note
        case velocity
        case positionBeats
        case durationBeats
        case restBeforeBeats
        case accent
        case releaseWasInferred
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            note: try container.decode(UInt8.self, forKey: .note),
            velocity: try container.decode(UInt8.self, forKey: .velocity),
            positionBeats: try container.decode(Double.self, forKey: .positionBeats),
            durationBeats: try container.decodeIfPresent(
                Double.self,
                forKey: .durationBeats
            ) ?? 0.5,
            restBeforeBeats: try container.decodeIfPresent(
                Double.self,
                forKey: .restBeforeBeats
            ) ?? 0,
            accent: try container.decodeIfPresent(Double.self, forKey: .accent) ?? 1,
            releaseWasInferred: try container.decodeIfPresent(
                Bool.self,
                forKey: .releaseWasInferred
            ) ?? false
        )
    }
}

public struct HumanPhraseMemory: Codable, Equatable, Sendable {
    public let notes: [HumanPhraseNote]
    public let ageBars: Int

    public init(notes: [HumanPhraseNote], ageBars: Int = 0) {
        self.notes = notes
        self.ageBars = ageBars
    }
}

public enum MotifDevelopmentStage: String, Codable, CaseIterable, Equatable, Sendable {
    case answer
    case sequence
    case inversion
    case fragmentation
    case augmentation
    case diminution
    case stretto
    case returnOfSubject = "return"

    public static func stage(at cyclePosition: Int) -> MotifDevelopmentStage {
        let stages = MotifDevelopmentStage.allCases
        let normalized = (cyclePosition % stages.count + stages.count) % stages.count
        return stages[normalized]
    }
}

public struct EnsembleExpression: Codable, Equatable, Sendable {
    public let memory: Double
    public let tension: Double
    public let activity: Double
    public let resonance: Double

    public init(memory: Double, tension: Double, activity: Double, resonance: Double) {
        self.memory = min(1, max(0, memory))
        self.tension = min(1, max(0, tension))
        self.activity = min(1, max(0, activity))
        self.resonance = min(1, max(0, resonance))
    }

    public static let quiet = EnsembleExpression(
        memory: 0,
        tension: 0.15,
        activity: 0,
        resonance: 0.2
    )
}

public enum BassActivity: String, Codable, CaseIterable, Sendable {
    case rest
    case sparse
    case normal
    case busy
}

public enum BassRelationship: String, Codable, CaseIterable, Sendable {
    case follow
    case contrast
    case hold
}

public enum BassMotion: String, Codable, CaseIterable, Sendable {
    case root
    case step
    case approach
    case leap
}

/// A bounded musical decision. Concrete note choice and timing stay in the
/// deterministic phrase generator.
public struct BassDecision: Codable, Equatable, Sendable {
    public let activity: BassActivity
    public let relationship: BassRelationship
    public let motion: BassMotion
    public let fill: Bool
    public let confidence: Double

    public init(
        activity: BassActivity,
        relationship: BassRelationship,
        motion: BassMotion,
        fill: Bool,
        confidence: Double
    ) {
        self.activity = activity
        self.relationship = relationship
        self.motion = motion
        self.fill = fill
        self.confidence = confidence
    }
}

public struct BassDecisionInput: Codable, Equatable, Sendable {
    public let state: MusicalState
    public let chord: ChordCandidate?
    public let nextChord: ChordCandidate?
    public let style: AccompanimentStyle
    public let developmentStage: MotifDevelopmentStage?
    public let mode: MusicalMode?
    public let tonalCenterPitchClass: UInt8?
    public let isHeldChord: Bool
    public let targetBarIndex: Int

    public init(
        state: MusicalState,
        chord: ChordCandidate?,
        nextChord: ChordCandidate? = nil,
        style: AccompanimentStyle = .bass,
        developmentStage: MotifDevelopmentStage? = nil,
        mode: MusicalMode? = nil,
        tonalCenterPitchClass: UInt8? = nil,
        isHeldChord: Bool,
        targetBarIndex: Int
    ) {
        self.state = state
        self.chord = chord
        self.nextChord = nextChord
        self.style = style
        self.developmentStage = developmentStage
        self.mode = mode
        self.tonalCenterPitchClass = tonalCenterPitchClass
        self.isHeldChord = isHeldChord
        self.targetBarIndex = targetBarIndex
    }

    private enum CodingKeys: String, CodingKey {
        case state
        case chord
        case nextChord
        case style
        case developmentStage
        case mode
        case tonalCenterPitchClass
        case isHeldChord
        case targetBarIndex
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        state = try container.decode(MusicalState.self, forKey: .state)
        chord = try container.decodeIfPresent(ChordCandidate.self, forKey: .chord)
        nextChord = try container.decodeIfPresent(ChordCandidate.self, forKey: .nextChord)
        style = try container.decodeIfPresent(AccompanimentStyle.self, forKey: .style) ?? .bass
        developmentStage = try container.decodeIfPresent(
            MotifDevelopmentStage.self,
            forKey: .developmentStage
        )
        mode = try container.decodeIfPresent(MusicalMode.self, forKey: .mode)
        tonalCenterPitchClass = try container.decodeIfPresent(
            UInt8.self,
            forKey: .tonalCenterPitchClass
        )
        isHeldChord = try container.decode(Bool.self, forKey: .isHeldChord)
        targetBarIndex = try container.decode(Int.self, forKey: .targetBarIndex)
    }
}

public enum BassDecisionSource: String, Codable, Equatable, Sendable {
    case rules
    case jev
    case fallback
}

public struct BassDecisionResolution: Codable, Equatable, Sendable {
    public let decision: BassDecision
    public let source: BassDecisionSource

    public init(decision: BassDecision, source: BassDecisionSource) {
        self.decision = decision
        self.source = source
    }
}

public protocol BassDecisionProvider: Sendable {
    /// Starts any work needed for a future bar. Implementations must return
    /// immediately; live MIDI scheduling never waits for this work.
    func prepare(_ input: BassDecisionInput)

    func decision(for input: BassDecisionInput) -> BassDecision

    /// Resolves an already prepared decision without waiting. Remote
    /// implementations return a deterministic local fallback when no result is
    /// ready at the boundary.
    func resolution(for input: BassDecisionInput) -> BassDecisionResolution

    func cancelPendingDecisions()
}

public extension BassDecisionProvider {
    func prepare(_ input: BassDecisionInput) {}

    func resolution(for input: BassDecisionInput) -> BassDecisionResolution {
        BassDecisionResolution(decision: decision(for: input), source: .rules)
    }

    func cancelPendingDecisions() {}
}

/// A deliberately small baseline policy. It leaves space when the player is
/// dense and becomes only modestly more active during short silences.
public struct RuleBasedBassDecisionProvider: BassDecisionProvider {
    public init() {}

    public func decision(for input: BassDecisionInput) -> BassDecision {
        guard input.chord != nil else {
            return BassDecision(
                activity: .rest,
                relationship: .hold,
                motion: .root,
                fill: false,
                confidence: 1
            )
        }

        let density = input.state.noteDensityPerBeat
        if input.state.noteOnCount == 0 {
            return BassDecision(
                activity: .normal,
                relationship: .hold,
                motion: .step,
                fill: input.targetBarIndex.isMultiple(of: 4),
                confidence: input.isHeldChord ? 0.72 : 0.82
            )
        }
        if density >= 1.5 {
            return BassDecision(
                activity: .sparse,
                relationship: .contrast,
                motion: .root,
                fill: false,
                confidence: 0.9
            )
        }
        if density <= 0.75 {
            return BassDecision(
                activity: .normal,
                relationship: .follow,
                motion: .root,
                fill: input.targetBarIndex.isMultiple(of: 4),
                confidence: 0.86
            )
        }
        return BassDecision(
            activity: .sparse,
            relationship: .follow,
            motion: .leap,
            fill: false,
            confidence: 0.8
        )
    }
}

public enum ScheduledMIDIMessageKind: String, Codable, Equatable, Sendable {
    case noteOn
    case noteOff

    fileprivate var sortOrder: Int {
        switch self {
        case .noteOff:
            return 0
        case .noteOn:
            return 1
        }
    }
}

public struct ScheduledMIDIMessage: Codable, Equatable, Sendable {
    public let offsetMicroseconds: UInt64
    public let kind: ScheduledMIDIMessageKind
    public let channel: UInt8
    public let note: UInt8
    public let velocity: UInt8

    public init(
        offsetMicroseconds: UInt64,
        kind: ScheduledMIDIMessageKind,
        channel: UInt8,
        note: UInt8,
        velocity: UInt8
    ) {
        self.offsetMicroseconds = offsetMicroseconds
        self.kind = kind
        self.channel = channel
        self.note = note
        self.velocity = velocity
    }

    public var bytes: [UInt8] {
        let statusBase: UInt8 = kind == .noteOn ? 0x90 : 0x80
        return [statusBase | ((channel - 1) & 0x0F), note, velocity]
    }
}

public struct BassPhrase: Codable, Equatable, Sendable {
    public let barIndex: Int
    public let startMicroseconds: UInt64
    public let endMicroseconds: UInt64
    public let messages: [ScheduledMIDIMessage]

    public init(
        barIndex: Int,
        startMicroseconds: UInt64,
        endMicroseconds: UInt64,
        messages: [ScheduledMIDIMessage]
    ) {
        self.barIndex = barIndex
        self.startMicroseconds = startMicroseconds
        self.endMicroseconds = endMicroseconds
        self.messages = messages
    }
}

public struct BassPhraseGenerator: Sendable {
    public let outputChannel: UInt8

    public init(outputChannel: UInt8) {
        precondition((1...16).contains(outputChannel))
        self.outputChannel = outputChannel
    }

    public func generate(
        decision: BassDecision,
        chord: ChordCandidate?,
        barIndex: Int,
        startMicroseconds: UInt64,
        musicalStateConfiguration: MusicalStateConfiguration
    ) -> BassPhrase {
        generate(
            decision: decision,
            chord: chord,
            barIndex: barIndex,
            startMicroseconds: startMicroseconds,
            musicalStateConfiguration: musicalStateConfiguration,
            previousBassNote: nil,
            humanAverageVelocity: nil
        )
    }

    /// Generates a deterministic pocket while carrying just enough context to
    /// avoid octave jumps and to sit underneath the player's dynamics.
    public func generate(
        decision: BassDecision,
        chord: ChordCandidate?,
        barIndex: Int,
        startMicroseconds: UInt64,
        musicalStateConfiguration: MusicalStateConfiguration,
        previousBassNote: UInt8?,
        humanAverageVelocity: Double?,
        nextChord: ChordCandidate? = nil
    ) -> BassPhrase {
        let barLength = musicalStateConfiguration.boundaryMicroseconds(
            afterBeats: musicalStateConfiguration.beatsPerBar
        )
        let endMicroseconds = startMicroseconds + barLength
        guard decision.activity != .rest, let chord else {
            return BassPhrase(
                barIndex: barIndex,
                startMicroseconds: startMicroseconds,
                endMicroseconds: endMicroseconds,
                messages: []
            )
        }

        let beatLength = 60_000_000 / musicalStateConfiguration.tempoBPM
        let positions = onsetPositions(
            decision: decision,
            barIndex: barIndex,
            beatsPerBar: musicalStateConfiguration.beatsPerBar
        )
        let notes = notePattern(
            decision: decision,
            chord: chord,
            count: positions.count,
            previousBassNote: previousBassNote,
            nextChord: nextChord
        )
        var messages: [ScheduledMIDIMessage] = []

        for (index, pair) in zip(positions, notes).enumerated() {
            let (position, note) = pair
            let relativeOnset = UInt64((beatLength * position).rounded())
            let onset = startMicroseconds + relativeOnset
            let nextPosition = index + 1 < positions.count
                ? positions[index + 1]
                : Double(musicalStateConfiguration.beatsPerBar)
            let available = max(0.08, nextPosition - position)
            let articulationBeats = durationRatio(
                for: decision,
                availableBeats: available,
                isLast: index == positions.count - 1
            )
            let duration = UInt64((beatLength * articulationBeats).rounded())
            let noteOff = min(onset + duration, endMicroseconds - 1)
            messages.append(
                ScheduledMIDIMessage(
                    offsetMicroseconds: onset,
                    kind: .noteOn,
                    channel: outputChannel,
                    note: note,
                    velocity: velocity(
                        for: decision.activity,
                        position: position,
                        humanAverageVelocity: humanAverageVelocity,
                        isFill: decision.fill && index == positions.count - 1
                    )
                )
            )
            messages.append(
                ScheduledMIDIMessage(
                    offsetMicroseconds: noteOff,
                    kind: .noteOff,
                    channel: outputChannel,
                    note: note,
                    velocity: 0
                )
            )
        }

        messages.sort {
            if $0.offsetMicroseconds != $1.offsetMicroseconds {
                return $0.offsetMicroseconds < $1.offsetMicroseconds
            }
            if $0.kind.sortOrder != $1.kind.sortOrder {
                return $0.kind.sortOrder < $1.kind.sortOrder
            }
            return $0.note < $1.note
        }
        return BassPhrase(
            barIndex: barIndex,
            startMicroseconds: startMicroseconds,
            endMicroseconds: endMicroseconds,
            messages: messages
        )
    }

    private func onsetPositions(
        decision: BassDecision,
        barIndex: Int,
        beatsPerBar: Int
    ) -> [Double] {
        guard beatsPerBar == 4 else {
            return regularOnsetPositions(
                activity: decision.activity,
                beatsPerBar: beatsPerBar
            )
        }

        let positions: [Double]
        switch decision.activity {
        case .rest:
            positions = []
        case .sparse:
            switch decision.relationship {
            case .follow:
                positions = barIndex.isMultiple(of: 2) ? [0, 2.5] : [0, 3]
            case .contrast:
                positions = [0, 2]
            case .hold:
                positions = [0]
            }
        case .normal:
            switch decision.relationship {
            case .follow:
                positions = barIndex.isMultiple(of: 2)
                    ? [0, 1.5, 2, 3.5]
                    : [0, 1, 2.5, 3]
            case .contrast:
                positions = [0, 1.5, 2.75]
            case .hold:
                positions = [0, 2, 3]
            }
        case .busy:
            switch decision.relationship {
            case .follow:
                positions = [0, 0.5, 1.5, 2, 2.5, 3.5]
            case .contrast:
                positions = [0, 0.75, 2, 2.75, 3.5]
            case .hold:
                positions = [0, 1, 2, 3]
            }
        }

        guard decision.fill, let last = positions.last, last < 3.5 else {
            return positions
        }
        return positions + [3.5]
    }

    private func regularOnsetPositions(
        activity: BassActivity,
        beatsPerBar: Int
    ) -> [Double] {
        switch activity {
        case .rest:
            return []
        case .sparse:
            return beatsPerBar >= 3 ? [0, Double(beatsPerBar) / 2] : [0]
        case .normal:
            return (0..<beatsPerBar).map(Double.init)
        case .busy:
            return (0..<(beatsPerBar * 2)).map { Double($0) / 2 }
        }
    }

    private func notePattern(
        decision: BassDecision,
        chord: ChordCandidate,
        count: Int,
        previousBassNote: UInt8?,
        nextChord: ChordCandidate?
    ) -> [UInt8] {
        let thirdInterval = chord.quality == .major ? 4 : 3
        let fifthInterval = chord.quality == .diminished ? 6 : 7
        let sixthInterval = chord.quality == .minor ? 8 : 9
        let intervals: [Int]

        if decision.relationship == .hold {
            intervals = [0]
        } else {
            switch decision.motion {
            case .root:
                intervals = [0, 0, fifthInterval, 0]
            case .step:
                intervals = [0, 2, thirdInterval, 5, fifthInterval, sixthInterval]
            case .approach:
                intervals = [0, fifthInterval, 0, fifthInterval]
            case .leap:
                intervals = [0, fifthInterval, thirdInterval, fifthInterval]
            }
        }

        guard count > 0 else {
            return []
        }
        var pitchClasses = (0..<count).map {
            Int(chord.rootPitchClass) + intervals[$0 % intervals.count]
        }
        if (decision.fill || decision.motion == .approach), let nextChord {
            // A chromatic approach only sounds intentional when its resolution
            // target is known. The following bar begins on nextChord's root.
            pitchClasses[pitchClasses.count - 1] = Int(nextChord.rootPitchClass) - 1
        }

        var reference = previousBassNote
        return pitchClasses.map { pitchClass in
            let note = bassNote(pitchClass: pitchClass, near: reference)
            reference = note
            return note
        }
    }

    private func bassNote(pitchClass: Int, near reference: UInt8?) -> UInt8 {
        let normalized = (pitchClass % 12 + 12) % 12
        let candidates = (36...48).filter { $0 % 12 == normalized }
        guard let reference else {
            return UInt8(candidates.first ?? 36)
        }
        return UInt8(
            candidates.min {
                let leftDistance = abs($0 - Int(reference))
                let rightDistance = abs($1 - Int(reference))
                if leftDistance != rightDistance {
                    return leftDistance < rightDistance
                }
                return $0 < $1
            } ?? 36
        )
    }

    private func durationRatio(
        for decision: BassDecision,
        availableBeats: Double,
        isLast: Bool
    ) -> Double {
        let articulation: Double
        switch decision.relationship {
        case .follow:
            articulation = decision.activity == .busy ? 0.34 : 0.68
        case .contrast:
            articulation = 0.42
        case .hold:
            articulation = 0.88
        }
        let fillLimit = decision.fill && isLast ? 0.32 : articulation
        return max(0.08, min(fillLimit, availableBeats - 0.04))
    }

    private func velocity(
        for activity: BassActivity,
        position: Double,
        humanAverageVelocity: Double?,
        isFill: Bool
    ) -> UInt8 {
        let defaultVelocity: Double
        switch activity {
        case .rest:
            defaultVelocity = 0
        case .sparse:
            defaultVelocity = 68
        case .normal:
            defaultVelocity = 74
        case .busy:
            defaultVelocity = 78
        }
        let followedVelocity = humanAverageVelocity.map {
            min(82, max(56, $0 * 0.55 + 18))
        } ?? defaultVelocity
        let isDownbeat = position == 0
        let isOffbeat = position.truncatingRemainder(dividingBy: 1) != 0
        let accent = isDownbeat ? 6.0 : (isOffbeat ? -4.0 : 0)
        let fillAccent = isFill ? 2.0 : 0
        return UInt8(min(100, max(1, followedVelocity + accent + fillAccent)).rounded())
    }
}

/// Renders Jev's bounded decision as a slow pad-like response. Activity changes
/// voicing width rather than attack rate, so even a busy decision stays airy.
public struct AmbientPhraseGenerator: Sendable {
    public let outputChannel: UInt8

    public init(outputChannel: UInt8) {
        precondition((1...16).contains(outputChannel))
        self.outputChannel = outputChannel
    }

    public func generate(
        decision: BassDecision,
        chord: ChordCandidate?,
        barIndex: Int,
        startMicroseconds: UInt64,
        musicalStateConfiguration: MusicalStateConfiguration,
        previousNotes: [UInt8],
        humanAverageVelocity: Double?
    ) -> BassPhrase {
        let barLength = musicalStateConfiguration.boundaryMicroseconds(
            afterBeats: musicalStateConfiguration.beatsPerBar
        )
        let endMicroseconds = startMicroseconds + barLength
        guard decision.activity != .rest, let chord else {
            return BassPhrase(
                barIndex: barIndex,
                startMicroseconds: startMicroseconds,
                endMicroseconds: endMicroseconds,
                messages: []
            )
        }

        let beatLength = 60_000_000 / musicalStateConfiguration.tempoBPM
        let onsetBeats: Double
        switch decision.relationship {
        case .hold:
            onsetBeats = 0
        case .follow:
            onsetBeats = barIndex.isMultiple(of: 2) ? 0.25 : 0.5
        case .contrast:
            onsetBeats = min(1, Double(musicalStateConfiguration.beatsPerBar) / 2)
        }
        let releaseGapBeats = decision.fill ? 0.5 : 0.1
        let onset = startMicroseconds + UInt64((beatLength * onsetBeats).rounded())
        let lastUsableBeat = max(0.1, Double(musicalStateConfiguration.beatsPerBar) - 0.05)
        let releaseBeat = min(
            lastUsableBeat,
            max(onsetBeats + 0.1, Double(musicalStateConfiguration.beatsPerBar) - releaseGapBeats)
        )
        let release = startMicroseconds + UInt64((beatLength * releaseBeat).rounded())
        let notes = voicing(
            decision: decision,
            chord: chord,
            previousNotes: previousNotes
        )
        var messages: [ScheduledMIDIMessage] = []
        for (voiceIndex, note) in notes.enumerated() {
            messages.append(
                ScheduledMIDIMessage(
                    offsetMicroseconds: onset,
                    kind: .noteOn,
                    channel: outputChannel,
                    note: note,
                    velocity: velocity(
                        activity: decision.activity,
                        voiceIndex: voiceIndex,
                        humanAverageVelocity: humanAverageVelocity
                    )
                )
            )
            messages.append(
                ScheduledMIDIMessage(
                    offsetMicroseconds: min(release, endMicroseconds - 1),
                    kind: .noteOff,
                    channel: outputChannel,
                    note: note,
                    velocity: 0
                )
            )
        }
        messages.sort {
            if $0.offsetMicroseconds != $1.offsetMicroseconds {
                return $0.offsetMicroseconds < $1.offsetMicroseconds
            }
            if $0.kind.sortOrder != $1.kind.sortOrder {
                return $0.kind.sortOrder < $1.kind.sortOrder
            }
            return $0.note < $1.note
        }
        return BassPhrase(
            barIndex: barIndex,
            startMicroseconds: startMicroseconds,
            endMicroseconds: endMicroseconds,
            messages: messages
        )
    }

    private func voicing(
        decision: BassDecision,
        chord: ChordCandidate,
        previousNotes: [UInt8]
    ) -> [UInt8] {
        let voiceCount: Int
        switch decision.activity {
        case .rest:
            return []
        case .sparse:
            voiceCount = 1
        case .normal:
            voiceCount = 2
        case .busy:
            voiceCount = 3
        }

        let third = chord.quality == .major ? 4 : 3
        let fifth = chord.quality == .diminished ? 6 : 7
        let intervals: [Int]
        switch decision.motion {
        case .root:
            intervals = [0, fifth, third]
        case .step:
            intervals = [third, fifth, 0]
        case .approach:
            intervals = [fifth, third, 0]
        case .leap:
            intervals = [0, third, fifth]
        }

        let anchors = [52, 60, 67]
        return Array(intervals.prefix(voiceCount)).enumerated().map { index, interval in
            let pitchClass = (Int(chord.rootPitchClass) + interval) % 12
            let reference = index < previousNotes.count
                ? Int(previousNotes[index])
                : anchors[index]
            return UInt8(nearestNote(pitchClass: pitchClass, to: reference))
        }.sorted()
    }

    private func nearestNote(pitchClass: Int, to reference: Int) -> Int {
        let candidates = (48...72).filter { $0 % 12 == pitchClass }
        return candidates.min {
            let left = abs($0 - reference)
            let right = abs($1 - reference)
            return left == right ? $0 < $1 : left < right
        } ?? 60
    }

    private func velocity(
        activity: BassActivity,
        voiceIndex: Int,
        humanAverageVelocity: Double?
    ) -> UInt8 {
        let defaultVelocity: Double
        switch activity {
        case .rest:
            defaultVelocity = 0
        case .sparse:
            defaultVelocity = 44
        case .normal:
            defaultVelocity = 40
        case .busy:
            defaultVelocity = 36
        }
        let followed = humanAverageVelocity.map {
            min(52, max(30, $0 * 0.25 + 18))
        } ?? defaultVelocity
        return UInt8(min(56, max(1, followed - Double(voiceIndex * 3))).rounded())
    }
}

public struct MemoryPhraseResult: Equatable, Sendable {
    public let phrase: BassPhrase
    public let expression: EnsembleExpression

    public init(phrase: BassPhrase, expression: EnsembleExpression) {
        self.phrase = phrase
        self.expression = expression
    }
}

/// Turns a recently played human motif into a sparse, delayed response. The
/// contour and relative timing remain recognizable while Jev's bounded axes
/// select how much is recalled, how long the answer waits, and how it mutates.
public struct MemoryPhraseGenerator: Sendable {
    public let outputChannel: UInt8

    public init(outputChannel: UInt8) {
        precondition((1...16).contains(outputChannel))
        self.outputChannel = outputChannel
    }

    public func generate(
        decision: BassDecision,
        chord: ChordCandidate?,
        barIndex: Int,
        startMicroseconds: UInt64,
        musicalStateConfiguration: MusicalStateConfiguration,
        memory: HumanPhraseMemory?,
        previousNotes: [UInt8],
        humanAverageVelocity: Double?
    ) -> MemoryPhraseResult {
        let barLength = musicalStateConfiguration.boundaryMicroseconds(
            afterBeats: musicalStateConfiguration.beatsPerBar
        )
        let endMicroseconds = startMicroseconds + barLength
        let empty = BassPhrase(
            barIndex: barIndex,
            startMicroseconds: startMicroseconds,
            endMicroseconds: endMicroseconds,
            messages: []
        )
        guard decision.activity != .rest,
              let memory,
              !memory.notes.isEmpty,
              memory.ageBars <= 2 else {
            return MemoryPhraseResult(phrase: empty, expression: .quiet)
        }

        let selected = selectedNotes(from: memory.notes, activity: decision.activity)
        guard !selected.isEmpty else {
            return MemoryPhraseResult(phrase: empty, expression: .quiet)
        }
        let transformed = transformedNotes(
            selected,
            motion: decision.motion,
            chord: chord,
            previousNotes: previousNotes
        )
        let beatsPerBar = Double(musicalStateConfiguration.beatsPerBar)
        let onsetBeat = responseOnset(
            relationship: decision.relationship,
            beatsPerBar: beatsPerBar,
            sourceLastBeat: memory.notes.last?.positionBeats ?? 0
        )
        let releaseGap = decision.fill ? 0.7 : 0.12
        let finalReleaseBeat = max(onsetBeat + 0.15, beatsPerBar - releaseGap)
        let relativePositions = stretchedPositions(
            selected,
            onsetBeat: onsetBeat,
            latestBeat: finalReleaseBeat - 0.12
        )
        let beatLength = 60_000_000 / musicalStateConfiguration.tempoBPM
        var messages: [ScheduledMIDIMessage] = []

        for index in transformed.indices {
            let position = relativePositions[index]
            let onset = startMicroseconds + UInt64((beatLength * position).rounded())
            let nextPosition = index + 1 < relativePositions.count
                ? relativePositions[index + 1]
                : finalReleaseBeat
            let releaseBeat = min(
                finalReleaseBeat,
                max(position + 0.35, nextPosition + 0.35)
            )
            let release = min(
                startMicroseconds + UInt64((beatLength * releaseBeat).rounded()),
                endMicroseconds - 1
            )
            let velocity = responseVelocity(
                sourceVelocity: selected[index].velocity,
                humanAverageVelocity: humanAverageVelocity,
                index: index,
                ageBars: memory.ageBars
            )
            messages.append(
                ScheduledMIDIMessage(
                    offsetMicroseconds: onset,
                    kind: .noteOn,
                    channel: outputChannel,
                    note: transformed[index],
                    velocity: velocity
                )
            )
            messages.append(
                ScheduledMIDIMessage(
                    offsetMicroseconds: release,
                    kind: .noteOff,
                    channel: outputChannel,
                    note: transformed[index],
                    velocity: 0
                )
            )
        }
        messages.sort {
            if $0.offsetMicroseconds != $1.offsetMicroseconds {
                return $0.offsetMicroseconds < $1.offsetMicroseconds
            }
            if $0.kind.sortOrder != $1.kind.sortOrder {
                return $0.kind.sortOrder < $1.kind.sortOrder
            }
            return $0.note < $1.note
        }

        let phrase = BassPhrase(
            barIndex: barIndex,
            startMicroseconds: startMicroseconds,
            endMicroseconds: endMicroseconds,
            messages: messages
        )
        return MemoryPhraseResult(
            phrase: phrase,
            expression: expression(
                decision: decision,
                chord: chord,
                sourceCount: memory.notes.count,
                responseNotes: transformed,
                ageBars: memory.ageBars,
                onsetBeat: onsetBeat,
                releaseBeat: finalReleaseBeat,
                beatsPerBar: beatsPerBar
            )
        )
    }

    private func selectedNotes(
        from notes: [HumanPhraseNote],
        activity: BassActivity
    ) -> [HumanPhraseNote] {
        let ordered = notes.sorted { $0.positionBeats < $1.positionBeats }
        let desired: Int
        switch activity {
        case .rest:
            return []
        case .sparse:
            desired = 1
        case .normal:
            desired = min(3, ordered.count)
        case .busy:
            desired = min(4, ordered.count)
        }
        guard desired > 1 else {
            return [ordered[ordered.count - 1]]
        }
        return (0..<desired).map { index in
            let sourceIndex = Int(
                (Double(index) * Double(ordered.count - 1) / Double(desired - 1)).rounded()
            )
            return ordered[sourceIndex]
        }
    }

    private func transformedNotes(
        _ notes: [HumanPhraseNote],
        motion: BassMotion,
        chord: ChordCandidate?,
        previousNotes: [UInt8]
    ) -> [UInt8] {
        let source = motion == .approach ? Array(notes.reversed()) : notes
        let sourceAnchor = Int(source[0].note)
        let targetPitchClass = Int(chord?.rootPitchClass ?? (source[0].note % 12))
        let reference = Int(previousNotes.last ?? 60)
        let targetAnchor = nearestNote(pitchClass: targetPitchClass, to: reference)

        return source.enumerated().map { index, sourceNote in
            let rawInterval = Int(sourceNote.note) - sourceAnchor
            let interval: Int
            switch motion {
            case .root, .approach:
                interval = rawInterval
            case .step:
                interval = rawInterval.signum() * min(abs(rawInterval), 5)
            case .leap:
                let expansion = index.isMultiple(of: 2) ? 0 : (rawInterval >= 0 ? 7 : -7)
                interval = rawInterval + expansion
            }
            return UInt8(foldToResponseRegister(targetAnchor + interval))
        }
    }

    private func responseOnset(
        relationship: BassRelationship,
        beatsPerBar: Double,
        sourceLastBeat: Double
    ) -> Double {
        let base: Double
        switch relationship {
        case .follow:
            base = 0.75
        case .contrast:
            base = min(1.75, beatsPerBar * 0.5)
        case .hold:
            base = 0.5
        }
        let latePhraseBreath = sourceLastBeat > beatsPerBar * 0.7 ? 0.25 : 0
        return min(max(0, beatsPerBar - 0.75), base + latePhraseBreath)
    }

    private func stretchedPositions(
        _ notes: [HumanPhraseNote],
        onsetBeat: Double,
        latestBeat: Double
    ) -> [Double] {
        guard notes.count > 1 else {
            return [onsetBeat]
        }
        let first = notes[0].positionBeats
        let sourceSpan = max(0.25, notes[notes.count - 1].positionBeats - first)
        let available = max(0.25, latestBeat - onsetBeat)
        let scale = min(2, available / sourceSpan)
        return notes.map {
            let stretched = onsetBeat + ($0.positionBeats - first) * scale
            return min(latestBeat, (stretched * 4).rounded() / 4)
        }
    }

    private func responseVelocity(
        sourceVelocity: UInt8,
        humanAverageVelocity: Double?,
        index: Int,
        ageBars: Int
    ) -> UInt8 {
        let source = humanAverageVelocity ?? Double(sourceVelocity)
        let aged = source * 0.28 + 17 - Double(ageBars * 5) - Double(index * 2)
        return UInt8(min(52, max(22, aged)).rounded())
    }

    private func expression(
        decision: BassDecision,
        chord: ChordCandidate?,
        sourceCount: Int,
        responseNotes: [UInt8],
        ageBars: Int,
        onsetBeat: Double,
        releaseBeat: Double,
        beatsPerBar: Double
    ) -> EnsembleExpression {
        let memory = max(0, 1 - Double(ageBars) * 0.3)
            * min(1, 0.45 + Double(sourceCount) * 0.11)
        let decisionActivity: Double
        switch decision.activity {
        case .rest: decisionActivity = 0
        case .sparse: decisionActivity = 0.28
        case .normal: decisionActivity = 0.56
        case .busy: decisionActivity = 0.78
        }
        let activity = min(1, decisionActivity + Double(sourceCount) * 0.035)
        let harmonicTension: Double
        switch chord?.quality {
        case .some(.diminished): harmonicTension = 0.9
        case .some(.minor): harmonicTension = 0.52
        case .some(.major): harmonicTension = 0.28
        case .none: harmonicTension = 0.62
        }
        let motionTension: Double
        switch decision.motion {
        case .root: motionTension = 0.15
        case .step: motionTension = 0.32
        case .approach: motionTension = 0.72
        case .leap: motionTension = 0.58
        }
        let spread = responseNotes.isEmpty
            ? 0
            : Double(Int(responseNotes.max()!) - Int(responseNotes.min()!)) / 24
        let tension = harmonicTension * 0.55 + motionTension * 0.35 + spread * 0.1
        let resonance = memory * min(1, max(0, releaseBeat - onsetBeat) / beatsPerBar)
        return EnsembleExpression(
            memory: memory,
            tension: tension,
            activity: activity,
            resonance: resonance
        )
    }

    private func nearestNote(pitchClass: Int, to reference: Int) -> Int {
        let normalized = (pitchClass % 12 + 12) % 12
        let candidates = (48...72).filter { $0 % 12 == normalized }
        return candidates.min {
            let left = abs($0 - reference)
            let right = abs($1 - reference)
            return left == right ? $0 < $1 : left < right
        } ?? 60
    }

    private func foldToResponseRegister(_ note: Int) -> Int {
        var folded = note
        while folded < 48 { folded += 12 }
        while folded > 72 { folded -= 12 }
        return folded
    }
}

/// Develops one locked human subject across an eight-bar imitative form. New
/// material cannot replace the subject until its explicit return. All concrete
/// note selection, transformation, and scheduling remain deterministic.
public struct FuguePhraseGenerator: Sendable {
    public let outputChannel: UInt8

    public init(outputChannel: UInt8) {
        precondition((1...16).contains(outputChannel))
        self.outputChannel = outputChannel
    }

    public func generate(
        decision: BassDecision,
        chord: ChordCandidate?,
        nextChord: ChordCandidate?,
        barIndex: Int,
        startMicroseconds: UInt64,
        musicalStateConfiguration: MusicalStateConfiguration,
        memory: HumanPhraseMemory?,
        previousNotes: [UInt8],
        humanAverageVelocity: Double?,
        stage: MotifDevelopmentStage = .answer,
        tonalCenterPitchClass: UInt8? = nil
    ) -> MemoryPhraseResult {
        let barLength = musicalStateConfiguration.boundaryMicroseconds(
            afterBeats: musicalStateConfiguration.beatsPerBar
        )
        let endMicroseconds = startMicroseconds + barLength
        let empty = BassPhrase(
            barIndex: barIndex,
            startMicroseconds: startMicroseconds,
            endMicroseconds: endMicroseconds,
            messages: []
        )
        guard decision.activity != .rest || stage == .returnOfSubject,
              let memory,
              !memory.notes.isEmpty else {
            return MemoryPhraseResult(phrase: empty, expression: .quiet)
        }

        let subject = selectedSubject(
            from: memory.notes,
            activity: decision.activity,
            stage: stage,
            barIndex: barIndex
        )
        let rhythm = subjectRhythm(
            subject,
            relationship: decision.relationship,
            stage: stage,
            beatsPerBar: Double(musicalStateConfiguration.beatsPerBar)
        )
        let subjectNotes = tonalAnswer(
            subject,
            motion: decision.motion,
            chord: chord,
            previousNotes: previousNotes,
            stage: stage,
            usesModalHarmony: tonalCenterPitchClass != nil
        )
        var finalSubjectNotes = subjectNotes
        if decision.fill && stage != .returnOfSubject,
           let cadence = cadenceNote(
               chord: nextChord ?? chord,
               near: Int(subjectNotes.last ?? 67)
           ),
           !finalSubjectNotes.isEmpty {
            finalSubjectNotes[finalSubjectNotes.count - 1] = cadence
        }
        let counterNotes = countersubject(
            subject: subject,
            chord: chord,
            include: (decision.activity == .normal || decision.activity == .busy)
                && stage != .fragmentation
                && stage != .returnOfSubject
        )
        let beatLength = 60_000_000 / musicalStateConfiguration.tempoBPM
        var messages: [ScheduledMIDIMessage] = []

        appendVoice(
            notes: finalSubjectNotes,
            positions: rhythm,
            beatLength: beatLength,
            startMicroseconds: startMicroseconds,
            endMicroseconds: endMicroseconds,
            baseVelocity: voiceVelocity(humanAverageVelocity: humanAverageVelocity, ageBars: memory.ageBars),
            durationRatio: durationRatio(stage: stage, relationship: decision.relationship),
            messages: &messages
        )
        if !counterNotes.isEmpty {
            let counterPositions = stride(from: 0, to: rhythm.count, by: 2).map { rhythm[$0] }
            appendVoice(
                notes: counterNotes,
                positions: counterPositions,
                beatLength: beatLength,
                startMicroseconds: startMicroseconds,
                endMicroseconds: endMicroseconds,
                baseVelocity: max(22, voiceVelocity(
                    humanAverageVelocity: humanAverageVelocity,
                    ageBars: memory.ageBars
                ) - 9),
                durationRatio: 1.28,
                messages: &messages
            )
        }
        if stage == .stretto, subject.count >= 3 {
            let entryNotes = strettoAnswer(subjectNotes, chord: chord)
            let entryPositions = rhythm.map { min(
                Double(musicalStateConfiguration.beatsPerBar) - 0.2,
                $0 + 0.75
            ) }
            appendVoice(
                notes: entryNotes,
                positions: entryPositions,
                beatLength: beatLength,
                startMicroseconds: startMicroseconds,
                endMicroseconds: endMicroseconds,
                baseVelocity: max(20, voiceVelocity(
                    humanAverageVelocity: humanAverageVelocity,
                    ageBars: 0
                ) - 12),
                durationRatio: 0.62,
                messages: &messages
            )
        }
        messages.sort {
            if $0.offsetMicroseconds != $1.offsetMicroseconds {
                return $0.offsetMicroseconds < $1.offsetMicroseconds
            }
            if $0.kind.sortOrder != $1.kind.sortOrder {
                return $0.kind.sortOrder < $1.kind.sortOrder
            }
            return $0.note < $1.note
        }

        let phrase = BassPhrase(
            barIndex: barIndex,
            startMicroseconds: startMicroseconds,
            endMicroseconds: endMicroseconds,
            messages: messages
        )
        let ageStrength: Double = stage == .returnOfSubject ? 1 : 0.94
        let voiceActivity = min(1, Double(finalSubjectNotes.count + counterNotes.count) / 8)
        let intervalTension = contrapuntalTension(
            subject: finalSubjectNotes,
            counter: counterNotes
        )
        return MemoryPhraseResult(
            phrase: phrase,
            expression: EnsembleExpression(
                memory: ageStrength * min(1, 0.55 + Double(subject.count) * 0.08),
                tension: stageTension(stage, intervalTension: intervalTension),
                activity: 0.35 + voiceActivity * 0.65,
                resonance: stage == .augmentation || decision.relationship == .hold ? 0.72 : 0.46
            )
        )
    }

    private func selectedSubject(
        from notes: [HumanPhraseNote],
        activity: BassActivity,
        stage: MotifDevelopmentStage,
        barIndex: Int
    ) -> [HumanPhraseNote] {
        let ordered = notes.sorted { $0.positionBeats < $1.positionBeats }
        if stage == .returnOfSubject {
            return Array(ordered.prefix(6))
        }
        if stage == .fragmentation {
            let fragmentLength = min(3, ordered.count)
            let possibleStarts = max(1, ordered.count - fragmentLength + 1)
            let start = abs(barIndex) % possibleStarts
            return Array(ordered[start..<(start + fragmentLength)])
        }
        let count: Int
        switch activity {
        case .rest:
            return []
        case .sparse:
            count = min(2, ordered.count)
        case .normal:
            count = min(4, ordered.count)
        case .busy:
            count = min(6, ordered.count)
        }
        guard count < ordered.count, count > 1 else {
            return Array(ordered.prefix(count))
        }
        return (0..<count).map { index in
            let sourceIndex = Int(
                (Double(index) * Double(ordered.count - 1) / Double(count - 1)).rounded()
            )
            return ordered[sourceIndex]
        }
    }

    private func subjectRhythm(
        _ subject: [HumanPhraseNote],
        relationship: BassRelationship,
        stage: MotifDevelopmentStage,
        beatsPerBar: Double
    ) -> [Double] {
        guard let first = subject.first else { return [] }
        let onset: Double
        let scale: Double
        switch relationship {
        case .follow:
            onset = 0.5
            scale = 1
        case .contrast:
            onset = 1
            scale = 0.72
        case .hold:
            onset = 0
            scale = 1.45
        }
        let stageScale: Double
        switch stage {
        case .augmentation:
            stageScale = 1.65
        case .diminution, .stretto:
            stageScale = 0.58
        default:
            stageScale = 1
        }
        let stageOnset = stage == .returnOfSubject ? 0.25 : onset
        let effectiveScale = stage == .returnOfSubject ? 1 : scale * stageScale
        return subject.map {
            let position = stageOnset
                + ($0.positionBeats - first.positionBeats) * effectiveScale
            return min(beatsPerBar - 0.3, (position * 4).rounded() / 4)
        }
    }

    private func tonalAnswer(
        _ subject: [HumanPhraseNote],
        motion: BassMotion,
        chord: ChordCandidate?,
        previousNotes: [UInt8],
        stage: MotifDevelopmentStage,
        usesModalHarmony: Bool
    ) -> [UInt8] {
        guard let first = subject.first else { return [] }
        let tonic = Int(chord?.rootPitchClass ?? (first.note % 12))
        let answerPitchClass: Int
        if usesModalHarmony {
            answerPitchClass = tonic
        } else {
            switch stage {
            case .answer, .diminution:
                answerPitchClass = (tonic + 7) % 12
            case .sequence:
                answerPitchClass = (tonic + 2) % 12
            case .augmentation:
                answerPitchClass = (tonic + 9) % 12
            default:
                answerPitchClass = tonic
            }
        }
        let reference = Int(previousNotes.last ?? 67)
        let anchor = nearest(pitchClass: answerPitchClass, to: reference, in: 55...67)
        return subject.enumerated().map { index, item in
            let sourceInterval = Int(item.note) - Int(first.note)
            let stagedInterval = stage == .inversion ? -sourceInterval : sourceInterval
            let interval: Int
            if stage == .returnOfSubject {
                return UInt8(fold(anchor + sourceInterval, into: 55...79))
            }
            switch motion {
            case .root:
                interval = stagedInterval
            case .step:
                interval = stagedInterval.signum() * min(abs(stagedInterval), 5)
            case .approach:
                interval = -stagedInterval
            case .leap:
                interval = stagedInterval + (index.isMultiple(of: 2) ? 0 : 7)
            }
            return UInt8(fold(anchor + interval, into: 55...79))
        }
    }

    private func countersubject(
        subject: [HumanPhraseNote],
        chord: ChordCandidate?,
        include: Bool
    ) -> [UInt8] {
        guard include, let first = subject.first else { return [] }
        let pitchClass = Int(chord?.rootPitchClass ?? (first.note % 12))
        let anchor = nearest(pitchClass: pitchClass, to: 48, in: 43...60)
        return stride(from: 0, to: subject.count, by: 2).map { index in
            let interval = Int(subject[index].note) - Int(first.note)
            return UInt8(fold(anchor - interval, into: 43...60))
        }
    }

    private func strettoAnswer(
        _ notes: [UInt8],
        chord: ChordCandidate?
    ) -> [UInt8] {
        let dominantPitchClass = (Int(chord?.rootPitchClass ?? 0) + 7) % 12
        let anchor = nearest(pitchClass: dominantPitchClass, to: 55, in: 43...67)
        guard let first = notes.first else { return [] }
        return notes.map {
            UInt8(fold(anchor + Int($0) - Int(first), into: 43...67))
        }
    }

    private func durationRatio(
        stage: MotifDevelopmentStage,
        relationship: BassRelationship
    ) -> Double {
        switch stage {
        case .augmentation:
            return 1.18
        case .diminution, .stretto:
            return 0.58
        default:
            return relationship == .hold ? 0.92 : 0.76
        }
    }

    private func stageTension(
        _ stage: MotifDevelopmentStage,
        intervalTension: Double
    ) -> Double {
        let structural: Double
        switch stage {
        case .answer: structural = 0.34
        case .sequence: structural = 0.48
        case .inversion: structural = 0.58
        case .fragmentation: structural = 0.64
        case .augmentation: structural = 0.46
        case .diminution: structural = 0.68
        case .stretto: structural = 0.9
        case .returnOfSubject: structural = 0.22
        }
        return min(1, structural * 0.72 + intervalTension * 0.28)
    }

    private func appendVoice(
        notes: [UInt8],
        positions: [Double],
        beatLength: Double,
        startMicroseconds: UInt64,
        endMicroseconds: UInt64,
        baseVelocity: UInt8,
        durationRatio: Double,
        messages: inout [ScheduledMIDIMessage]
    ) {
        for index in notes.indices {
            let position = positions[index]
            let nextPosition = index + 1 < positions.count
                ? positions[index + 1]
                : position + 1
            let available = max(0.2, nextPosition - position)
            let duration = max(0.18, min(1.5, available * durationRatio))
            let onset = startMicroseconds + UInt64((beatLength * position).rounded())
            let release = min(
                onset + UInt64((beatLength * duration).rounded()),
                endMicroseconds - 1
            )
            messages.append(
                ScheduledMIDIMessage(
                    offsetMicroseconds: onset,
                    kind: .noteOn,
                    channel: outputChannel,
                    note: notes[index],
                    velocity: UInt8(max(18, Int(baseVelocity) - index * 2))
                )
            )
            messages.append(
                ScheduledMIDIMessage(
                    offsetMicroseconds: release,
                    kind: .noteOff,
                    channel: outputChannel,
                    note: notes[index],
                    velocity: 0
                )
            )
        }
    }

    private func voiceVelocity(humanAverageVelocity: Double?, ageBars: Int) -> UInt8 {
        let followed = (humanAverageVelocity ?? 82) * 0.42 + 20 - Double(ageBars * 5)
        return UInt8(min(68, max(32, followed)).rounded())
    }

    private func cadenceNote(chord: ChordCandidate?, near reference: Int) -> UInt8? {
        guard let chord else { return nil }
        return UInt8(nearest(
            pitchClass: Int(chord.rootPitchClass),
            to: reference,
            in: 55...79
        ))
    }

    private func contrapuntalTension(subject: [UInt8], counter: [UInt8]) -> Double {
        guard !counter.isEmpty else { return 0.38 }
        let comparisons = zip(subject, counter)
        let clashes = comparisons.reduce(0.0) { total, pair in
            let interval = abs(Int(pair.0) - Int(pair.1)) % 12
            return total + ([1, 2, 6, 10, 11].contains(interval) ? 1 : 0.25)
        }
        return min(1, 0.32 + clashes / Double(counter.count) * 0.38)
    }

    private func nearest(
        pitchClass: Int,
        to reference: Int,
        in range: ClosedRange<Int>
    ) -> Int {
        let normalized = (pitchClass % 12 + 12) % 12
        let candidates = range.filter { $0 % 12 == normalized }
        return candidates.min {
            let left = abs($0 - reference)
            let right = abs($1 - reference)
            return left == right ? $0 < $1 : left < right
        } ?? range.lowerBound
    }

    private func fold(_ note: Int, into range: ClosedRange<Int>) -> Int {
        var folded = note
        while folded < range.lowerBound { folded += 12 }
        while folded > range.upperBound { folded -= 12 }
        return folded
    }
}

public struct BassBarPlan: Codable, Equatable, Sendable {
    public let sourceBarIndex: Int
    public let targetBarIndex: Int
    public let chord: ChordCandidate?
    public let usedHeldChord: Bool
    public let decision: BassDecision
    public let decisionSource: BassDecisionSource
    public let developmentStage: MotifDevelopmentStage?
    public let tonalCenterPitchClass: UInt8?
    public let phrase: BassPhrase
    public let expression: EnsembleExpression

    public init(
        sourceBarIndex: Int,
        targetBarIndex: Int,
        chord: ChordCandidate?,
        usedHeldChord: Bool,
        decision: BassDecision,
        decisionSource: BassDecisionSource = .rules,
        developmentStage: MotifDevelopmentStage? = nil,
        tonalCenterPitchClass: UInt8? = nil,
        phrase: BassPhrase,
        expression: EnsembleExpression = .quiet
    ) {
        self.sourceBarIndex = sourceBarIndex
        self.targetBarIndex = targetBarIndex
        self.chord = chord
        self.usedHeldChord = usedHeldChord
        self.decision = decision
        self.decisionSource = decisionSource
        self.developmentStage = developmentStage
        self.tonalCenterPitchClass = tonalCenterPitchClass
        self.phrase = phrase
        self.expression = expression
    }
}

public struct LocalBassistUpdate: Equatable, Sendable {
    public let snapshots: [MusicalStateSnapshot]
    public let plans: [BassBarPlan]
    public let performedNotes: [PerformedNote]
    public let phraseObservations: [PhraseObservation]
    public let motifs: [Motif]
    public let performanceDiagnostics: [PerformanceTrackerDiagnostic]

    public init(
        snapshots: [MusicalStateSnapshot],
        plans: [BassBarPlan],
        performedNotes: [PerformedNote] = [],
        phraseObservations: [PhraseObservation] = [],
        motifs: [Motif] = [],
        performanceDiagnostics: [PerformanceTrackerDiagnostic] = []
    ) {
        self.snapshots = snapshots
        self.plans = plans
        self.performedNotes = performedNotes
        self.phraseObservations = phraseObservations
        self.motifs = motifs
        self.performanceDiagnostics = performanceDiagnostics
    }
}

public enum LocalBassistError: Error, CustomStringConvertible, Equatable {
    case invalidIntroBars(Int)
    case invalidMaximumHeldChordBars(Int)
    case invalidOutputChannel(UInt8)
    case fugueRequiresMode
    case fugueDoesNotUseProgression
    case modeOnlyAppliesToFugue

    public var description: String {
        switch self {
        case let .invalidIntroBars(value):
            return "Intro bars must be between 0 and 32; received \(value)."
        case let .invalidMaximumHeldChordBars(value):
            return "Maximum held-chord bars must be between 0 and 16; received \(value)."
        case let .invalidOutputChannel(value):
            return "MIDI output channel must be between 1 and 16; received \(value)."
        case .fugueRequiresMode:
            return "Fugue style requires --mode instead of a fixed chord progression."
        case .fugueDoesNotUseProgression:
            return "Fugue style develops harmony from --mode; remove --progression."
        case .modeOnlyAppliesToFugue:
            return "--mode currently applies only to --style fugue."
        }
    }
}

public struct LocalBassistConfiguration: Equatable, Sendable {
    public let musicalState: MusicalStateConfiguration
    public let introBars: Int
    public let maximumHeldChordBars: Int
    public let outputChannel: UInt8
    public let progression: [ChordCandidate]
    public let style: AccompanimentStyle
    public let mode: MusicalMode?

    public init(
        musicalState: MusicalStateConfiguration,
        introBars: Int = 4,
        maximumHeldChordBars: Int = 2,
        outputChannel: UInt8 = 3,
        progression: [ChordCandidate] = [],
        style: AccompanimentStyle = .bass,
        mode: MusicalMode? = nil
    ) throws {
        guard (0...32).contains(introBars) else {
            throw LocalBassistError.invalidIntroBars(introBars)
        }
        guard (0...16).contains(maximumHeldChordBars) else {
            throw LocalBassistError.invalidMaximumHeldChordBars(maximumHeldChordBars)
        }
        guard (1...16).contains(outputChannel) else {
            throw LocalBassistError.invalidOutputChannel(outputChannel)
        }
        if style == .fugue, mode == nil {
            throw LocalBassistError.fugueRequiresMode
        }
        if style == .fugue, !progression.isEmpty {
            throw LocalBassistError.fugueDoesNotUseProgression
        }
        if style != .fugue, mode != nil {
            throw LocalBassistError.modeOnlyAppliesToFugue
        }
        self.musicalState = musicalState
        self.introBars = introBars
        self.maximumHeldChordBars = maximumHeldChordBars
        self.outputChannel = outputChannel
        self.progression = progression
        self.style = style
        self.mode = mode
    }
}

public struct LocalBassistEngine: Sendable {
    public let configuration: LocalBassistConfiguration

    private var tracker: MusicalStateTracker
    private let decisionProvider: any BassDecisionProvider
    private let phraseGenerator: BassPhraseGenerator
    private let ambientPhraseGenerator: AmbientPhraseGenerator
    private let memoryPhraseGenerator: MemoryPhraseGenerator
    private let fuguePhraseGenerator: FuguePhraseGenerator
    private var lastChord: ChordCandidate?
    private var barsWithoutChord = 0
    private var previousBassNote: UInt8?
    private var previousPhraseNotes: [UInt8] = []
    private var performanceTracker: PerformanceTracker
    private var phraseSegmenter: PhraseSegmenter
    private var motifMemory = MotifMemory()
    private var pendingMotifs: [Motif] = []
    private var recentPhraseMemory: HumanPhraseMemory?
    private var fugueSubjectMemory: HumanPhraseMemory?
    private var pendingFugueSubject: HumanPhraseMemory?
    private var fugueCycleStartBarIndex: Int?
    private var fugueTonalCenterPitchClass: UInt8?

    public init(
        configuration: LocalBassistConfiguration,
        decisionProvider: any BassDecisionProvider = RuleBasedBassDecisionProvider()
    ) {
        self.configuration = configuration
        tracker = MusicalStateTracker(configuration: configuration.musicalState)
        self.decisionProvider = decisionProvider
        phraseGenerator = BassPhraseGenerator(outputChannel: configuration.outputChannel)
        ambientPhraseGenerator = AmbientPhraseGenerator(
            outputChannel: configuration.outputChannel
        )
        memoryPhraseGenerator = MemoryPhraseGenerator(
            outputChannel: configuration.outputChannel
        )
        fuguePhraseGenerator = FuguePhraseGenerator(
            outputChannel: configuration.outputChannel
        )
        performanceTracker = PerformanceTracker()
        phraseSegmenter = PhraseSegmenter(
            musicalStateConfiguration: configuration.musicalState
        )
    }

    public mutating func ingest(_ event: SessionMIDIEvent) throws -> LocalBassistUpdate {
        var nextPerformanceTracker = performanceTracker
        var nextPhraseSegmenter = phraseSegmenter
        let observationsBeforeEvent = try nextPhraseSegmenter.observeEvent(
            at: event.offsetMicroseconds,
            hasActiveNotes: nextPerformanceTracker.hasActiveNotes
        )
        let performance = try nextPerformanceTracker.ingest(event)
        try nextPhraseSegmenter.ingest(completedNotes: performance.completedNotes)
        let snapshots = try tracker.ingest(event)
        performanceTracker = nextPerformanceTracker
        phraseSegmenter = nextPhraseSegmenter
        let motifs = remember(observationsBeforeEvent)
        return Self.enriching(
            makeUpdate(from: snapshots),
            performance: performance,
            observations: observationsBeforeEvent,
            motifs: motifs
        )
    }

    public mutating func advance(through offsetMicroseconds: UInt64) throws -> LocalBassistUpdate {
        var nextPhraseSegmenter = phraseSegmenter
        let observations = try nextPhraseSegmenter.advance(
            through: offsetMicroseconds,
            hasActiveNotes: performanceTracker.hasActiveNotes
        )
        let snapshots = try tracker.advance(through: offsetMicroseconds)
        phraseSegmenter = nextPhraseSegmenter
        let motifs = remember(observations)
        return Self.enriching(
            makeUpdate(from: snapshots),
            observations: observations,
            motifs: motifs
        )
    }

    public mutating func finish(through offsetMicroseconds: UInt64) throws -> LocalBassistUpdate {
        var nextPerformanceTracker = performanceTracker
        var nextPhraseSegmenter = phraseSegmenter
        let performance = try nextPerformanceTracker.finish(through: offsetMicroseconds)
        try nextPhraseSegmenter.ingest(completedNotes: performance.completedNotes)
        let observations = try nextPhraseSegmenter.finish(through: offsetMicroseconds)
        let snapshots = try tracker.finish(through: offsetMicroseconds)
        performanceTracker = nextPerformanceTracker
        phraseSegmenter = nextPhraseSegmenter
        let motifs = remember(observations)
        return Self.enriching(
            makeUpdate(from: snapshots),
            performance: performance,
            observations: observations,
            motifs: motifs
        )
    }

    public func cancelPendingDecisions() {
        decisionProvider.cancelPendingDecisions()
    }

    private mutating func makeUpdate(
        from snapshots: [MusicalStateSnapshot]
    ) -> LocalBassistUpdate {
        var plans: [BassBarPlan] = []
        for snapshot in snapshots where snapshot.boundary == .bar {
            let memory = phraseMemory(for: snapshot)
            let currentChord = snapshot.state.chordCandidates.first
            if let currentChord {
                lastChord = currentChord
                barsWithoutChord = 0
            } else {
                barsWithoutChord += 1
            }

            let mayHoldChord = barsWithoutChord <= configuration.maximumHeldChordBars
            let targetBarIndex = snapshot.barIndex + 1
            let fugueDevelopment = configuration.style == .fugue
                ? updateFugueDevelopment(
                    candidate: memory,
                    targetBarIndex: targetBarIndex
                )
                : nil
            let nextFugueDevelopment = previewFugueDevelopment(
                targetBarIndex: targetBarIndex + 1
            )
            let liveChord = currentChord ?? (mayHoldChord ? lastChord : nil)
            let plannedChord = progressionChord(for: targetBarIndex)
            let modalChord = fugueDevelopment.flatMap {
                chord(for: $0.stage, tonalCenterPitchClass: $0.tonalCenterPitchClass)
            }
            let nextChord = progressionChord(for: targetBarIndex + 1)
                ?? nextFugueDevelopment.flatMap {
                    chord(for: $0.stage, tonalCenterPitchClass: $0.tonalCenterPitchClass)
                }
            let resolvedChord = plannedChord ?? modalChord ?? liveChord
            let usedHeldChord = plannedChord == nil
                && modalChord == nil
                && currentChord == nil
                && resolvedChord != nil
            if targetBarIndex >= configuration.introBars {
                let input = BassDecisionInput(
                    state: snapshot.state,
                    chord: resolvedChord,
                    nextChord: nextChord,
                    style: configuration.style,
                    developmentStage: fugueDevelopment?.stage,
                    mode: configuration.mode,
                    tonalCenterPitchClass: fugueDevelopment?.tonalCenterPitchClass,
                    isHeldChord: usedHeldChord,
                    targetBarIndex: targetBarIndex
                )
                let resolution = decisionProvider.resolution(for: input)
                let phrase: BassPhrase
                let expression: EnsembleExpression
                switch configuration.style {
                case .bass:
                    phrase = phraseGenerator.generate(
                        decision: resolution.decision,
                        chord: resolvedChord,
                        barIndex: targetBarIndex,
                        startMicroseconds: snapshot.endMicroseconds,
                        musicalStateConfiguration: configuration.musicalState,
                        previousBassNote: previousBassNote,
                        humanAverageVelocity: snapshot.state.averageVelocity,
                        nextChord: nextChord
                    )
                    expression = .quiet
                case .ambient:
                    phrase = ambientPhraseGenerator.generate(
                        decision: resolution.decision,
                        chord: resolvedChord,
                        barIndex: targetBarIndex,
                        startMicroseconds: snapshot.endMicroseconds,
                        musicalStateConfiguration: configuration.musicalState,
                        previousNotes: previousPhraseNotes,
                        humanAverageVelocity: snapshot.state.averageVelocity
                    )
                    expression = .quiet
                case .memory:
                    let result = memoryPhraseGenerator.generate(
                        decision: resolution.decision,
                        chord: resolvedChord,
                        barIndex: targetBarIndex,
                        startMicroseconds: snapshot.endMicroseconds,
                        musicalStateConfiguration: configuration.musicalState,
                        memory: memory,
                        previousNotes: previousPhraseNotes,
                        humanAverageVelocity: snapshot.state.averageVelocity
                    )
                    phrase = result.phrase
                    expression = result.expression
                case .fugue:
                    let result = fuguePhraseGenerator.generate(
                        decision: resolution.decision,
                        chord: resolvedChord,
                        nextChord: nextChord,
                        barIndex: targetBarIndex,
                        startMicroseconds: snapshot.endMicroseconds,
                        musicalStateConfiguration: configuration.musicalState,
                        memory: fugueDevelopment?.memory,
                        previousNotes: previousPhraseNotes,
                        humanAverageVelocity: snapshot.state.averageVelocity,
                        stage: fugueDevelopment?.stage ?? .answer,
                        tonalCenterPitchClass: fugueDevelopment?.tonalCenterPitchClass
                    )
                    phrase = result.phrase
                    expression = result.expression
                }
                let generatedNotes = phrase.messages
                    .filter { $0.kind == .noteOn }
                    .map(\.note)
                if !generatedNotes.isEmpty {
                    previousPhraseNotes = generatedNotes
                }
                previousBassNote = phrase.messages.last(where: { $0.kind == .noteOn })?.note
                    ?? previousBassNote
                plans.append(
                    BassBarPlan(
                        sourceBarIndex: snapshot.barIndex,
                        targetBarIndex: targetBarIndex,
                        chord: resolvedChord,
                        usedHeldChord: usedHeldChord,
                        decision: resolution.decision,
                        decisionSource: resolution.source,
                        developmentStage: fugueDevelopment?.stage,
                        tonalCenterPitchClass: fugueDevelopment?.tonalCenterPitchClass,
                        phrase: phrase,
                        expression: expression
                    )
                )
            }

            let preparedTargetBarIndex = targetBarIndex + 1
            if preparedTargetBarIndex >= configuration.introBars {
                let preparedPlannedChord = progressionChord(for: preparedTargetBarIndex)
                let preparedFugue = previewFugueDevelopment(
                    targetBarIndex: preparedTargetBarIndex
                )
                let preparedModalChord = preparedFugue.flatMap {
                    chord(for: $0.stage, tonalCenterPitchClass: $0.tonalCenterPitchClass)
                }
                let followingFugue = previewFugueDevelopment(
                    targetBarIndex: preparedTargetBarIndex + 1
                )
                let preparedChord = preparedPlannedChord ?? preparedModalChord ?? liveChord
                let preparedNextChord = progressionChord(for: preparedTargetBarIndex + 1)
                    ?? followingFugue.flatMap {
                        chord(for: $0.stage, tonalCenterPitchClass: $0.tonalCenterPitchClass)
                    }
                decisionProvider.prepare(
                    BassDecisionInput(
                        state: snapshot.state,
                        chord: preparedChord,
                        nextChord: preparedNextChord,
                        style: configuration.style,
                        developmentStage: preparedFugue?.stage,
                        mode: configuration.mode,
                        tonalCenterPitchClass: preparedFugue?.tonalCenterPitchClass,
                        isHeldChord: preparedPlannedChord == nil
                            && preparedModalChord == nil
                            && currentChord == nil
                            && preparedChord != nil,
                        targetBarIndex: preparedTargetBarIndex
                    )
                )
            }
        }
        return LocalBassistUpdate(snapshots: snapshots, plans: plans)
    }

    private mutating func remember(_ observations: [PhraseObservation]) -> [Motif] {
        observations.compactMap { observation in
            guard let motif = motifMemory.remember(
                observation,
                musicalStateConfiguration: configuration.musicalState
            ) else {
                return nil
            }
            pendingMotifs.append(motif)
            return motif
        }
    }

    private mutating func phraseMemory(
        for snapshot: MusicalStateSnapshot
    ) -> HumanPhraseMemory? {
        let eligibleCount = pendingMotifs.prefix {
            $0.finalizedAtMicroseconds <= snapshot.endMicroseconds
        }.count
        if eligibleCount > 0 {
            let captured = pendingMotifs[eligibleCount - 1]
            pendingMotifs.removeFirst(eligibleCount)
            let memory = captured.legacyMemory()
            recentPhraseMemory = memory
            return memory
        }
        guard let recentPhraseMemory else {
            return nil
        }
        let aged = HumanPhraseMemory(
            notes: recentPhraseMemory.notes,
            ageBars: recentPhraseMemory.ageBars + 1
        )
        self.recentPhraseMemory = aged.ageBars <= 2 ? aged : nil
        return aged.ageBars <= 2 ? aged : nil
    }

    private static func enriching(
        _ update: LocalBassistUpdate,
        performance: PerformanceTrackerUpdate = PerformanceTrackerUpdate(),
        observations: [PhraseObservation] = [],
        motifs: [Motif] = []
    ) -> LocalBassistUpdate {
        LocalBassistUpdate(
            snapshots: update.snapshots,
            plans: update.plans,
            performedNotes: performance.completedNotes,
            phraseObservations: observations,
            motifs: motifs,
            performanceDiagnostics: performance.diagnostics
        )
    }

    private mutating func updateFugueDevelopment(
        candidate: HumanPhraseMemory?,
        targetBarIndex: Int
    ) -> (
        memory: HumanPhraseMemory,
        stage: MotifDevelopmentStage,
        tonalCenterPitchClass: UInt8
    )? {
        let qualified = candidate.flatMap { memory in
            memory.notes.count >= 3
                ? HumanPhraseMemory(notes: Array(memory.notes.prefix(8)), ageBars: 0)
                : nil
        }
        if targetBarIndex < configuration.introBars {
            if let qualified {
                pendingFugueSubject = qualified
            }
            return nil
        }
        if fugueSubjectMemory == nil, let initial = qualified ?? pendingFugueSubject {
            fugueSubjectMemory = initial
            pendingFugueSubject = nil
            fugueCycleStartBarIndex = targetBarIndex
            fugueTonalCenterPitchClass = modalPlanner?.inferTonalCenter(from: initial.notes)
        } else if let qualified {
            pendingFugueSubject = qualified
        }

        guard var subject = fugueSubjectMemory,
              var cycleStart = fugueCycleStartBarIndex else {
            return nil
        }
        let elapsed = max(0, targetBarIndex - cycleStart)
        if elapsed >= MotifDevelopmentStage.allCases.count,
           elapsed.isMultiple(of: MotifDevelopmentStage.allCases.count),
           let pendingFugueSubject {
            subject = pendingFugueSubject
            fugueSubjectMemory = pendingFugueSubject
            self.pendingFugueSubject = nil
            cycleStart = targetBarIndex
            fugueCycleStartBarIndex = targetBarIndex
            fugueTonalCenterPitchClass = modalPlanner?.inferTonalCenter(
                from: subject.notes
            )
        }
        guard let fugueTonalCenterPitchClass else { return nil }
        return (
            subject,
            MotifDevelopmentStage.stage(at: targetBarIndex - cycleStart),
            fugueTonalCenterPitchClass
        )
    }

    private func previewFugueDevelopment(
        targetBarIndex: Int
    ) -> (
        memory: HumanPhraseMemory,
        stage: MotifDevelopmentStage,
        tonalCenterPitchClass: UInt8
    )? {
        guard let subject = fugueSubjectMemory,
              let cycleStart = fugueCycleStartBarIndex,
              let tonalCenter = fugueTonalCenterPitchClass else {
            return nil
        }
        let elapsed = max(0, targetBarIndex - cycleStart)
        if elapsed >= MotifDevelopmentStage.allCases.count,
           elapsed.isMultiple(of: MotifDevelopmentStage.allCases.count),
           let pendingFugueSubject,
           let pendingCenter = modalPlanner?.inferTonalCenter(from: pendingFugueSubject.notes) {
            return (pendingFugueSubject, .answer, pendingCenter)
        }
        return (
            subject,
            MotifDevelopmentStage.stage(at: elapsed),
            tonalCenter
        )
    }

    private var modalPlanner: ModalHarmonyPlanner? {
        configuration.mode.map { ModalHarmonyPlanner(mode: $0) }
    }

    private func chord(
        for stage: MotifDevelopmentStage,
        tonalCenterPitchClass: UInt8
    ) -> ChordCandidate? {
        modalPlanner?.chord(
            tonalCenterPitchClass: tonalCenterPitchClass,
            stage: stage
        )
    }

    private func progressionChord(for barIndex: Int) -> ChordCandidate? {
        guard !configuration.progression.isEmpty, barIndex >= configuration.introBars else {
            return nil
        }
        let index = (barIndex - configuration.introBars) % configuration.progression.count
        return configuration.progression[index]
    }
}
