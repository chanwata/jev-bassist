import XCTest
@testable import JevBassistCore

final class PhraseMemoryTests: XCTestCase {
    func testPhraseMayCrossBarWithoutBeingSplit() throws {
        let configuration = try MusicalStateConfiguration(tempoBPM: 120, beatsPerBar: 4)
        var segmenter = PhraseSegmenter(musicalStateConfiguration: configuration)
        try segmenter.ingest(
            completedNotes: [
                note(id: 1, pitch: 62, velocity: 96, onset: 1_800_000, release: 1_950_000),
                note(id: 2, pitch: 65, velocity: 72, onset: 2_050_000, release: 2_300_000)
            ]
        )

        XCTAssertTrue(
            try segmenter.advance(through: 2_000_000, hasActiveNotes: false).isEmpty
        )
        XCTAssertTrue(
            try segmenter.advance(through: 2_499_999, hasActiveNotes: false).isEmpty
        )
        let observation = try XCTUnwrap(
            segmenter.advance(through: 2_500_000, hasActiveNotes: false).first
        )

        XCTAssertEqual(observation.notes.map(\.id), [1, 2])
        XCTAssertEqual(observation.melodyNotes.map(\.note), [62, 65])
        XCTAssertEqual(observation.finalizedAtMicroseconds, 2_500_000)
    }

    func testSimultaneousChordDoesNotBecomeThreeNoteMelody() throws {
        let configuration = try MusicalStateConfiguration(tempoBPM: 120, beatsPerBar: 4)
        var segmenter = PhraseSegmenter(musicalStateConfiguration: configuration)
        try segmenter.ingest(
            completedNotes: [
                note(id: 1, pitch: 60, velocity: 80, onset: 0, release: 200_000),
                note(id: 2, pitch: 64, velocity: 90, onset: 8_000, release: 210_000),
                note(id: 3, pitch: 67, velocity: 85, onset: 12_000, release: 220_000)
            ]
        )

        let observation = try XCTUnwrap(segmenter.finish(through: 1_000_000).first)
        var memory = MotifMemory()

        XCTAssertEqual(observation.simultaneousNoteGroups.count, 1)
        XCTAssertEqual(observation.melodyNotes.map(\.note), [64])
        XCTAssertNil(
            memory.remember(
                observation,
                musicalStateConfiguration: configuration
            )
        )
    }

    func testMotifPreservesDurationRestsAccentsAndOriginal() throws {
        let configuration = try MusicalStateConfiguration(tempoBPM: 120, beatsPerBar: 4)
        let observation = PhraseObservation(
            notes: [
                note(id: 1, pitch: 60, velocity: 100, onset: 100_000, release: 350_000),
                note(id: 2, pitch: 67, velocity: 60, onset: 600_000, release: 1_100_000)
            ],
            melodyNotes: [
                note(id: 1, pitch: 60, velocity: 100, onset: 100_000, release: 350_000),
                note(id: 2, pitch: 67, velocity: 60, onset: 600_000, release: 1_100_000)
            ],
            simultaneousNoteGroups: [[1], [2]],
            startMicroseconds: 100_000,
            endMicroseconds: 1_100_000,
            finalizedAtMicroseconds: 1_400_000,
            boundaryConfidence: 0.9,
            melodyConfidence: 1
        )
        var memory = MotifMemory(maximumMotifs: 2)

        let motif = try XCTUnwrap(
            memory.remember(observation, musicalStateConfiguration: configuration)
        )
        let original = motif
        _ = memory.remember(observation, musicalStateConfiguration: configuration)
        _ = memory.remember(observation, musicalStateConfiguration: configuration)

        XCTAssertEqual(motif.notes.map(\.relativeOnsetBeats), [0, 1])
        XCTAssertEqual(motif.notes.map(\.durationBeats), [0.5, 1])
        XCTAssertEqual(motif.notes.map(\.restBeforeBeats), [0, 0.5])
        XCTAssertEqual(motif.notes.map(\.accent), [1, 0.6])
        XCTAssertEqual(motif.features.pitchIntervals, [7])
        XCTAssertEqual(motif.features.restedNoteIndices, [1])
        XCTAssertEqual(motif.features.characteristicIntervalIndices, [0])
        XCTAssertEqual(motif, original)
        XCTAssertEqual(memory.motifs.map(\.id), [2, 3])
    }

    func testContinuousPlayingEmitsBoundedObservationWithoutSilence() throws {
        let configuration = try MusicalStateConfiguration(tempoBPM: 120, beatsPerBar: 4)
        var segmenter = PhraseSegmenter(
            musicalStateConfiguration: configuration,
            maximumPendingNotes: 64,
            maximumContinuousNotes: 4
        )
        try segmenter.ingest(completedNotes: [
            note(id: 1, pitch: 60, velocity: 80, onset: 0, release: 100_000),
            note(id: 2, pitch: 62, velocity: 80, onset: 90_000, release: 200_000),
            note(id: 3, pitch: 64, velocity: 80, onset: 190_000, release: 300_000),
            note(id: 4, pitch: 65, velocity: 80, onset: 290_000, release: 400_000)
        ])

        let observation = try XCTUnwrap(
            segmenter.advance(through: 410_000, hasActiveNotes: true).first
        )

        XCTAssertEqual(observation.notes.count, 4)
        XCTAssertEqual(observation.boundaryConfidence, 0.65)
        XCTAssertTrue(
            try segmenter.advance(through: 500_000, hasActiveNotes: true).isEmpty
        )
    }

    private func note(
        id: UInt64,
        pitch: UInt8,
        velocity: UInt8,
        onset: UInt64,
        release: UInt64
    ) -> PerformedNote {
        PerformedNote(
            id: id,
            channel: 1,
            note: pitch,
            velocity: velocity,
            onsetMicroseconds: onset,
            releaseMicroseconds: release,
            release: .observed
        )
    }
}
