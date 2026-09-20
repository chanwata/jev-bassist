import Foundation
import XCTest
@testable import JevBassistCore

final class LocalBassistTests: XCTestCase {
    func testRulePolicyLeavesSpaceForDensePlayingAndMovesDuringSilence() {
        let provider = RuleBasedBassDecisionProvider()
        let chord = ChordCandidate(rootPitchClass: 0, quality: .minor, confidence: 0.9)

        let dense = provider.decision(
            for: BassDecisionInput(
                state: state(noteCount: 8, density: 2),
                chord: chord,
                isHeldChord: false,
                targetBarIndex: 4
            )
        )
        let silent = provider.decision(
            for: BassDecisionInput(
                state: state(noteCount: 0, density: 0),
                chord: chord,
                isHeldChord: true,
                targetBarIndex: 5
            )
        )

        XCTAssertEqual(dense.activity, .sparse)
        XCTAssertEqual(dense.relationship, .contrast)
        XCTAssertEqual(silent.activity, .normal)
        XCTAssertEqual(silent.relationship, .hold)
        XCTAssertLessThan(silent.confidence, dense.confidence)
    }

    func testRulePolicyRestsWithoutKnownHarmony() {
        let decision = RuleBasedBassDecisionProvider().decision(
            for: BassDecisionInput(
                state: state(noteCount: 4, density: 1),
                chord: nil,
                isHeldChord: false,
                targetBarIndex: 4
            )
        )

        XCTAssertEqual(decision.activity, .rest)
        XCTAssertEqual(decision.confidence, 1)
    }

    func testPhraseGeneratorProducesDeterministicPairedNotesInBassRange() throws {
        let generator = BassPhraseGenerator(outputChannel: 3)
        let decision = BassDecision(
            activity: .normal,
            relationship: .follow,
            motion: .step,
            fill: false,
            confidence: 0.9
        )
        let phrase = generator.generate(
            decision: decision,
            chord: ChordCandidate(rootPitchClass: 0, quality: .minor, confidence: 1),
            barIndex: 4,
            startMicroseconds: 8_000_000,
            musicalStateConfiguration: try MusicalStateConfiguration(
                tempoBPM: 120,
                beatsPerBar: 4
            )
        )

        let noteOns = phrase.messages.filter { $0.kind == .noteOn }
        let noteOffs = phrase.messages.filter { $0.kind == .noteOff }
        XCTAssertEqual(noteOns.map(\.note), [36, 38, 39, 41])
        XCTAssertEqual(
            noteOns.map(\.offsetMicroseconds),
            [8_000_000, 8_750_000, 9_000_000, 9_750_000]
        )
        XCTAssertEqual(noteOffs.count, noteOns.count)
        XCTAssertTrue(phrase.messages.allSatisfy { (36...48).contains($0.note) })
        XCTAssertEqual(noteOns.map(\.velocity), [80, 70, 74, 70])
        XCTAssertEqual(noteOns[0].bytes, [0x92, 36, 80])
        XCTAssertEqual(noteOffs[0].bytes, [0x82, 36, 0])
    }

    func testPhraseGeneratorUsesRelationshipForRhythmicPocket() throws {
        let generator = BassPhraseGenerator(outputChannel: 3)
        let chord = ChordCandidate(rootPitchClass: 0, quality: .minor, confidence: 1)
        let configuration = try MusicalStateConfiguration(tempoBPM: 120, beatsPerBar: 4)
        let follow = generator.generate(
            decision: BassDecision(
                activity: .normal,
                relationship: .follow,
                motion: .root,
                fill: false,
                confidence: 1
            ),
            chord: chord,
            barIndex: 4,
            startMicroseconds: 0,
            musicalStateConfiguration: configuration
        )
        let contrast = generator.generate(
            decision: BassDecision(
                activity: .normal,
                relationship: .contrast,
                motion: .root,
                fill: false,
                confidence: 1
            ),
            chord: chord,
            barIndex: 4,
            startMicroseconds: 0,
            musicalStateConfiguration: configuration
        )

        XCTAssertEqual(
            follow.messages.filter { $0.kind == .noteOn }.map(\.offsetMicroseconds),
            [0, 750_000, 1_000_000, 1_750_000]
        )
        XCTAssertEqual(
            contrast.messages.filter { $0.kind == .noteOn }.map(\.offsetMicroseconds),
            [0, 750_000, 1_375_000]
        )
    }

