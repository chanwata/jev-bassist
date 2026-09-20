import XCTest
@testable import JevBassistMIDI

final class MIDIHostTimeTests: XCTestCase {
    func testMicrosecondConversionRoundTrips() {
        let start = MIDIHostTime.now
        let end = MIDIHostTime.addingMicroseconds(1_234_567, to: start)
        let measured = MIDIHostTime.microseconds(from: start, to: end)

        XCTAssertLessThanOrEqual(abs(Int64(measured) - 1_234_567), 1)
    }

    func testEarlierHostTimeClampsToZero() {
        XCTAssertEqual(MIDIHostTime.microseconds(from: 200, to: 100), 0)
    }

    func testControlChangeEncodesChannelVolume() throws {
        XCTAssertEqual(
            try MIDIControlChangeEncoder.bytes(controller: 7, value: 72, channel: 2),
            [0xB1, 7, 72]
        )
    }

    func testControlChangeRejectsOutOfRangeData() {
        XCTAssertThrowsError(
            try MIDIControlChangeEncoder.bytes(controller: 7, value: 128, channel: 2)
        )
        XCTAssertThrowsError(
            try MIDIControlChangeEncoder.bytes(controller: 7, value: 72, channel: 17)
        )
    }
}
