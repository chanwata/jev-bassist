import Foundation
import XCTest
@testable import JevBassistCore

final class MIDIByteParserTests: XCTestCase {
    private let receivedAt = Date(timeIntervalSince1970: 1_700_000_000)

    func testParsesNoteOnAndNoteOff() {
        var parser = MIDIByteParser()

        let events = parser.parse(
            [0x91, 60, 100, 0x81, 60, 45],
            hostTime: 123,
            receivedAt: receivedAt
        )

        XCTAssertEqual(events, [
            MIDIEvent(receivedAt: receivedAt, hostTime: 123, channel: 2, kind: .noteOn, note: 60, velocity: 100),
            MIDIEvent(receivedAt: receivedAt, hostTime: 123, channel: 2, kind: .noteOff, note: 60, velocity: 45)
        ])
    }

    func testNormalizesVelocityZeroNoteOnToNoteOff() {
        var parser = MIDIByteParser()

        let events = parser.parse(
            [0x90, 69, 0],
            hostTime: 1,
            receivedAt: receivedAt
        )

        XCTAssertEqual(events.first?.kind, .noteOff)
        XCTAssertEqual(events.first?.note, 69)
        XCTAssertEqual(events.first?.velocity, 0)
    }

    func testRetainsRunningStatusAcrossCalls() {
        var parser = MIDIByteParser()

        let first = parser.parse(
            [0x90, 60],
            hostTime: 10,
            receivedAt: receivedAt
        )
        let second = parser.parse(
            [90, 64, 80],
            hostTime: 11,
            receivedAt: receivedAt
        )

        XCTAssertTrue(first.isEmpty)
        XCTAssertEqual(second.map(\.note), [60, 64])
        XCTAssertEqual(second.map(\.velocity), [90, 80])
    }

    func testRealtimeByteDoesNotBreakMessageOrRunningStatus() {
        var parser = MIDIByteParser()

        let events = parser.parse(
            [0x90, 60, 0xF8, 100, 62, 0xFE, 110],
            hostTime: 20,
            receivedAt: receivedAt
        )

        XCTAssertEqual(events.map(\.note), [60, 62])
        XCTAssertEqual(events.map(\.velocity), [100, 110])
    }

    func testIgnoresSysExUntilTerminator() {
        var parser = MIDIByteParser()

        let events = parser.parse(
            [0xF0, 0x01, 0x02, 0xF8, 0xF7, 0x90, 67, 88],
            hostTime: 30,
            receivedAt: receivedAt
        )

        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.note, 67)
    }

    func testChannelStatusAbortsTruncatedSysEx() {
        var parser = MIDIByteParser()

        let events = parser.parse(
            [0xF0, 0x01, 0x02, 0x90, 65, 91],
            hostTime: 31,
            receivedAt: receivedAt
        )

        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.kind, .noteOn)
        XCTAssertEqual(events.first?.note, 65)
        XCTAssertEqual(events.first?.velocity, 91)
    }

    func testConsumesUnsupportedChannelMessagesWithoutLosingAlignment() {
        var parser = MIDIByteParser()

        let events = parser.parse(
            [0xC0, 12, 0xD0, 70, 0x90, 72, 99],
            hostTime: 40,
            receivedAt: receivedAt
        )

        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.note, 72)
    }

    func testNoteNamesCoverMIDIBoundsAndConcertA() {
        XCTAssertEqual(MIDINoteName.name(for: 0), "C-1")
        XCTAssertEqual(MIDINoteName.name(for: 69), "A4")
        XCTAssertEqual(MIDINoteName.name(for: 127), "G9")
    }

    func testRunningStatusIsIsolatedBetweenStreams() {
        var parser = MIDIStreamParser<String>()

        let partialA = parser.parse(
            [0x90, 60],
            streamID: "keyboard-a",
            hostTime: 50,
            receivedAt: receivedAt
        )
        let completeB = parser.parse(
            [0x81, 64, 7],
            streamID: "keyboard-b",
            hostTime: 51,
            receivedAt: receivedAt
        )
        let completeA = parser.parse(
            [100],
            streamID: "keyboard-a",
            hostTime: 52,
            receivedAt: receivedAt
        )

        XCTAssertTrue(partialA.isEmpty)
        XCTAssertEqual(completeB.map(\.kind), [.noteOff])
        XCTAssertEqual(completeB.map(\.note), [64])
        XCTAssertEqual(completeA.map(\.kind), [.noteOn])
        XCTAssertEqual(completeA.map(\.note), [60])
        XCTAssertEqual(completeA.map(\.velocity), [100])
    }
}