    func testPhraseGeneratorVoiceLeadsAcrossBToCWithoutOctaveDrop() throws {
        let phrase = BassPhraseGenerator(outputChannel: 3).generate(
            decision: BassDecision(
                activity: .sparse,
                relationship: .follow,
                motion: .root,
                fill: false,
                confidence: 1
            ),
            chord: ChordCandidate(rootPitchClass: 0, quality: .major, confidence: 1),
            barIndex: 4,
            startMicroseconds: 0,
            musicalStateConfiguration: try MusicalStateConfiguration(),
            previousBassNote: 47,
            humanAverageVelocity: 80
        )

        XCTAssertEqual(
            phrase.messages.filter { $0.kind == .noteOn }.first?.note,
            48
        )
    }

    func testPhraseGeneratorProducesSilenceForRestDecision() throws {
        let phrase = BassPhraseGenerator(outputChannel: 3).generate(
            decision: BassDecision(
                activity: .rest,
                relationship: .hold,
                motion: .root,
                fill: false,
                confidence: 1
            ),
            chord: nil,
            barIndex: 4,
            startMicroseconds: 8_000_000,
            musicalStateConfiguration: try MusicalStateConfiguration()
        )

        XCTAssertTrue(phrase.messages.isEmpty)
    }

    func testEngineWaitsFourCompleteBarsBeforePlanningBarFive() throws {
        var engine = try makeEngine(introBars: 4)
        var plans: [BassBarPlan] = []

        for bar in 0..<4 {
            let start = UInt64(bar) * 2_000_000
            plans += try ingestTriad(at: start, into: &engine)
            plans += try engine.advance(through: start + 2_000_000).plans
            if bar < 3 {
                XCTAssertTrue(plans.isEmpty)
            }
        }

        XCTAssertEqual(plans.count, 1)
        XCTAssertEqual(plans[0].sourceBarIndex, 3)
        XCTAssertEqual(plans[0].targetBarIndex, 4)
        XCTAssertEqual(plans[0].phrase.startMicroseconds, 8_000_000)
        XCTAssertFalse(plans[0].phrase.messages.isEmpty)
    }

    func testEnginePrefetchesRemoteDecisionOneBarBeforeFirstBassPlan() throws {
        let provider = ImmediatePreparedProvider()
        var engine = LocalBassistEngine(
            configuration: try LocalBassistConfiguration(
                musicalState: MusicalStateConfiguration(
                    tempoBPM: 120,
                    beatsPerBar: 4
                ),
                introBars: 4,
                outputChannel: 3
            ),
            decisionProvider: provider
        )
        var plans: [BassBarPlan] = []

        for bar in 0..<4 {
            let start = UInt64(bar) * 2_000_000
            plans += try ingestTriad(at: start, into: &engine)
            plans += try engine.advance(through: start + 2_000_000).plans
        }

        XCTAssertEqual(provider.preparedTargets, [4, 5])
        XCTAssertEqual(provider.resolvedTargets, [4])
        XCTAssertEqual(plans.count, 1)
        XCTAssertEqual(plans[0].decisionSource, .jev)
        XCTAssertEqual(plans[0].decision.activity, .busy)
    }

