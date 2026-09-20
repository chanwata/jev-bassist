import Foundation

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
    public let isHeldChord: Bool
    public let targetBarIndex: Int

    public init(
        state: MusicalState,
        chord: ChordCandidate?,
        isHeldChord: Bool,
        targetBarIndex: Int
    ) {
        self.state = state
        self.chord = chord
        self.isHeldChord = isHeldChord
        self.targetBarIndex = targetBarIndex
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
            activity: decision.activity,
            beatsPerBar: musicalStateConfiguration.beatsPerBar
        )
        let notes = notePattern(
            motion: decision.motion,
            chord: chord,
            count: positions.count,
            fill: decision.fill
        )
        let durationRatio = decision.activity == .busy ? 0.38 : 0.72
        let duration = UInt64((beatLength * durationRatio).rounded())
        let velocity = velocity(for: decision.activity)
        var messages: [ScheduledMIDIMessage] = []

        for (position, note) in zip(positions, notes) {
            let relativeOnset = UInt64((beatLength * position).rounded())
            let onset = startMicroseconds + relativeOnset
            let noteOff = min(onset + duration, endMicroseconds - 1)
            messages.append(
                ScheduledMIDIMessage(
                    offsetMicroseconds: onset,
                    kind: .noteOn,
                    channel: outputChannel,
                    note: note,
                    velocity: velocity
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
            return $0.kind.sortOrder < $1.kind.sortOrder
        }
        return BassPhrase(
            barIndex: barIndex,
            startMicroseconds: startMicroseconds,
            endMicroseconds: endMicroseconds,
            messages: messages
        )
    }

    private func onsetPositions(activity: BassActivity, beatsPerBar: Int) -> [Double] {
        switch activity {
        case .rest:
            return []
        case .sparse:
            return beatsPerBar >= 3 ? [0, Double(beatsPerBar / 2)] : [0]
        case .normal:
            return (0..<beatsPerBar).map(Double.init)
        case .busy:
            return (0..<(beatsPerBar * 2)).map { Double($0) / 2 }
        }
    }

    private func notePattern(
        motion: BassMotion,
        chord: ChordCandidate,
        count: Int,
        fill: Bool
    ) -> [UInt8] {
        let root = bassNote(pitchClass: Int(chord.rootPitchClass))
        let thirdInterval = chord.quality == .major ? 4 : 3
        let third = bassNote(pitchClass: Int(chord.rootPitchClass) + thirdInterval)
        let fifth = bassNote(pitchClass: Int(chord.rootPitchClass) + 7)
        let approach = bassNote(pitchClass: Int(chord.rootPitchClass) - 1)
        let cycle: [UInt8]

        switch motion {
        case .root:
            cycle = [root]
        case .step:
            cycle = [root, third, fifth, third]
        case .approach:
            cycle = [root, approach]
        case .leap:
            cycle = [root, fifth]
        }

        guard count > 0 else {
            return []
        }
        var result = (0..<count).map { cycle[$0 % cycle.count] }
        if fill {
            result[result.count - 1] = approach
        }
        return result
    }

    private func bassNote(pitchClass: Int) -> UInt8 {
        let normalized = (pitchClass % 12 + 12) % 12
        return UInt8(36 + normalized)
    }

    private func velocity(for activity: BassActivity) -> UInt8 {
        switch activity {
        case .rest:
            return 0
        case .sparse:
            return 78
        case .normal:
            return 84
        case .busy:
            return 88
        }
    }
}

public struct BassBarPlan: Codable, Equatable, Sendable {
    public let sourceBarIndex: Int
    public let targetBarIndex: Int
    public let chord: ChordCandidate?
    public let usedHeldChord: Bool
    public let decision: BassDecision
    public let decisionSource: BassDecisionSource
    public let phrase: BassPhrase

    public init(
        sourceBarIndex: Int,
        targetBarIndex: Int,
        chord: ChordCandidate?,
        usedHeldChord: Bool,
        decision: BassDecision,
        decisionSource: BassDecisionSource = .rules,
        phrase: BassPhrase
    ) {
        self.sourceBarIndex = sourceBarIndex
        self.targetBarIndex = targetBarIndex
        self.chord = chord
        self.usedHeldChord = usedHeldChord
        self.decision = decision
        self.decisionSource = decisionSource
        self.phrase = phrase
    }
}

public struct LocalBassistUpdate: Equatable, Sendable {
    public let snapshots: [MusicalStateSnapshot]
    public let plans: [BassBarPlan]

    public init(snapshots: [MusicalStateSnapshot], plans: [BassBarPlan]) {
        self.snapshots = snapshots
        self.plans = plans
    }
}

