import XCTest
@testable import JevBassistCore

final class ConversationEngineTests: XCTestCase {
    func testClearMotifProducesRecognizableOneVoiceAnswerOnNextBeat() throws {
        let configuration = try MusicalStateConfiguration(tempoBPM: 120, beatsPerBar: 4)
        var engine = ConversationEngine(
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

    func testContextualDevelopmentReturnsToImmutableOriginAfterDivergence() throws {
        let configuration = try MusicalStateConfiguration(tempoBPM: 120, beatsPerBar: 4)
        var engine = ConversationEngine(
            musicalStateConfiguration: configuration,
            mode: .dorian,
            outputChannel: 3
        )

        let echo = try XCTUnwrap(engine.plan(for: motif(id: 1)))
        let sequence = try XCTUnwrap(engine.plan(for: motif(
            id: 2,
            pitches: [67, 70, 72],
            finalizedAt: 4_215_000
        )))
        let augmentation = try XCTUnwrap(engine.plan(for: motif(
            id: 3,
            pitches: [62, 64, 65, 67, 69, 71],
            durationBeats: 2,
            finalizedAt: 6_215_000
        )))
        let returned = try XCTUnwrap(engine.plan(for: motif(
            id: 4,
            pitches: [64, 67, 69],
            finalizedAt: 8_215_000
        )))

        XCTAssertEqual(echo.conversationLineage?.relationship, .echo)
        XCTAssertEqual(sequence.conversationLineage?.relationship, .sequence)
        XCTAssertEqual(augmentation.conversationLineage?.relationship, .augmentation)
        XCTAssertEqual(returned.conversationLineage?.relationship, .originalReturn)
        XCTAssertEqual(returned.conversationLineage?.originMotifID, 1)
        XCTAssertEqual(returned.conversationLineage?.sourceMotifID, 4)
        XCTAssertEqual(returned.conversationLineage?.generation, 3)
        XCTAssertEqual(
            returned.phrase.messages.filter { $0.kind == .noteOn }.map(\.note),
            [62, 65, 67]
        )
    }

    private func motif(
        id: UInt64 = 1,
        pitches: [UInt8] = [62, 65, 67],
        durationBeats: Double = 2.12,
        finalizedAt: UInt64 = 2_215_000
    ) -> Motif {
        let onsetStep = durationBeats / Double(max(1, pitches.count))
        let preservedOnsets = [0.0, 0.6, 1.64]
        let preservedDurations = [0.32, 0.72, 0.48]
        let notes = pitches.enumerated().map { index, pitch in
            MotifNote(
                sourceNoteID: UInt64(index + 1),
                note: pitch,
                velocity: index == 0 ? 96 : 82,
                relativeOnsetBeats: pitches.count == 3
                    ? preservedOnsets[index]
                    : Double(index) * onsetStep,
                durationBeats: pitches.count == 3
                    ? preservedDurations[index]
                    : max(0.12, onsetStep * 0.7),
                restBeforeBeats: index == 0 ? 0 : onsetStep * 0.3,
                accent: index == 0 ? 1 : 0.85,
                releaseWasInferred: false
            )
        }
        let intervals = zip(pitches.dropFirst(), pitches).map { later, earlier in
            Int(later) - Int(earlier)
        }
        return Motif(
            id: id,
            notes: notes,
            durationBeats: durationBeats,
            boundaryConfidence: 0.9,
            melodyConfidence: 1,
            features: MotifFeatures(
                pitchIntervals: intervals,
                accentedNoteIndices: [0],
                restedNoteIndices: Array(notes.indices.dropFirst()),
                characteristicIntervalIndices: []
            ),
            finalizedAtMicroseconds: finalizedAt
        )
    }
}
