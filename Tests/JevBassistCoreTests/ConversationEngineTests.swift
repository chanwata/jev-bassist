import XCTest
@testable import JevBassistCore

final class ConversationEngineTests: XCTestCase {
    func testClearMotifProducesRecognizableOneVoiceAnswerOnNextBeat() throws {
        let configuration = try MusicalStateConfiguration(tempoBPM: 120, beatsPerBar: 4)
        let engine = ConversationEngine(
            musicalStateConfiguration: configuration,
            mode: .dorian,
            outputChannel: 3
        )
        let plan = try XCTUnwrap(engine.plan(for: motif()))
        let noteOns = plan.phrase.messages.filter { $0.kind == .noteOn }
        let noteOffs = plan.phrase.messages.filter { $0.kind == .noteOff }

        XCTAssertEqual(plan.phrase.startMicroseconds, 2_500_000)
        XCTAssertEqual(plan.developmentStage, nil)
        XCTAssertEqual(noteOns.map(\.offsetMicroseconds), [2_500_000, 2_800_000, 3_320_000])
        XCTAssertEqual(noteOns.map(\.note), [62, 65, 67])
        XCTAssertEqual(noteOns.count, noteOffs.count)
        XCTAssertLessThan(noteOffs[0].offsetMicroseconds, noteOns[1].offsetMicroseconds)
        XCTAssertLessThan(noteOffs[1].offsetMicroseconds, noteOns[2].offsetMicroseconds)
        XCTAssertTrue(plan.phrase.messages.allSatisfy { $0.channel == 3 })
    }

    func testModalProjectionMovesOnlyOutOfModePitchToNearestTone() {
        let context = ModalPitchContext(mode: .dorian, tonalCenterPitchClass: 2)

        XCTAssertEqual(context.conservativeProjection(62), 62)
        XCTAssertEqual(context.conservativeProjection(66), 65)
        XCTAssertTrue(context.contains(context.conservativeProjection(66)))
    }

    private func motif() -> Motif {
        Motif(
            id: 1,
            notes: [
                MotifNote(
                    sourceNoteID: 1,
                    note: 62,
                    velocity: 96,
                    relativeOnsetBeats: 0,
                    durationBeats: 0.32,
                    restBeforeBeats: 0,
                    accent: 1,
                    releaseWasInferred: false
                ),
                MotifNote(
                    sourceNoteID: 2,
                    note: 65,
                    velocity: 78,
                    relativeOnsetBeats: 0.6,
                    durationBeats: 0.72,
                    restBeforeBeats: 0.28,
                    accent: 0.81,
                    releaseWasInferred: false
                ),
                MotifNote(
                    sourceNoteID: 3,
                    note: 67,
                    velocity: 88,
                    relativeOnsetBeats: 1.64,
                    durationBeats: 0.48,
                    restBeforeBeats: 0.32,
                    accent: 0.92,
                    releaseWasInferred: false
                )
            ],
            durationBeats: 2.12,
            boundaryConfidence: 0.9,
            melodyConfidence: 1,
            features: MotifFeatures(
                pitchIntervals: [3, 2],
                accentedNoteIndices: [0, 2],
                restedNoteIndices: [1, 2],
                characteristicIntervalIndices: []
            ),
            finalizedAtMicroseconds: 2_215_000
        )
    }
}