public enum LocalBassistError: Error, CustomStringConvertible, Equatable {
    case invalidIntroBars(Int)
    case invalidMaximumHeldChordBars(Int)
    case invalidOutputChannel(UInt8)

    public var description: String {
        switch self {
        case let .invalidIntroBars(value):
            return "Intro bars must be between 0 and 32; received \(value)."
        case let .invalidMaximumHeldChordBars(value):
            return "Maximum held-chord bars must be between 0 and 16; received \(value)."
        case let .invalidOutputChannel(value):
            return "MIDI output channel must be between 1 and 16; received \(value)."
        }
    }
}

public struct LocalBassistConfiguration: Equatable, Sendable {
    public let musicalState: MusicalStateConfiguration
    public let introBars: Int
    public let maximumHeldChordBars: Int
    public let outputChannel: UInt8

    public init(
        musicalState: MusicalStateConfiguration,
        introBars: Int = 4,
        maximumHeldChordBars: Int = 2,
        outputChannel: UInt8 = 3
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
        self.musicalState = musicalState
        self.introBars = introBars
        self.maximumHeldChordBars = maximumHeldChordBars
        self.outputChannel = outputChannel
    }
}

public struct LocalBassistEngine: Sendable {
    public let configuration: LocalBassistConfiguration

    private var tracker: MusicalStateTracker
    private let decisionProvider: any BassDecisionProvider
    private let phraseGenerator: BassPhraseGenerator
    private var lastChord: ChordCandidate?
    private var barsWithoutChord = 0

    public init(
        configuration: LocalBassistConfiguration,
        decisionProvider: any BassDecisionProvider = RuleBasedBassDecisionProvider()
    ) {
        self.configuration = configuration
        tracker = MusicalStateTracker(configuration: configuration.musicalState)
        self.decisionProvider = decisionProvider
        phraseGenerator = BassPhraseGenerator(outputChannel: configuration.outputChannel)
    }

    public mutating func ingest(_ event: SessionMIDIEvent) throws -> LocalBassistUpdate {
        makeUpdate(from: try tracker.ingest(event))
    }

    public mutating func advance(through offsetMicroseconds: UInt64) throws -> LocalBassistUpdate {
        makeUpdate(from: try tracker.advance(through: offsetMicroseconds))
    }

    public mutating func finish(through offsetMicroseconds: UInt64) throws -> LocalBassistUpdate {
        makeUpdate(from: try tracker.finish(through: offsetMicroseconds))
    }

    public func cancelPendingDecisions() {
        decisionProvider.cancelPendingDecisions()
    }

    private mutating func makeUpdate(
        from snapshots: [MusicalStateSnapshot]
    ) -> LocalBassistUpdate {
        var plans: [BassBarPlan] = []
        for snapshot in snapshots where snapshot.boundary == .bar {
            let currentChord = snapshot.state.chordCandidates.first
            if let currentChord {
                lastChord = currentChord
                barsWithoutChord = 0
            } else {
                barsWithoutChord += 1
            }

            let mayHoldChord = barsWithoutChord <= configuration.maximumHeldChordBars
            let resolvedChord = currentChord ?? (mayHoldChord ? lastChord : nil)
            let usedHeldChord = currentChord == nil && resolvedChord != nil
            let targetBarIndex = snapshot.barIndex + 1
            if targetBarIndex >= configuration.introBars {
                let input = BassDecisionInput(
                    state: snapshot.state,
                    chord: resolvedChord,
                    isHeldChord: usedHeldChord,
                    targetBarIndex: targetBarIndex
                )
                let resolution = decisionProvider.resolution(for: input)
                let phrase = phraseGenerator.generate(
                    decision: resolution.decision,
                    chord: resolvedChord,
                    barIndex: targetBarIndex,
                    startMicroseconds: snapshot.endMicroseconds,
                    musicalStateConfiguration: configuration.musicalState
                )
                plans.append(
                    BassBarPlan(
                        sourceBarIndex: snapshot.barIndex,
                        targetBarIndex: targetBarIndex,
                        chord: resolvedChord,
                        usedHeldChord: usedHeldChord,
                        decision: resolution.decision,
                        decisionSource: resolution.source,
                        phrase: phrase
                    )
                )
            }

            let preparedTargetBarIndex = targetBarIndex + 1
            if preparedTargetBarIndex >= configuration.introBars {
                decisionProvider.prepare(
                    BassDecisionInput(
                        state: snapshot.state,
                        chord: resolvedChord,
                        isHeldChord: usedHeldChord,
                        targetBarIndex: preparedTargetBarIndex
                    )
                )
            }
        }
        return LocalBassistUpdate(snapshots: snapshots, plans: plans)
    }
}
