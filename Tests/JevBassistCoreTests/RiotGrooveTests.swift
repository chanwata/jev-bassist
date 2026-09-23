import XCTest
@testable import JevBassistCore

final class RiotGrooveTests: XCTestCase {
    func testRiotGrooveProvidesDryPulseAndBackbeat() throws {
        let generator = RiotGrooveGenerator(
            musicalState: try MusicalStateConfiguration(tempoBPM: 120, beatsPerBar: 4),
            drumChannel: 10,
            textureChannel: 2
        )

        let plan = generator.plan(
            barIndex: 0,
            humanDensity: 0.5,
            tonalCenterPitchClass: 2,
            mode: .dorian,
            swing: 0.58,
            intensity: 0.7
        )
        let drumAttacks = plan.drumMessages.filter { $0.kind == .noteOn }

        XCTAssertTrue(drumAttacks.contains { $0.note == 36 && $0.offsetMicroseconds == 0 })
        XCTAssertEqual(drumAttacks.filter { $0.note == 37 }.count, 2)
        XCTAssertTrue(drumAttacks.contains {
            $0.note == 42 && $0.offsetMicroseconds == 290_000
        })
        XCTAssertTrue(plan.drumMessages.allSatisfy { $0.channel == 10 })
        XCTAssertTrue(plan.textureMessages.allSatisfy { $0.channel == 2 })
        XCTAssertEqual(
            try XCTUnwrap(plan.textureMessages.first { $0.kind == .noteOn }).note % 12,
            2,
            "The first keyboard punctuation should anchor the inferred tonic."
        )
    }

    func testDenseHumanPlayingLeavesMoreSpace() throws {
        let generator = RiotGrooveGenerator(
            musicalState: try MusicalStateConfiguration(tempoBPM: 96, beatsPerBar: 4)
        )
        let sparse = generator.plan(
            barIndex: 1,
            humanDensity: 0.4,
            tonalCenterPitchClass: 0,
            mode: .mixolydian,
            intensity: 0.8
        )
        let dense = generator.plan(
            barIndex: 1,
            humanDensity: 3,
            tonalCenterPitchClass: 0,
            mode: .mixolydian,
            intensity: 0.8
        )

        XCTAssertGreaterThan(
            sparse.drumMessages.filter { $0.kind == .noteOn }.count,
            dense.drumMessages.filter { $0.kind == .noteOn }.count
        )
        XCTAssertFalse(sparse.textureMessages.isEmpty)
        XCTAssertTrue(dense.textureMessages.isEmpty)
    }

    func testHouseGrooveKeepsFourOnFloorAndFrequentOffbeats() throws {
        let generator = RiotGrooveGenerator(
            musicalState: try MusicalStateConfiguration(tempoBPM: 120, beatsPerBar: 4),
            drumChannel: 10,
            textureChannel: 2
        )

        let plan = generator.plan(
            barIndex: 0,
            humanDensity: 3,
            tonalCenterPitchClass: 2,
            mode: .dorian,
            swing: 0.58,
            intensity: 0.72,
            style: .house
        )
        let attacks = plan.drumMessages.filter { $0.kind == .noteOn }
        let kicks = attacks.filter { $0.note == 36 }.map(\.offsetMicroseconds)
        let claps = attacks.filter { $0.note == 39 }.map(\.offsetMicroseconds)

        XCTAssertEqual(kicks, [0, 500_000, 1_000_000, 1_500_000])
        XCTAssertEqual(claps, [500_000, 1_500_000])
        XCTAssertGreaterThanOrEqual(attacks.filter { [42, 46].contains($0.note) }.count, 12)
        XCTAssertEqual(plan.textureMessages.filter { $0.kind == .noteOn }.count, 4)
    }

    func testZeroIntensityIsSilent() throws {
        let generator = RiotGrooveGenerator(
            musicalState: try MusicalStateConfiguration(tempoBPM: 100, beatsPerBar: 4)
        )

        let plan = generator.plan(
            barIndex: 0,
            humanDensity: 0,
            tonalCenterPitchClass: 9,
            mode: .dorian,
            intensity: 0
        )

        XCTAssertTrue(plan.messages.isEmpty)
    }

