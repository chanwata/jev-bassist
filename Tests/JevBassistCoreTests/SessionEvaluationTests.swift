import Foundation
import XCTest
@testable import JevBassistCore

final class SessionEvaluationTests: XCTestCase {
    func testFixtureEvaluationIsDeterministicAndCapturesPlans() throws {
        let fixture = try loadFixture()
        let configuration = try fugueConfiguration()
        let evaluator = LocalBassistSessionEvaluator()

        let first = try evaluator.evaluate(
            fixture: fixture,
            configuration: configuration
        )
        let second = try evaluator.evaluate(
            fixture: fixture,
            configuration: configuration
        )

        XCTAssertEqual(first, second)
        XCTAssertEqual(
            try SessionEvaluationCodec.encode(first),
            try SessionEvaluationCodec.encode(second)
        )
        XCTAssertEqual(first.formatVersion, 1)
        XCTAssertEqual(first.policy, .rules)
        XCTAssertEqual(first.input, fixture)
        XCTAssertEqual(first.configuration.style, .fugue)
        XCTAssertEqual(first.configuration.mode, .dorian)
        XCTAssertEqual(first.plans.map(\.developmentStage), [.answer, .sequence])
        XCTAssertFalse(first.plans[0].phrase.messages.isEmpty)
        XCTAssertTrue(
            first.plans.flatMap { $0.phrase.messages }.allSatisfy { $0.channel == 3 }
        )
    }

    func testEvaluationCodecRoundTripsAndRefusesOverwrite() throws {
        let trace = try LocalBassistSessionEvaluator().evaluate(
            fixture: loadFixture(),
            configuration: fugueConfiguration()
        )
        let data = try SessionEvaluationCodec.encode(trace)

        XCTAssertEqual(try SessionEvaluationCodec.decode(data), trace)

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: false
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("evaluation.json")

        try SessionEvaluationCodec.write(trace, to: url)

        XCTAssertEqual(
            try SessionEvaluationCodec.decode(Data(contentsOf: url)),
            trace
        )
        XCTAssertThrowsError(try SessionEvaluationCodec.write(trace, to: url))
    }

    func testEvaluationCodecRejectsUnknownTraceVersion() throws {
        let trace = try LocalBassistSessionEvaluator().evaluate(
            fixture: loadFixture(),
            configuration: fugueConfiguration()
        )
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: SessionEvaluationCodec.encode(trace))
                as? [String: Any]
        )
        object["formatVersion"] = 99
        let data = try JSONSerialization.data(withJSONObject: object)

        XCTAssertThrowsError(try SessionEvaluationCodec.decode(data)) { error in
            XCTAssertEqual(
                error as? SessionEvaluationError,
                .unsupportedFormatVersion(99)
            )
        }
    }

    private func loadFixture() throws -> MIDISessionFixture {
        let url = try XCTUnwrap(
            Bundle.module.url(
                forResource: "conversation-four-note",
                withExtension: "json"
            )
        )
        return try MIDISessionFixtureCodec.decode(Data(contentsOf: url))
    }

    private func fugueConfiguration() throws -> LocalBassistConfiguration {
        try LocalBassistConfiguration(
            musicalState: MusicalStateConfiguration(tempoBPM: 120, beatsPerBar: 4),
            introBars: 0,
            outputChannel: 3,
            style: .fugue,
            mode: .dorian
        )
    }
}
