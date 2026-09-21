import Foundation
import JevBassistCore
@testable import JevBassistJev
import XCTest

final class JevDecisionProviderTests: XCTestCase {
    func testRequestEncodesOfficialSystemOneShape() throws {
        let request = JevSystemOneRequest(input: makeInput(targetBarIndex: 4))
        let data = try JSONEncoder().encode(request)
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        let state = try XCTUnwrap(object["state"] as? [String: Any])
        let questions = try XCTUnwrap(object["questions"] as? [String: Any])
        let activity = try XCTUnwrap(questions["activity"] as? [String: Any])
        let fill = try XCTUnwrap(questions["fill"] as? [String: Any])

        XCTAssertEqual(object["model"] as? String, "jev-latest")
        XCTAssertEqual(state["target_bar_index"] as? Int, 4)
        XCTAssertEqual(state["accompaniment_style"] as? String, "ambient")
        XCTAssertEqual(state["note_density_per_beat"] as? Double, 1)
        XCTAssertEqual((state["next_chord"] as? [String: Any])?["root"] as? String, "G")
        XCTAssertEqual(activity["type"] as? String, "choice")
        XCTAssertNotNil(activity["criteria"] as? [String: String])
        XCTAssertTrue(
            (activity["instructions"] as? String)?.contains("sustained ambient") == true
        )
        XCTAssertEqual(fill["type"] as? String, "noul")
        XCTAssertEqual(
            Set(questions.keys),
            Set(["activity", "relationship", "motion", "fill"])
        )
    }

    func testMemoryStyleUsesMotifRecallQuestions() throws {
        let request = JevSystemOneRequest(
            input: makeInput(targetBarIndex: 6, style: .memory)
        )

        XCTAssertEqual(request.state.accompanimentStyle, "memory")
        XCTAssertTrue(request.questions.activity.instructions.contains("recent motif"))
        XCTAssertTrue(request.questions.relationship.instructions.contains("listen"))
        XCTAssertTrue(request.questions.motion.instructions.contains("transformation"))
    }

    func testFugueStyleUsesImitativeCounterpointQuestions() throws {
        let request = JevSystemOneRequest(
            input: makeInput(
                targetBarIndex: 7,
                style: .fugue,
                developmentStage: .stretto,
                mode: .dorian,
                tonalCenterPitchClass: 2
            )
        )

        XCTAssertEqual(request.state.accompanimentStyle, "fugue")
        XCTAssertEqual(request.state.developmentStage, "stretto")
        XCTAssertEqual(request.state.mode, "dorian")
        XCTAssertEqual(request.state.tonalCenterPitchClass, 2)
        XCTAssertTrue(request.questions.activity.instructions.contains("motif-development"))
        XCTAssertTrue(request.questions.relationship.instructions.contains("temporal"))
        XCTAssertTrue(request.questions.motion.instructions.contains("contrapuntal"))
    }

    func testClientMapsTypedAnswersAndLogsFullSecretFreeTrace() async throws {
        let response = makeResponse()
        let transport = StubTransport(response: response)
        let secret = "test-secret-that-must-not-be-logged"
        let client = JevDecisionClient(apiKey: secret, transport: transport)

        let evaluation = await client.evaluate(makeInput(targetBarIndex: 5))

        let decision = try XCTUnwrap(evaluation.decision)
        XCTAssertEqual(decision.activity, .normal)
        XCTAssertEqual(decision.relationship, .follow)
        XCTAssertEqual(decision.motion, .step)
        XCTAssertTrue(decision.fill)
        XCTAssertEqual(decision.confidence, 0.6, accuracy: 0.000_001)
        XCTAssertEqual(evaluation.trace.outcome, .ready)
        XCTAssertEqual(evaluation.trace.response, response)
        XCTAssertEqual(evaluation.trace.request.state.targetBarIndex, 5)
        XCTAssertGreaterThanOrEqual(evaluation.trace.latencyMilliseconds, 0)

        let traceData = try JSONEncoder().encode(evaluation.trace)
        let traceText = try XCTUnwrap(String(data: traceData, encoding: .utf8))
        XCTAssertFalse(traceText.contains(secret))
        XCTAssertEqual(transport.receivedAPIKey, secret)
    }

    func testLowConfidenceResultUsesDeterministicRuleFallback() throws {
        let transport = StubTransport(response: makeResponse(activityConfidence: 0.4))
        let completed = DispatchSemaphore(value: 0)
        let provider = JevDecisionProvider(
            apiKey: "test-key",
            transport: transport,
            traceHandler: { _ in completed.signal() }
        )
        let input = makeInput(targetBarIndex: 5)

        provider.prepare(input)
        XCTAssertEqual(completed.wait(timeout: .now() + 1), .success)
        let resolution = provider.resolution(for: input)

        XCTAssertEqual(resolution.source, .fallback)
        XCTAssertEqual(resolution.decision.activity, .sparse)
        XCTAssertEqual(resolution.decision.relationship, .follow)
        XCTAssertEqual(resolution.decision.motion, .leap)
    }

    func testPreparedResultIsReadWithoutWaitingAtBoundary() throws {
        let completed = DispatchSemaphore(value: 0)
        let provider = JevDecisionProvider(
            apiKey: "test-key",
            transport: StubTransport(response: makeResponse()),
            traceHandler: { _ in completed.signal() }
        )
        let input = makeInput(targetBarIndex: 5)

        provider.prepare(input)
        XCTAssertEqual(completed.wait(timeout: .now() + 1), .success)
        let resolution = provider.resolution(for: input)

        XCTAssertEqual(resolution.source, .jev)
        XCTAssertEqual(resolution.decision.activity, .normal)
    }

