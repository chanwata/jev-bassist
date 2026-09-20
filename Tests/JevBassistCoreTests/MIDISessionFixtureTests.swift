import Foundation
import XCTest
@testable import JevBassistCore

final class MIDISessionFixtureTests: XCTestCase {
    func testCaptureCodecAndReplayRoundTrip() throws {
        let startedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let capture = MIDISessionCapture(startedAt: startedAt)
        capture.append(
            MIDIEvent(
                receivedAt: startedAt.addingTimeInterval(0.125),
                hostTime: 10,
                channel: 1,
                kind: .noteOn,
                note: 60,
                velocity: 96
            )
        )
        capture.append(
            MIDIEvent(
                receivedAt: startedAt.addingTimeInterval(0.5),
                hostTime: 20,
                channel: 1,
                kind: .noteOff,
                note: 60,
                velocity: 32
            )
        )

        let fixture = try capture.fixture(
            sourceNames: ["Steinberg UR22mkII"],
            endedAt: startedAt.addingTimeInterval(1)
        )
        let data = try MIDISessionFixtureCodec.encode(fixture)
        let decoded = try MIDISessionFixtureCodec.decode(data)

        XCTAssertEqual(decoded, fixture)
        XCTAssertEqual(decoded.formatVersion, 1)
        XCTAssertEqual(decoded.durationMicroseconds, 1_000_000)
        XCTAssertEqual(decoded.events.map(\.offsetMicroseconds), [125_000, 500_000])
        XCTAssertEqual(decoded.sourceNames, ["Steinberg UR22mkII"])

        let replayed = decoded.replayedEvents()
        XCTAssertEqual(replayed.map(\.kind), [.noteOn, .noteOff])
        XCTAssertEqual(replayed.map(\.hostTime), [10, 20])
        XCTAssertEqual(
            replayed[0].receivedAt.timeIntervalSince(startedAt),
            0.125,
            accuracy: 0.000_001
        )
    }

    func testCaptureClampsOutOfOrderReceiptTimesToMonotonicOffsets() throws {
        let startedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let capture = MIDISessionCapture(startedAt: startedAt)
        capture.append(event(at: startedAt.addingTimeInterval(0.2), note: 60))
        capture.append(event(at: startedAt.addingTimeInterval(0.1), note: 62))

        let fixture = try capture.fixture(
            sourceNames: ["test"],
            endedAt: startedAt.addingTimeInterval(0.3)
        )

        XCTAssertEqual(fixture.events.map(\.offsetMicroseconds), [200_000, 200_000])
    }

    func testRejectsUnsupportedFormatVersion() {
        XCTAssertThrowsError(
            try MIDISessionFixture(
                formatVersion: 99,
                startedAt: Date(timeIntervalSince1970: 0),
                durationMicroseconds: 0,
                sourceNames: [],
                events: []
            )
        ) { error in
            XCTAssertEqual(error as? MIDISessionFixtureError, .unsupportedFormatVersion(99))
        }
    }

    func testRejectsNonMonotonicEvents() {
        let events = [
            sessionEvent(at: 200, note: 60),
            sessionEvent(at: 100, note: 62)
        ]

        XCTAssertThrowsError(
            try MIDISessionFixture(
                startedAt: Date(timeIntervalSince1970: 0),
                durationMicroseconds: 300,
                sourceNames: [],
                events: events
            )
        ) { error in
            XCTAssertEqual(error as? MIDISessionFixtureError, .nonMonotonicEvent(index: 1))
        }
    }

    func testRejectsEventAfterSessionEnd() {
        XCTAssertThrowsError(
            try MIDISessionFixture(
                startedAt: Date(timeIntervalSince1970: 0),
                durationMicroseconds: 99,
                sourceNames: [],
                events: [sessionEvent(at: 100, note: 60)]
            )
        ) { error in
            XCTAssertEqual(error as? MIDISessionFixtureError, .eventAfterSessionEnd(index: 0))
        }
    }

    private func event(at date: Date, note: UInt8) -> MIDIEvent {
        MIDIEvent(
            receivedAt: date,
            hostTime: 0,
            channel: 1,
            kind: .noteOn,
            note: note,
            velocity: 80
        )
    }

    private func sessionEvent(at offset: UInt64, note: UInt8) -> SessionMIDIEvent {
        SessionMIDIEvent(
            offsetMicroseconds: offset,
            hostTime: 0,
            channel: 1,
            kind: .noteOn,
            note: note,
            velocity: 80
        )
    }
}