    func testEngineHoldsChordForTwoSilentBarsThenFallsBackToRest() throws {
        var engine = try makeEngine(introBars: 0, maximumHeldChordBars: 2)
        _ = try ingestTriad(at: 0, into: &engine)

        let known = try XCTUnwrap(engine.advance(through: 2_000_000).plans.first)
        let heldOnce = try XCTUnwrap(engine.advance(through: 4_000_000).plans.first)
        let heldTwice = try XCTUnwrap(engine.advance(through: 6_000_000).plans.first)
        let expired = try XCTUnwrap(engine.advance(through: 8_000_000).plans.first)

        XCTAssertFalse(known.usedHeldChord)
        XCTAssertTrue(heldOnce.usedHeldChord)
        XCTAssertTrue(heldTwice.usedHeldChord)
        XCTAssertFalse(heldOnce.phrase.messages.isEmpty)
        XCTAssertFalse(heldTwice.phrase.messages.isEmpty)
        XCTAssertNil(expired.chord)
        XCTAssertEqual(expired.decision.activity, .rest)
        XCTAssertTrue(expired.phrase.messages.isEmpty)
    }

    private func makeEngine(
        introBars: Int,
        maximumHeldChordBars: Int = 2
    ) throws -> LocalBassistEngine {
        LocalBassistEngine(
            configuration: try LocalBassistConfiguration(
                musicalState: MusicalStateConfiguration(
                    tempoBPM: 120,
                    beatsPerBar: 4
                ),
                introBars: introBars,
                maximumHeldChordBars: maximumHeldChordBars,
                outputChannel: 3
            )
        )
    }

    private func ingestTriad(
        at start: UInt64,
        into engine: inout LocalBassistEngine
    ) throws -> [BassBarPlan] {
        var plans: [BassBarPlan] = []
        for (offset, note) in [(UInt64(0), UInt8(60)), (100_000, 63), (200_000, 67)] {
            plans += try engine.ingest(
                SessionMIDIEvent(
                    offsetMicroseconds: start + offset,
                    hostTime: start + offset,
                    channel: 1,
                    kind: .noteOn,
                    note: note,
                    velocity: 90
                )
            ).plans
        }
        for (offset, note) in [(UInt64(300_000), UInt8(60)), (310_000, 63), (320_000, 67)] {
            plans += try engine.ingest(
                SessionMIDIEvent(
                    offsetMicroseconds: start + offset,
                    hostTime: start + offset,
                    channel: 1,
                    kind: .noteOff,
                    note: note,
                    velocity: 0
                )
            ).plans
        }
        return plans
    }

    private func state(noteCount: Int, density: Double) -> MusicalState {
        MusicalState(
            noteOnCount: noteCount,
            noteDensityPerBeat: density,
            averageVelocity: nil,
            averageNote: nil,
            lowestNote: nil,
            highestNote: nil,
            heldNotes: [],
            pulse: nil,
            chordCandidates: []
        )
    }
}

private final class ImmediatePreparedProvider: BassDecisionProvider, @unchecked Sendable {
    private let lock = NSLock()
    private var prepared: Set<Int> = []
    private var recordedPreparedTargets: [Int] = []
    private var recordedResolvedTargets: [Int] = []

    var preparedTargets: [Int] {
        lock.lock()
        defer { lock.unlock() }
        return recordedPreparedTargets
    }

    var resolvedTargets: [Int] {
        lock.lock()
        defer { lock.unlock() }
        return recordedResolvedTargets
    }

    func prepare(_ input: BassDecisionInput) {
        lock.lock()
        prepared.insert(input.targetBarIndex)
        recordedPreparedTargets.append(input.targetBarIndex)
        lock.unlock()
    }

    func decision(for input: BassDecisionInput) -> BassDecision {
        RuleBasedBassDecisionProvider().decision(for: input)
    }

    func resolution(for input: BassDecisionInput) -> BassDecisionResolution {
        lock.lock()
        recordedResolvedTargets.append(input.targetBarIndex)
        let wasPrepared = prepared.remove(input.targetBarIndex) != nil
        lock.unlock()
        guard wasPrepared else {
            return BassDecisionResolution(
                decision: decision(for: input),
                source: .fallback
            )
        }
        return BassDecisionResolution(
            decision: BassDecision(
                activity: .busy,
                relationship: .contrast,
                motion: .approach,
                fill: true,
                confidence: 0.9
            ),
            source: .jev
        )
    }
}
