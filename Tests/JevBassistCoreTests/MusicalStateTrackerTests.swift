import XCTest
@testable import JevBassistCore

final class MusicalStateTrackerTests: XCTestCase {
    func testBeatSnapshotSummarizesDensityVelocityRegisterHeldNotesAndChord() throws {
        var tracker = try makeTracker()
        _ = try tracker.ingest(event(at: 0, note: 60, velocity: 60))
        _ = try tracker.ingest(event(at: 100_000, note: 64, velocity: 90))
        _ = try tracker.ingest(event(at: 200_000, note: 67, velocity: 120))
        _ = try tracker.ingest(event(at: 400_000, kind: .noteOff, note: 60, velocity: 0))

        let snapshots = try tracker.finish(through: 500_000)
        let beat = try XCTUnwrap(snapshots.first)

        XCTAssertEqual(beat.boundary, .beat)
        XCTAssertEqual(beat.index, 0)
        XCTAssertEqual(beat.barIndex, 0)
        XCTAssertEqual(beat.beatInBar, 1)
        XCTAssertEqual(beat.state.noteOnCount, 3)
        XCTAssertEqual(beat.state.noteDensityPerBeat, 3)
        XCTAssertEqual(beat.state.averageVelocity, 90)
        XCTAssertEqual(beat.state.averageNote ?? 0, 63.666_666, accuracy: 0.000_001)
        XCTAssertEqual(beat.state.lowestNote, 60)
        XCTAssertEqual(beat.state.highestNote, 67)
        XCTAssertEqual(beat.state.heldNotes.map(\.note), [64, 67])
        XCTAssertEqual(beat.state.chordCandidates.first?.displayName, "C major")
        XCTAssertEqual(beat.state.chordCandidates.first?.confidence ?? 0, 1, accuracy: 0.000_001)
    }

    func testEventOnBoundaryBelongsToFollowingBeat() throws {
        var tracker = try makeTracker()

        let emittedBeforeEvent = try tracker.ingest(event(at: 500_000, note: 60))
        let emittedAtFinish = try tracker.finish(through: 1_000_000)

        XCTAssertEqual(emittedBeforeEvent.count, 1)
        XCTAssertEqual(emittedBeforeEvent[0].state.noteOnCount, 0)
        XCTAssertEqual(emittedAtFinish.count, 1)
        XCTAssertEqual(emittedAtFinish[0].state.noteOnCount, 1)
    }

    func testHeldNotePersistsAcrossSilentBeat() throws {
        var tracker = try makeTracker()
        _ = try tracker.ingest(event(at: 0, note: 48, velocity: 100))

        let snapshots = try tracker.finish(through: 1_000_000)

        XCTAssertEqual(snapshots.count, 2)
        XCTAssertEqual(snapshots[0].state.noteOnCount, 1)
        XCTAssertEqual(snapshots[1].state.noteOnCount, 0)
        XCTAssertEqual(snapshots[1].state.noteDensityPerBeat, 0)
        XCTAssertNil(snapshots[1].state.averageVelocity)
        XCTAssertEqual(snapshots[1].state.heldNotes.map(\.note), [48])
    }

    func testQuarterNoteOnsetsEstimate120BPMAndEmitBarSnapshot() throws {
        var tracker = try makeTracker()
        for offset in stride(from: UInt64(0), through: 1_500_000, by: 500_000) {
            _ = try tracker.ingest(event(at: offset, note: 60))
        }

        let snapshots = try tracker.finish(through: 2_000_000)
        let bar = try XCTUnwrap(snapshots.last)

        XCTAssertEqual(snapshots.filter { $0.boundary == .beat }.count, 4)
        XCTAssertEqual(snapshots.filter { $0.boundary == .bar }.count, 1)
        XCTAssertEqual(bar.boundary, .bar)
        XCTAssertEqual(bar.state.noteOnCount, 4)
        XCTAssertEqual(bar.state.noteDensityPerBeat, 1)
        XCTAssertEqual(bar.state.pulse?.bpm ?? 0, 120, accuracy: 0.000_001)
        XCTAssertEqual(bar.state.pulse?.confidence ?? 0, 0.75, accuracy: 0.000_001)
    }

    func testEmptySessionProducesStableSilentBeatAndBarSnapshots() throws {
        var tracker = try makeTracker()

        let snapshots = try tracker.finish(through: 2_000_000)

        XCTAssertEqual(snapshots.count, 5)
        XCTAssertTrue(snapshots.allSatisfy { $0.state.noteOnCount == 0 })
        XCTAssertTrue(snapshots.allSatisfy { $0.state.heldNotes.isEmpty })
        XCTAssertTrue(snapshots.allSatisfy { $0.state.chordCandidates.isEmpty })
        XCTAssertTrue(snapshots.allSatisfy { $0.state.pulse == nil })
    }

    func testRejectsOutOfOrderEventsAndIngestAfterFinish() throws {
        var tracker = try makeTracker()
        _ = try tracker.ingest(event(at: 200, note: 60))

        XCTAssertThrowsError(try tracker.ingest(event(at: 100, note: 62)))
        _ = try tracker.finish(through: 500_000)
        XCTAssertThrowsError(try tracker.ingest(event(at: 600_000, note: 64))) { error in
            XCTAssertEqual(error as? MusicalStateError, .eventAfterFinish)
        }
    }

    private func makeTracker() throws -> MusicalStateTracker {
        MusicalStateTracker(
            configuration: try MusicalStateConfiguration(
                tempoBPM: 120,
                beatsPerBar: 4
            )
        )
    }

    private func event(
        at offset: UInt64,
        kind: MIDIEvent.Kind = .noteOn,
        note: UInt8,
        velocity: UInt8 = 80
    ) -> SessionMIDIEvent {
        SessionMIDIEvent(
            offsetMicroseconds: offset,
            hostTime: offset,
            channel: 1,
            kind: kind,
            note: note,
            velocity: velocity
        )
    }
}
