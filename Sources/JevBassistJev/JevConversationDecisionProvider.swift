import Dispatch
import Foundation
import JevBassistCore

public struct JevConversationRequest: Codable, Equatable, Sendable {
    public let state: ConversationSelectionInput
    public let model: String
    public let questions: [String: JevChoiceQuestion]

    public init(input: ConversationSelectionInput, model: String = "jev-latest") {
        state = input
        self.model = model
        questions = [
            "response": JevChoiceQuestion(
                instructions: "Choose one supplied one-voice response. Favor a traceable relationship to the player's phrase, coherent modal voice leading, a purposeful arrival, and room for the player. Treat pitches and timing as immutable local candidates; use return when divergence is high.",
                criteria: Dictionary(uniqueKeysWithValues: input.candidates.map {
                    (
                        $0.id,
                        "\($0.relationship.rawValue); pitches \($0.pitches); intervals \($0.pitchIntervals); onsets \($0.relativeOnsets); durations \($0.durations); recognition \($0.recognition); contour \($0.contourIntegrity); voice leading \($0.voiceLeading); cadence \($0.cadence); continuity \($0.continuity); modal fit \($0.modalFit); space \($0.space); maximum leap \($0.maximumLeap)"
                    )
                })
            )
        ]
    }
}

public struct JevConversationResponse: Codable, Equatable, Sendable {
    public let model: String
    public let answers: [String: JevChoiceAnswer]
    public let usage: JevUsage

    public init(
        model: String,
        answers: [String: JevChoiceAnswer],
        usage: JevUsage
    ) {
        self.model = model
        self.answers = answers
        self.usage = usage
    }
}

public struct JevConversationTrace: Codable, Equatable, Sendable {
    public let request: JevConversationRequest
    public let response: JevConversationResponse?
    public let responseBody: String?
    public let latencyMilliseconds: Double
    public let deadlineMilliseconds: UInt64
    public let outcome: JevDecisionTraceOutcome
    public let error: String?
    public let candidateID: String?
}

public struct JevConversationEvaluation: Equatable, Sendable {
    public let candidateID: String?
    public let trace: JevConversationTrace
}

public struct JevConversationDecisionClient: Sendable {
    public let model: String
    public let deadlineMilliseconds: UInt64
    public let minimumConfidence: Double

    private let apiKey: String
    private let transport: any JevTransport

    public init(
        apiKey: String,
        model: String = "jev-latest",
        deadlineMilliseconds: UInt64 = 350,
        minimumConfidence: Double = 0.5,
        transport: any JevTransport = URLSessionJevTransport()
    ) {
        self.apiKey = apiKey
        self.model = model
        self.deadlineMilliseconds = min(max(deadlineMilliseconds, 1), 60_000)
        self.minimumConfidence = min(max(minimumConfidence, 0), 1)
        self.transport = transport
    }

    public func evaluate(
        _ input: ConversationSelectionInput
    ) async -> JevConversationEvaluation {
        let request = JevConversationRequest(input: input, model: model)
        let started = DispatchTime.now().uptimeNanoseconds
        var response: JevConversationResponse?
        var responseBody: String?
        do {
            let body = try JSONEncoder().encode(request)
            let transportResponse = try await sendWithDeadline(body)
            responseBody = String(data: transportResponse.body, encoding: .utf8)
            guard (200..<300).contains(transportResponse.statusCode) else {
                return result(
                    request: request,
                    response: nil,
                    responseBody: responseBody,
                    started: started,
                    outcome: .httpError,
                    error: "Jev returned HTTP \(transportResponse.statusCode)."
                )
            }
            response = try JSONDecoder().decode(
                JevConversationResponse.self,
                from: transportResponse.body
            )
            guard let answer = response?.answers["response"], answer.type == "choice" else {
                throw JevClientError.invalidAnswer("response choice is missing")
            }
            let expected = Set(input.candidates.map(\.id))
            guard Set(answer.probabilities.keys) == expected,
                  expected.contains(answer.choice),
                  answer.probabilities.values.allSatisfy({ $0.isFinite && (0...1).contains($0) }),
                  abs(answer.probabilities.values.reduce(0, +) - 1) <= 0.02,
                  answer.confidence.isFinite,
                  (0...1).contains(answer.confidence) else {
                throw JevClientError.invalidAnswer("response probabilities are invalid")
            }
            let accepted = answer.confidence >= minimumConfidence
            return result(
                request: request,
                response: response,
                responseBody: nil,
                started: started,
                outcome: accepted ? .ready : .lowConfidence,
                error: accepted ? nil : "Response confidence is below \(minimumConfidence).",
                candidateID: accepted ? answer.choice : nil
            )
        } catch is CancellationError {
            return result(
                request: request,
                response: response,
                responseBody: responseBody,
                started: started,
                outcome: .cancelled,
                error: "Jev request was cancelled."
            )
        } catch let error as JevClientError {
            let outcome: JevDecisionTraceOutcome = if case .timedOut = error {
                .timedOut
            } else {
                .invalidResponse
            }
            return result(
                request: request,
                response: response,
                responseBody: responseBody,
                started: started,
                outcome: outcome,
                error: error.description
            )
        } catch {
            return result(
                request: request,
                response: response,
                responseBody: responseBody,
                started: started,
                outcome: .transportError,
                error: String(describing: error)
            )
        }
    }

