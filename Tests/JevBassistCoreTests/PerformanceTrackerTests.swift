import XCTest
@testable import JevBassistCore

final class PerformanceTrackerTests: XCTestCase {
    func testPairsRetriggeredSameNoteInFIFOOrder() throws {
        var tracker = PerformanceTracker()

        _ = try tracker.ingest(event(.noteOn, note: 60, velocity: 90, at: 100))
        _ = try tracker.ingest(event(.noteOn, note: 60, velocity: 70, at: 150))
        let first = try tracker.ingest(event(.noteOff, note: 60, at: 300))
        let second = try tracker.ingest(event(.noteOff, note: 60, at: 450))

        XCTAssertEqual(first.completedNotes.first?.id, 1)
        XCTAssertEqual(first.completedNotes.first?.durationMicroseconds, 200)
        XCTAssertEqual(second.completedNotes.first?.id, 2)
        XCTAssertEqual(second.completedNotes.first?.durationMicroseconds, 300)
        XCTAssertEqual(second.completedNotes.first?.velocity, 70)
        XCTAssertFalse(tracker.hasActiveNotes)
    }

    func testReportsOrphanNoteOffAndInfersMissingReleaseAtFinish() throws {
        var tracker = PerformanceTracker()

        let orphan = try tracker.ingest(event(.noteOff, note: 61, at: 10))
        _ = try tracker.ingest(event(.noteOn, note: 64, velocity: 88, at: 20))
        let finished = try tracker.finish(through: 520)

        XCTAssertEqual(
            orphan.diagnostics,
            [.orphanNoteOff(channel: 1, note: 61, offsetMicroseconds: 10)]
        )
        XCTAssertEqual(finished.completedNotes.first?.durationMicroseconds, 500)
        XCTAssertEqual(finished.completedNotes.first?.release, .inferredAtSessionEnd)
    }

    func testRejectsOutOfOrderEvents() throws {
        var tracker = PerformanceTracker()
        _ = try tracker.ingest(event(.noteOn, note: 60, at: 200))

        XCTAssertThrowsError(try tracker.ingest(event(.noteOff, note: 60, at: 199))) {
            XCTAssertEqual(
                $0 as? PerformanceTrackerError,
                .nonMonotonicEvent(offsetMicroseconds: 199)
            )
        }
    }

    private func event(
        _ kind: MIDIEvent.Kind,
        note: UInt8,
        velocity: UInt8 = 0,
        at offset: UInt64
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