    func testGrooveTimingSwingsOffbeatsAndBlendsObservedTiming() {
        let timing = GrooveTiming(swing: 0.6, strength: 0.75)

        XCTAssertEqual(timing.nextOpportunity(after: 1.1, minimumLeadBeats: 0), 1.6)
        XCTAssertEqual(
            timing.nextConversationOpportunity(after: 1.1, minimumLeadBeats: 0),
            1.3
        )
        XCTAssertEqual(
            GrooveTiming(swing: 0.6, strength: 1).alignedConversationBeat(1.12),
            1
        )
        XCTAssertEqual(
            GrooveTiming(swing: 0.6, strength: 1).alignedConversationBeat(1.62),
            1.6
        )
        XCTAssertEqual(timing.alignedBeat(0.52), 0.58, accuracy: 0.0001)
        XCTAssertEqual(timing.alignedBeat(1), 1, accuracy: 0.0001)
    }

    func testLogicalConversationSubdivisionsApplySwingOnce() {
        let timing = GrooveTiming(swing: 0.58, strength: 1)

        XCTAssertEqual(timing.conversationSubdivisionIndex(nearest: 4.58), 18)
        XCTAssertEqual(timing.conversationBeat(forSubdivisionIndex: 18), 4.58)
        XCTAssertEqual(timing.conversationBeat(forSubdivisionIndex: 20), 5)
        XCTAssertEqual(timing.conversationBeat(forSubdivisionIndex: 22), 5.58)
        XCTAssertEqual(
            timing.nextConversationOpportunity(
                after: 4.55,
                minimumLeadBeats: 0,
                matchingSubdivisionPhase: 2
            ),
            4.58
        )
    }

    func testConversationResponseUsesSameSwingGrid() throws {
        var engine = ConversationEngine(
            musicalStateConfiguration: try MusicalStateConfiguration(
                tempoBPM: 120,
                beatsPerBar: 4
            ),
            mode: .dorian,
            outputChannel: 3,
            grooveTiming: GrooveTiming(swing: 0.6, strength: 1)
        )
        let motif = Motif(
            id: 1,
            notes: [
                note(id: 1, pitch: 62, onset: 0),
                note(id: 2, pitch: 65, onset: 0.52),
                note(id: 3, pitch: 67, onset: 1.02)
            ],
            durationBeats: 1.4,
            boundaryConfidence: 0.9,
            melodyConfidence: 1,
            features: MotifFeatures(
                pitchIntervals: [3, 2],
                accentedNoteIndices: [0],
                restedNoteIndices: [],
                characteristicIntervalIndices: [0]
            ),
            finalizedAtMicroseconds: 2_215_000
        )

        let plan = try XCTUnwrap(engine.submit(
            motif,
            availableAtMicroseconds: 2_215_000
        ))
        let onsets = plan.phrase.messages
            .filter { $0.kind == .noteOn }
            .map(\.offsetMicroseconds)

        XCTAssertEqual(plan.phrase.startMicroseconds, 2_300_000)
        XCTAssertEqual(onsets, [2_300_000, 2_500_000, 2_800_000])
        XCTAssertEqual(
            onsets.map { Double($0) / 500_000 },
            [4.6, 5.0, 5.6]
        )
    }

