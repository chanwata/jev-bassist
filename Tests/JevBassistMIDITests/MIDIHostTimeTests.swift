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
}