    private func sendWithDeadline(_ body: Data) async throws -> JevTransportResponse {
        let transport = transport
        let apiKey = apiKey
        let deadlineMilliseconds = deadlineMilliseconds
        return try await withThrowingTaskGroup(of: JevTransportResponse.self) { group in
            group.addTask {
                try await transport.send(
                    requestBody: body,
                    apiKey: apiKey,
                    timeoutInterval: Double(deadlineMilliseconds) / 1_000
                )
            }
            group.addTask {
                try await Task.sleep(nanoseconds: deadlineMilliseconds * 1_000_000)
                throw JevClientError.timedOut(deadlineMilliseconds)
            }
            guard let first = try await group.next() else {
                throw JevClientError.invalidHTTPResponse
            }
            group.cancelAll()
            return first
        }
    }

    private func result(
        request: JevConversationRequest,
        response: JevConversationResponse?,
        responseBody: String?,
        started: UInt64,
        outcome: JevDecisionTraceOutcome,
        error: String?,
        candidateID: String? = nil
    ) -> JevConversationEvaluation {
        let ended = DispatchTime.now().uptimeNanoseconds
        let elapsed = ended >= started ? ended - started : 0
        return JevConversationEvaluation(
            candidateID: candidateID,
            trace: JevConversationTrace(
                request: request,
                response: response,
                responseBody: responseBody,
                latencyMilliseconds: Double(elapsed) / 1_000_000,
                deadlineMilliseconds: deadlineMilliseconds,
                outcome: outcome,
                error: error,
                candidateID: candidateID
            )
        )
    }
}

public final class JevConversationDecisionProvider: ConversationDecisionProvider, @unchecked Sendable {
    public typealias TraceHandler = @Sendable (JevConversationTrace) -> Void

    private let lock = NSLock()
    private let client: JevConversationDecisionClient
    private let traceHandler: TraceHandler
    private var prepared: [UInt64: String] = [:]
    private var tasks: [UInt64: Task<Void, Never>] = [:]
    private var expiredThroughRevision: UInt64 = 0
    private var isCancelled = false

    public init(
        apiKey: String,
        model: String = "jev-latest",
        deadlineMilliseconds: UInt64 = 350,
        minimumConfidence: Double = 0.5,
        transport: any JevTransport = URLSessionJevTransport(),
        traceHandler: @escaping TraceHandler = { _ in }
    ) {
        client = JevConversationDecisionClient(
            apiKey: apiKey,
            model: model,
            deadlineMilliseconds: deadlineMilliseconds,
            minimumConfidence: minimumConfidence,
            transport: transport
        )
        self.traceHandler = traceHandler
    }

    deinit { cancelPendingDecisions() }

    public func prepare(_ input: ConversationSelectionInput) {
        lock.lock()
        let mayStart = !isCancelled
            && input.revision > expiredThroughRevision
            && tasks[input.revision] == nil
        lock.unlock()
        guard mayStart else { return }

        let client = self.client
        let traceHandler = self.traceHandler
        let task = Task { [weak self, client, traceHandler] in
            let evaluation = await client.evaluate(input)
            guard let self else {
                traceHandler(evaluation.trace)
                return
            }
            self.lock.withLock {
                self.tasks.removeValue(forKey: input.revision)
                if !self.isCancelled,
                   input.revision > self.expiredThroughRevision,
                   let candidateID = evaluation.candidateID {
                    self.prepared[input.revision] = candidateID
                }
            }
            traceHandler(evaluation.trace)
        }
        lock.lock()
        if input.revision > expiredThroughRevision, !isCancelled {
            tasks[input.revision] = task
        } else {
            task.cancel()
        }
        lock.unlock()
    }

    public func resolution(
        for input: ConversationSelectionInput
    ) -> ConversationSelectionResolution? {
        lock.lock()
        let candidateID = prepared.removeValue(forKey: input.revision)
        lock.unlock()
        return candidateID.map {
            ConversationSelectionResolution(candidateID: $0, source: .jev)
        }
    }

    public func expire(revision: UInt64) {
        lock.lock()
        expiredThroughRevision = max(expiredThroughRevision, revision)
        let stale = tasks.filter { $0.key <= expiredThroughRevision }.map(\.value)
        tasks = tasks.filter { $0.key > expiredThroughRevision }
        prepared = prepared.filter { $0.key > expiredThroughRevision }
        lock.unlock()
        stale.forEach { $0.cancel() }
    }

    public func cancelPendingDecisions() {
        lock.lock()
        guard !isCancelled else {
            lock.unlock()
            return
        }
        isCancelled = true
        let pending = Array(tasks.values)
        tasks.removeAll()
        prepared.removeAll()
        lock.unlock()
        pending.forEach { $0.cancel() }
    }
}