    func testConversationPreservesSourcePhaseWithoutReswingingIntervals() throws {
        var engine = ConversationEngine(
            musicalStateConfiguration: try MusicalStateConfiguration(
                tempoBPM: 120,
                beatsPerBar: 4
            ),
            mode: .dorian,
            outputChannel: 3,
            grooveTiming: GrooveTiming(swing: 0.6, strength: 1)
        )
        let motif = Motif(
            id: 1,
            notes: [
                note(id: 1, pitch: 62, onset: 0, grooveOnset: 0),
                note(id: 2, pitch: 65, onset: 0.4, grooveOnset: 0.5),
                note(id: 3, pitch: 67, onset: 1, grooveOnset: 1)
            ],
            durationBeats: 1.4,
            boundaryConfidence: 0.9,
            melodyConfidence: 1,
            features: MotifFeatures(
                pitchIntervals: [3, 2],
                accentedNoteIndices: [0],
                restedNoteIndices: [],
                characteristicIntervalIndices: [0]
            ),
            finalizedAtMicroseconds: 2_215_000,
            grooveStartSubdivision: 2
        )

        let plan = try XCTUnwrap(engine.submit(
            motif,
            availableAtMicroseconds: 2_215_000
        ))
        let onsets = plan.phrase.messages
            .filter { $0.kind == .noteOn }
            .map(\.offsetMicroseconds)

        XCTAssertEqual(onsets, [2_300_000, 2_500_000, 2_800_000])
        XCTAssertEqual(onsets.map { Double($0) / 500_000 }, [4.6, 5, 5.6])
    }

    func testHouseConversationUsesEighthGridAndExpandsShortMotif() throws {
        var engine = ConversationEngine(
            musicalStateConfiguration: try MusicalStateConfiguration(
                tempoBPM: 120,
                beatsPerBar: 4
            ),
            mode: .dorian,
            outputChannel: 3,
            grooveTiming: GrooveTiming(
                swing: 0.6,
                strength: 1,
                conversationGrid: .eighth
            )
        )
        let motif = Motif(
            id: 1,
            notes: [
                note(id: 1, pitch: 62, onset: 0, grooveOnset: 0),
                note(id: 2, pitch: 65, onset: 0.4, grooveOnset: 0.5),
                note(id: 3, pitch: 67, onset: 1, grooveOnset: 1)
            ],
            durationBeats: 1.4,
            boundaryConfidence: 0.9,
            melodyConfidence: 1,
            features: MotifFeatures(
                pitchIntervals: [3, 2],
                accentedNoteIndices: [0],
                restedNoteIndices: [],
                characteristicIntervalIndices: [0]
            ),
            finalizedAtMicroseconds: 2_215_000,
            grooveStartSubdivision: 1
        )

        let plan = try XCTUnwrap(engine.submit(
            motif,
            availableAtMicroseconds: 2_215_000
        ))
        let onsets = plan.phrase.messages
            .filter { $0.kind == .noteOn }
            .map(\.offsetMicroseconds)

        XCTAssertEqual(
            onsets,
            [2_300_000, 2_500_000, 2_800_000, 3_000_000, 3_300_000, 3_500_000]
        )
    }

    func testHouseSupportingHoldBecomesARegularPulse() throws {
        let motif = Motif(
            id: 1,
            notes: [
                note(id: 1, pitch: 62, onset: 0),
                note(id: 2, pitch: 65, onset: 0.5)
            ],
            durationBeats: 1,
            boundaryConfidence: 0.9,
            melodyConfidence: 1,
            features: MotifFeatures(
                pitchIntervals: [3],
                accentedNoteIndices: [0],
                restedNoteIndices: [],
                characteristicIntervalIndices: [0]
            ),
            finalizedAtMicroseconds: 1_000_000
        )
        let candidates = ResponseCandidateGenerator().candidates(
            for: motif,
            pitchContext: ModalPitchContext(mode: .dorian, tonalCenterPitchClass: 2),
            minimumResponseNotes: 6
        )
        let hold = try XCTUnwrap(candidates.first { $0.relationship == .hold })

        XCTAssertEqual(hold.notes.count, 6)
        XCTAssertEqual(hold.notes.map(\.relativeOnsetBeats), [0, 0.5, 1, 1.5, 2, 2.5])
        XCTAssertEqual(Set(hold.notes.map(\.note)).count, 1)
    }

    private func note(
        id: UInt64,
        pitch: UInt8,
        onset: Double,
        grooveOnset: Double? = nil
    ) -> MotifNote {
        MotifNote(
            sourceNoteID: id,
            note: pitch,
            velocity: 84,
            relativeOnsetBeats: onset,
            grooveOnsetBeats: grooveOnset,
            durationBeats: 0.3,
            restBeforeBeats: 0,
            accent: id == 1 ? 1 : 0.75,
            releaseWasInferred: false
        )
    }
}
