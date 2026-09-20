import XCTest
@testable import JevBassistCore

final class ChordProgressionTests: XCTestCase {
    func testParsesCommonTriadAndSeventhSymbols() throws {
        let chords = try ChordProgressionParser.parse("Dm7, G7, Cmaj7, Bb, F#dim, EM7")

        XCTAssertEqual(chords.map(\.rootPitchClass), [2, 7, 0, 10, 6, 4])
        XCTAssertEqual(
            chords.map(\.quality),
            [.minor, .major, .major, .major, .diminished, .major]
        )
    }

    func testRejectsEmptyAndUnsupportedSymbols() {
        XCTAssertThrowsError(try ChordProgressionParser.parse(""))
        XCTAssertThrowsError(try ChordProgressionParser.parse("Csus4"))
        XCTAssertThrowsError(try ChordProgressionParser.parse("C,,G"))
    }
}
