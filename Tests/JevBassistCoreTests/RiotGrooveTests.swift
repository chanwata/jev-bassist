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
        XCTAssertEqual(timing.alignedBeat(0.52), 0.58, accuracy: 0.0001)
        XCTAssertEqual(timing.alignedBeat(1), 1, accuracy: 0.0001)
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
        XCTAssertEqual(onsets, [2_300_000, 2_600_000, 2_800_000])
    }

    private func note(id: UInt64, pitch: UInt8, onset: Double) -> MotifNote {
        MotifNote(
            sourceNoteID: id,
            note: pitch,
            velocity: 84,
            relativeOnsetBeats: onset,
            durationBeats: 0.3,
            restBeforeBeats: 0,
            accent: id == 1 ? 1 : 0.75,
            releaseWasInferred: false
        )
    }
}
