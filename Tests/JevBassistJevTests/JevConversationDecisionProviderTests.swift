import Foundation
import JevBassistCore
@testable import JevBassistJev
import XCTest

final class JevConversationDecisionProviderTests: XCTestCase {
    func testRequestExposesOnlyBoundedCandidateIDs() throws {
        let request = JevConversationRequest(input: input())
        let criteria = try XCTUnwrap(request.questions["response"]?.criteria)

        XCTAssertEqual(request.state.revision, 7)
        XCTAssertEqual(Set(criteria.keys), Set(["echo", "inversion", "return"]))
        XCTAssertEqual(request.questions["response"]?.type, "choice")
        XCTAssertEqual(request.state.state?.intent, .question)
        XCTAssertEqual(request.state.state?.turnState, .awaitingReply)
        XCTAssertTrue(
            request.questions["response"]?.instructions.contains(
                "previous response 9"
            ) == true
        )
    }

    func testClientAcceptsTypedCandidateAndTraceContainsNoSecret() async throws {
        let transport = ConversationTransport(response: response(choice: "inversion"))
        let secret = "conversation-secret"
        let client = JevConversationDecisionClient(
            apiKey: secret,
            transport: transport
        )

        let evaluation = await client.evaluate(input())

        XCTAssertEqual(evaluation.candidateID, "inversion")
        XCTAssertEqual(evaluation.trace.outcome, .ready)
        let text = String(
            data: try JSONEncoder().encode(evaluation.trace),
            encoding: .utf8
        )
        XCTAssertFalse(text?.contains(secret) == true)
    }

    func testExpiredRevisionRejectsLateCompletion() {
        let completed = DispatchSemaphore(value: 0)
        let transport = ConversationTransport(
            response: response(choice: "inversion"),
            delayNanoseconds: 40_000_000
        )
        let provider = JevConversationDecisionProvider(
            apiKey: "test-key",
            deadlineMilliseconds: 200,
            transport: transport,
            traceHandler: { _ in completed.signal() }
        )
        let selection = input()

        provider.prepare(selection)
        provider.expire(revision: selection.revision)
        XCTAssertEqual(completed.wait(timeout: .now() + 1), .success)
        XCTAssertNil(provider.resolution(for: selection))
    }

    private func input() -> ConversationSelectionInput {
        ConversationSelectionInput(
            revision: 7,
            mode: .dorian,
            originMotifID: 1,
            sourceMotifID: 3,
            context: ConversationDevelopmentContext(
                generation: 2,
                accumulatedDivergence: 0.8,
                originSimilarity: 0.75,
                notesPerBeat: 1.2,
                registerShift: 2,
                originDurationBeats: 2.5
            ),
            candidates: [
                summary(id: "echo", relationship: .echo),
                summary(id: "inversion", relationship: .inversion),
                summary(id: "return", relationship: .originalReturn)
            ],
            localCandidateID: "inversion",
            state: conversationState()
        )
    }

    private func conversationState() -> ConversationStateSummary {
        func material(id: UInt64, pitches: [UInt8]) -> ConversationMaterialSummary {
            ConversationMaterialSummary(
                id: id,
                response: pitches.enumerated().map { index, pitch in
                    ConversationResponseNote(
                        note: pitch,
                        velocity: 72,
                        relativeOnsetBeats: Double(index) * 0.5,
                        durationBeats: 0.35
                    )
                }
            )
        }
        return ConversationStateSummary(
            themeRevision: 4,
            intent: .question,
            turnState: .awaitingReply,
            interaction: InteractionEvidence(
                kind: .imitation,
                confidence: 0.84,
                pitchContour: 0.9,
                intervalShape: 0.8,
                rhythm: 0.86,
                duration: 0.7,
                responseDelayBeats: 1.5
            ),
            origin: material(id: 1, pitches: [62, 65, 67]),
            sharedTheme: material(id: 3, pitches: [64, 67, 69]),
            latestHuman: material(id: 8, pitches: [67, 70, 72]),
            previousResponse: material(id: 9, pitches: [65, 68, 70])
        )
    }

    private func summary(
        id: String,
        relationship: ConversationRelationship
    ) -> ConversationCandidateSummary {
        ConversationCandidateSummary(
            candidate: ConversationResponseCandidate(
                id: id,
                relationship: relationship,
                notes: [],
                score: ConversationScore(
                    recognition: 0.8,
                    space: 0.8,
                    voiceLeading: 0.8,
                    modalFit: 1
                )
            )
        )
    }

    private func response(choice: String) -> JevConversationResponse {
        JevConversationResponse(
            model: "jev-test",
            answers: [
                "response": JevChoiceAnswer(
                    type: "choice",
                    choice: choice,
                    probabilities: [
                        "echo": 0.1,
                        "inversion": 0.8,
                        "return": 0.1
                    ],
                    confidence: 0.85
                )
            ],
            usage: JevUsage(inputTokens: 120, outputTokens: 12)
        )
    }
}

private final class ConversationTransport: JevTransport, @unchecked Sendable {
    private let data: Data
    private let delayNanoseconds: UInt64

    init(response: JevConversationResponse, delayNanoseconds: UInt64 = 0) {
        data = try! JSONEncoder().encode(response)
        self.delayNanoseconds = delayNanoseconds
    }

    func send(
        requestBody: Data,
        apiKey: String,
        timeoutInterval: TimeInterval
    ) async throws -> JevTransportResponse {
        if delayNanoseconds > 0 {
            try await Task.sleep(nanoseconds: delayNanoseconds)
        }
        return JevTransportResponse(statusCode: 200, body: data)
    }
}
