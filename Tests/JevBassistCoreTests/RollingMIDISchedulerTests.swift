import XCTest
@testable import JevBassistCore

final class RollingMIDISchedulerTests: XCTestCase {
    func testDrainsOnlyInsideRollingHorizon() throws {
        var scheduler = try RollingMIDIScheduler(horizonMicroseconds: 50_000)
        scheduler.submit([
            message(.noteOn, note: 60, at: 100_000),
            message(.noteOff, note: 60, at: 400_000)
        ])

        XCTAssertTrue(try scheduler.drain(through: 49_999).isEmpty)
        XCTAssertEqual(
            try scheduler.drain(through: 50_000).map(\.message.kind),
            [.noteOn]
        )
        XCTAssertTrue(try scheduler.drain(through: 349_999).isEmpty)
        XCTAssertEqual(
            try scheduler.drain(through: 350_000).map(\.message.kind),
            [.noteOff]
        )
    }

    func testHumanReentryCancelsUnsentAttacksButKeepsCommittedRelease() throws {
        var scheduler = try RollingMIDIScheduler(horizonMicroseconds: 50_000)
        scheduler.submit([
            message(.noteOn, note: 60, at: 0),
            message(.noteOff, note: 60, at: 500_000),
            message(.noteOn, note: 64, at: 700_000),
            message(.noteOff, note: 64, at: 900_000)
        ])

        let committed = try scheduler.drain(through: 0)
        let cancellation = scheduler.yieldToHuman(at: 100_000)
        let remaining = try scheduler.drain(through: 1_000_000)

        XCTAssertEqual(committed.map(\.message.kind), [.noteOn])
        XCTAssertEqual(cancellation.canceledNoteIDs.count, 1)
        XCTAssertEqual(cancellation.canceledEventIDs.count, 2)
        XCTAssertEqual(cancellation.canceledRevisions, [1])
        XCTAssertEqual(remaining.map(\.message.kind), [.noteOff])
        XCTAssertEqual(remaining.map(\.message.note), [60])
    }

    func testOverlappingSameNotePairsRemainIndependent() throws {
        var scheduler = try RollingMIDIScheduler(horizonMicroseconds: 5_000)
        scheduler.submit([
            message(.noteOn, note: 60, at: 0),
            message(.noteOn, note: 60, at: 10_000),
            message(.noteOff, note: 60, at: 100_000),
            message(.noteOff, note: 60, at: 110_000)
        ])

        let first = try scheduler.drain(through: 0)
        let cancellation = scheduler.yieldToHuman(at: 7_000)
        let remaining = try scheduler.drain(through: 200_000)

        XCTAssertEqual(first.count, 1)
        XCTAssertEqual(cancellation.canceledNoteIDs.count, 1)
        XCTAssertEqual(remaining.map(\.message.kind), [.noteOff])
        XCTAssertEqual(remaining.first?.noteID, first.first?.noteID)
    }

    func testExplicitStopClearsPendingQueue() throws {
        var scheduler = try RollingMIDIScheduler()
        scheduler.submit([
            message(.noteOn, note: 60, at: 500_000),
            message(.noteOff, note: 60, at: 700_000)
        ])

        let cancellation = scheduler.cancelAllPending()

        XCTAssertEqual(cancellation.canceledEventIDs.count, 2)
        XCTAssertEqual(scheduler.pendingEventCount, 0)
        XCTAssertTrue(try scheduler.drain(through: 1_000_000).isEmpty)
    }

    func testAssignsStableNoteOnIndicesBeforeRollingCommitment() throws {
        var scheduler = try RollingMIDIScheduler(horizonMicroseconds: 50_000)
        scheduler.submit([
            message(.noteOn, note: 60, at: 100_000),
            message(.noteOff, note: 60, at: 160_000),
            message(.noteOn, note: 64, at: 300_000),
            message(.noteOff, note: 64, at: 360_000),
            message(.noteOn, note: 67, at: 500_000),
            message(.noteOff, note: 67, at: 560_000)
        ])

        let first = try scheduler.drain(through: 110_000)
        _ = scheduler.yieldToHuman(at: 400_000)
        let remaining = try scheduler.drain(through: 1_000_000)

        XCTAssertEqual(first.filter { $0.message.kind == .noteOn }.map(\.noteOnIndex), [0])
        XCTAssertEqual(remaining.filter { $0.message.kind == .noteOn }.map(\.noteOnIndex), [1])
        XCTAssertTrue(
            (first + remaining)
                .filter { $0.message.kind == .noteOff }
                .allSatisfy { $0.noteOnIndex == nil }
        )
    }

    private func message(
        _ kind: ScheduledMIDIMessageKind,
        note: UInt8,
        at offset: UInt64
    ) -> ScheduledMIDIMessage {
        ScheduledMIDIMessage(
            offsetMicroseconds: offset,
            kind: kind,
            channel: 3,
            note: note,
            velocity: kind == .noteOn ? 80 : 0
        )
    }
}