    func testDeadlineReturnsTimeoutInsteadOfWaitingForTransport() async {
        let client = JevDecisionClient(
            apiKey: "test-key",
            deadlineMilliseconds: 10,
            transport: SlowTransport()
        )

        let evaluation = await client.evaluate(makeInput(targetBarIndex: 5))

        XCTAssertNil(evaluation.decision)
        XCTAssertEqual(evaluation.trace.outcome, .timedOut)
        XCTAssertEqual(evaluation.trace.deadlineMilliseconds, 10)
    }

    func testCancellingProviderCancelsInFlightRequest() throws {
        let completed = DispatchSemaphore(value: 0)
        let outcome = LockedValue<JevDecisionTraceOutcome?>(nil)
        let provider = JevDecisionProvider(
            apiKey: "test-key",
            deadlineMilliseconds: 1_000,
            transport: SlowTransport(),
            traceHandler: { trace in
                outcome.value = trace.outcome
                completed.signal()
            }
        )

        provider.prepare(makeInput(targetBarIndex: 5))
        provider.cancelPendingDecisions()

        XCTAssertEqual(completed.wait(timeout: .now() + 1), .success)
        XCTAssertEqual(outcome.value, .cancelled)
    }

    private func makeInput(
        targetBarIndex: Int,
        style: AccompanimentStyle = .ambient,
        developmentStage: MotifDevelopmentStage? = nil,
        mode: MusicalMode? = nil,
        tonalCenterPitchClass: UInt8? = nil
    ) -> BassDecisionInput {
        BassDecisionInput(
            state: MusicalState(
                noteOnCount: 4,
                noteDensityPerBeat: 1,
                averageVelocity: 84,
                averageNote: 63.5,
                lowestNote: 60,
                highestNote: 67,
                heldNotes: [
                    HeldNote(
                        channel: 1,
                        note: 64,
                        velocity: 82,
                        startedAtMicroseconds: 100_000
                    )
                ],
                pulse: PulseEstimate(bpm: 120, confidence: 0.8),
                chordCandidates: [
                    ChordCandidate(
                        rootPitchClass: 0,
                        quality: .major,
                        confidence: 0.9
                    )
                ]
            ),
            chord: ChordCandidate(
                rootPitchClass: 0,
                quality: .major,
                confidence: 0.9
            ),
            nextChord: ChordCandidate(
                rootPitchClass: 7,
                quality: .major,
                confidence: 1
            ),
            style: style,
            developmentStage: developmentStage,
            mode: mode,
            tonalCenterPitchClass: tonalCenterPitchClass,
            isHeldChord: false,
            targetBarIndex: targetBarIndex
        )
    }

    private func makeResponse(activityConfidence: Double = 0.8) -> JevSystemOneResponse {
        JevSystemOneResponse(
            model: "jev-1.13.0",
            answers: JevBassAnswers(
                activity: JevChoiceAnswer(
                    type: "choice",
                    choice: "normal",
                    probabilities: [
                        "rest": 0.05,
                        "sparse": 0.10,
                        "normal": 0.80,
                        "busy": 0.05
                    ],
                    confidence: activityConfidence
                ),
                relationship: JevChoiceAnswer(
                    type: "choice",
                    choice: "follow",
                    probabilities: [
                        "follow": 0.80,
                        "contrast": 0.10,
                        "hold": 0.10
                    ],
                    confidence: 0.7
                ),
                motion: JevChoiceAnswer(
                    type: "choice",
                    choice: "step",
                    probabilities: [
                        "root": 0.05,
                        "step": 0.85,
                        "approach": 0.05,
                        "leap": 0.05
                    ],
                    confidence: 0.9
                ),
                fill: JevNoulAnswer(type: "noul", noul: 0.8)
            ),
            usage: JevUsage(inputTokens: 320, outputTokens: 42)
        )
    }
}

private final class StubTransport: JevTransport, @unchecked Sendable {
    private let responseData: Data
    private let lock = NSLock()
    private var storedAPIKey: String?

    var receivedAPIKey: String? {
        lock.lock()
        defer { lock.unlock() }
        return storedAPIKey
    }

    init(response: JevSystemOneResponse) {
        responseData = try! JSONEncoder().encode(response)
    }

    func send(
        requestBody: Data,
        apiKey: String,
        timeoutInterval: TimeInterval
    ) async throws -> JevTransportResponse {
        lock.withLock {
            storedAPIKey = apiKey
        }
        return JevTransportResponse(statusCode: 200, body: responseData)
    }
}

private struct SlowTransport: JevTransport {
    func send(
        requestBody: Data,
        apiKey: String,
        timeoutInterval: TimeInterval
    ) async throws -> JevTransportResponse {
        try await Task.sleep(nanoseconds: 2_000_000_000)
        return JevTransportResponse(statusCode: 200, body: Data())
    }
}

private final class LockedValue<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var storedValue: Value

    init(_ value: Value) {
        storedValue = value
    }

    var value: Value {
        get {
            lock.lock()
            defer { lock.unlock() }
            return storedValue
        }
        set {
            lock.lock()
            storedValue = newValue
            lock.unlock()
        }
    }
}
