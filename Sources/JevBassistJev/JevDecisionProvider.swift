import Dispatch
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import JevBassistCore

public struct JevHeldNoteState: Codable, Equatable, Sendable {
    public let channel: UInt8
    public let note: UInt8
    public let velocity: UInt8

    public init(channel: UInt8, note: UInt8, velocity: UInt8) {
        self.channel = channel
        self.note = note
        self.velocity = velocity
    }
}

public struct JevChordState: Codable, Equatable, Sendable {
    public let root: String
    public let quality: String
    public let confidence: Double

    public init(root: String, quality: String, confidence: Double) {
        self.root = root
        self.quality = quality
        self.confidence = confidence
    }
}

/// The compact, serializable state sent to Jev. It contains musical facts,
/// never raw MIDI bytes or credentials.
public struct JevBassState: Codable, Equatable, Sendable {
    public let targetBarIndex: Int
    public let phrasePosition: Int
    public let noteOnCount: Int
    public let noteDensityPerBeat: Double
    public let averageVelocity: Double?
    public let averageNote: Double?
    public let lowestNote: UInt8?
    public let highestNote: UInt8?
    public let heldNotes: [JevHeldNoteState]
    public let pulseBPM: Double?
    public let pulseConfidence: Double?
    public let chord: JevChordState?
    public let isHeldChord: Bool

    public init(input: BassDecisionInput) {
        targetBarIndex = input.targetBarIndex
        phrasePosition = input.targetBarIndex % 4
        noteOnCount = input.state.noteOnCount
        noteDensityPerBeat = input.state.noteDensityPerBeat
        averageVelocity = input.state.averageVelocity
        averageNote = input.state.averageNote
        lowestNote = input.state.lowestNote
        highestNote = input.state.highestNote
        heldNotes = input.state.heldNotes.map {
            JevHeldNoteState(
                channel: $0.channel,
                note: $0.note,
                velocity: $0.velocity
            )
        }
        pulseBPM = input.state.pulse?.bpm
        pulseConfidence = input.state.pulse?.confidence
        chord = input.chord.map {
            JevChordState(
                root: $0.rootName,
                quality: $0.quality.rawValue,
                confidence: $0.confidence
            )
        }
        isHeldChord = input.isHeldChord
    }

    private enum CodingKeys: String, CodingKey {
        case targetBarIndex = "target_bar_index"
        case phrasePosition = "phrase_position_in_four_bar_cycle"
        case noteOnCount = "note_on_count"
        case noteDensityPerBeat = "note_density_per_beat"
        case averageVelocity = "average_velocity"
        case averageNote = "average_note"
        case lowestNote = "lowest_note"
        case highestNote = "highest_note"
        case heldNotes = "held_notes"
        case pulseBPM = "pulse_bpm"
        case pulseConfidence = "pulse_confidence"
        case chord
        case isHeldChord = "is_held_chord"
    }
}

public struct JevChoiceQuestion: Codable, Equatable, Sendable {
    public let type: String
    public let instructions: String
    public let criteria: [String: String]

    public init(instructions: String, criteria: [String: String]) {
        type = "choice"
        self.instructions = instructions
        self.criteria = criteria
    }
}

public struct JevNoulCriteria: Codable, Equatable, Sendable {
    public let trueDescription: String
    public let falseDescription: String

    public init(trueDescription: String, falseDescription: String) {
        self.trueDescription = trueDescription
        self.falseDescription = falseDescription
    }

    private enum CodingKeys: String, CodingKey {
        case trueDescription = "true"
        case falseDescription = "false"
    }
}

public struct JevNoulQuestion: Codable, Equatable, Sendable {
    public let type: String
    public let instructions: String
    public let criteria: JevNoulCriteria

    public init(instructions: String, criteria: JevNoulCriteria) {
        type = "noul"
        self.instructions = instructions
        self.criteria = criteria
    }
}

public struct JevBassQuestions: Codable, Equatable, Sendable {
    public let activity: JevChoiceQuestion
    public let relationship: JevChoiceQuestion
    public let motion: JevChoiceQuestion
    public let fill: JevNoulQuestion

    public static let standard = JevBassQuestions(
        activity: JevChoiceQuestion(
            instructions: "Choose the bass activity for the target bar. Leave room when the human is dense, and avoid activity when harmony is uncertain.",
            criteria: [
                "rest": "No bass attacks because usable harmony is absent or the safest musical response is silence.",
                "sparse": "Two widely spaced attacks that leave substantial room for the human player.",
                "normal": "One supportive attack per beat for a clear chord and available musical space.",
                "busy": "Eighth-note activity only when the human clearly leaves space and extra momentum is appropriate."
            ]
        ),
        relationship: JevChoiceQuestion(
            instructions: "Choose how the bass should relate to the human performance in the target bar.",
            criteria: [
                "follow": "Reinforce the player's current energy and harmonic direction.",
                "contrast": "Create space or a complementary response instead of matching dense human activity.",
                "hold": "Maintain the established harmonic attitude while the human pauses or the evidence is limited."
            ]
        ),
        motion: JevChoiceQuestion(
            instructions: "Choose one bounded pitch-motion behavior for the bass phrase.",
            criteria: [
                "root": "Anchor the phrase primarily on the chord root.",
                "step": "Move through nearby chord tones in a smooth supportive line.",
                "approach": "Alternate the root with a chromatic approach into it.",
                "leap": "Alternate root and fifth for a wider but still stable motion."
            ]
        ),
        fill: JevNoulQuestion(
            instructions: "Should the final bass attack become a restrained approach note into the following bar?",
            criteria: JevNoulCriteria(
                trueDescription: "The target bar closes a phrase and the human leaves enough space for a small fill.",
                falseDescription: "The player is dense, harmony is uncertain, or a plain ending would listen better."
            )
        )
    )

    public init(
        activity: JevChoiceQuestion,
        relationship: JevChoiceQuestion,
        motion: JevChoiceQuestion,
        fill: JevNoulQuestion
    ) {
        self.activity = activity
        self.relationship = relationship
        self.motion = motion
        self.fill = fill
    }
}

public struct JevSystemOneRequest: Codable, Equatable, Sendable {
    public let state: JevBassState
    public let model: String
    public let questions: JevBassQuestions

    public init(
        input: BassDecisionInput,
        model: String = "jev-latest",
        questions: JevBassQuestions = .standard
    ) {
        state = JevBassState(input: input)
        self.model = model
        self.questions = questions
    }
}

public struct JevChoiceAnswer: Codable, Equatable, Sendable {
    public let type: String
    public let choice: String
    public let probabilities: [String: Double]
    public let confidence: Double

    public init(
        type: String,
        choice: String,
        probabilities: [String: Double],
        confidence: Double
    ) {
        self.type = type
        self.choice = choice
        self.probabilities = probabilities
        self.confidence = confidence
    }
}

public struct JevNoulAnswer: Codable, Equatable, Sendable {
    public let type: String
    public let noul: Double

    public init(type: String, noul: Double) {
        self.type = type
        self.noul = noul
    }
}

public struct JevBassAnswers: Codable, Equatable, Sendable {
    public let activity: JevChoiceAnswer
    public let relationship: JevChoiceAnswer
    public let motion: JevChoiceAnswer
    public let fill: JevNoulAnswer

    public init(
        activity: JevChoiceAnswer,
        relationship: JevChoiceAnswer,
        motion: JevChoiceAnswer,
        fill: JevNoulAnswer
    ) {
        self.activity = activity
        self.relationship = relationship
        self.motion = motion
        self.fill = fill
    }
}

public struct JevUsage: Codable, Equatable, Sendable {
    public let inputTokens: Int
    public let outputTokens: Int

    public init(inputTokens: Int, outputTokens: Int) {
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
    }

    private enum CodingKeys: String, CodingKey {
        case inputTokens = "input_tokens"
        case outputTokens = "output_tokens"
    }
}

public struct JevSystemOneResponse: Codable, Equatable, Sendable {
    public let model: String
    public let answers: JevBassAnswers
    public let usage: JevUsage

    public init(model: String, answers: JevBassAnswers, usage: JevUsage) {
        self.model = model
        self.answers = answers
        self.usage = usage
    }
}

public enum JevDecisionTraceOutcome: String, Codable, Equatable, Sendable {
    case ready
    case lowConfidence = "low_confidence"
    case invalidResponse = "invalid_response"
    case httpError = "http_error"
    case timedOut = "timed_out"
    case cancelled
    case transportError = "transport_error"
}

/// A complete, secret-free record of one Jev evaluation. Authorization data is
/// owned by the transport and is intentionally absent from this type.
public struct JevDecisionTrace: Codable, Equatable, Sendable {
    public let request: JevSystemOneRequest
    public let response: JevSystemOneResponse?
    public let responseBody: String?
    public let requestedAt: Date
    public let completedAt: Date
    public let latencyMilliseconds: Double
    public let deadlineMilliseconds: UInt64
    public let outcome: JevDecisionTraceOutcome
    public let error: String?
    public let candidateDecision: BassDecision?

    public init(
        request: JevSystemOneRequest,
        response: JevSystemOneResponse?,
        responseBody: String?,
        requestedAt: Date,
        completedAt: Date,
        latencyMilliseconds: Double,
        deadlineMilliseconds: UInt64,
        outcome: JevDecisionTraceOutcome,
        error: String?,
        candidateDecision: BassDecision?
    ) {
        self.request = request
        self.response = response
        self.responseBody = responseBody
        self.requestedAt = requestedAt
        self.completedAt = completedAt
        self.latencyMilliseconds = latencyMilliseconds
        self.deadlineMilliseconds = deadlineMilliseconds
        self.outcome = outcome
        self.error = error
        self.candidateDecision = candidateDecision
    }
}

public struct JevTransportResponse: Sendable {
    public let statusCode: Int
    public let body: Data

    public init(statusCode: Int, body: Data) {
        self.statusCode = statusCode
        self.body = body
    }
}

public protocol JevTransport: Sendable {
    func send(
        requestBody: Data,
        apiKey: String,
        timeoutInterval: TimeInterval
    ) async throws -> JevTransportResponse
}

public final class URLSessionJevTransport: JevTransport, @unchecked Sendable {
    public static let productionEndpoint = URL(
        string: "https://api.typesafe.ai/v1/systemone"
    )!

    private let session: URLSession
    private let endpoint: URL

    public init(
        session: URLSession = .shared,
        endpoint: URL = URLSessionJevTransport.productionEndpoint
    ) {
        self.session = session
        self.endpoint = endpoint
    }

    public func send(
        requestBody: Data,
        apiKey: String,
        timeoutInterval: TimeInterval
    ) async throws -> JevTransportResponse {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = timeoutInterval
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = requestBody

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw JevClientError.invalidHTTPResponse
        }
        return JevTransportResponse(
            statusCode: httpResponse.statusCode,
            body: data
        )
    }
}

public enum JevClientError: Error, CustomStringConvertible, Equatable, Sendable {
    case invalidHTTPResponse
    case invalidAnswer(String)
    case timedOut(UInt64)

    public var description: String {
        switch self {
        case .invalidHTTPResponse:
            return "Jev returned a non-HTTP response."
        case let .invalidAnswer(message):
            return "Invalid Jev answer: \(message)"
        case let .timedOut(milliseconds):
            return "Jev did not answer within \(milliseconds) ms."
        }
    }
}

public struct JevDecisionEvaluation: Equatable, Sendable {
    public let decision: BassDecision?
    public let trace: JevDecisionTrace

    public init(decision: BassDecision?, trace: JevDecisionTrace) {
        self.decision = decision
        self.trace = trace
    }
}

public struct JevDecisionClient: Sendable {
    public let model: String
    public let deadlineMilliseconds: UInt64
    public let minimumConfidence: Double

    private let apiKey: String
    private let transport: any JevTransport

    public init(
        apiKey: String,
        model: String = "jev-latest",
        deadlineMilliseconds: UInt64 = 750,
        minimumConfidence: Double = 0.5,
        transport: any JevTransport = URLSessionJevTransport()
    ) {
        self.apiKey = apiKey
        self.model = model
        self.deadlineMilliseconds = min(max(deadlineMilliseconds, 1), 60_000)
        self.minimumConfidence = min(max(minimumConfidence, 0), 1)
        self.transport = transport
    }

    public func evaluate(_ input: BassDecisionInput) async -> JevDecisionEvaluation {
        let request = JevSystemOneRequest(input: input, model: model)
        let requestedAt = Date()
        let started = DispatchTime.now().uptimeNanoseconds
        var response: JevSystemOneResponse?
        var responseBody: String?

        do {
            let requestBody = try JSONEncoder().encode(request)
            let transportResponse = try await sendWithDeadline(requestBody)
            responseBody = String(data: transportResponse.body, encoding: .utf8)

            guard (200..<300).contains(transportResponse.statusCode) else {
                return evaluation(
                    decision: nil,
                    request: request,
                    response: nil,
                    responseBody: responseBody,
                    requestedAt: requestedAt,
                    startedNanoseconds: started,
                    outcome: .httpError,
                    error: "Jev returned HTTP \(transportResponse.statusCode)."
                )
            }

            do {
                response = try JSONDecoder().decode(
                    JevSystemOneResponse.self,
                    from: transportResponse.body
                )
                let candidate = try decision(from: response!)
                let choiceConfidence = [
                    response!.answers.activity.confidence,
                    response!.answers.relationship.confidence,
                    response!.answers.motion.confidence
                ].min() ?? 0
                let accepted = choiceConfidence >= minimumConfidence
                return evaluation(
                    decision: accepted ? candidate : nil,
                    request: request,
                    response: response,
                    responseBody: nil,
                    requestedAt: requestedAt,
                    startedNanoseconds: started,
                    outcome: accepted ? .ready : .lowConfidence,
                    error: accepted
                        ? nil
                        : "Choice confidence \(choiceConfidence) is below \(minimumConfidence).",
                    candidateDecision: candidate
                )
            } catch {
                return evaluation(
                    decision: nil,
                    request: request,
                    response: response,
                    responseBody: responseBody,
                    requestedAt: requestedAt,
                    startedNanoseconds: started,
                    outcome: .invalidResponse,
                    error: String(describing: error)
                )
            }
        } catch is CancellationError {
            return evaluation(
                decision: nil,
                request: request,
                response: response,
                responseBody: responseBody,
                requestedAt: requestedAt,
                startedNanoseconds: started,
                outcome: .cancelled,
                error: "Jev request was cancelled."
            )
        } catch let error as JevClientError {
            let outcome: JevDecisionTraceOutcome
            if case .timedOut = error {
                outcome = .timedOut
            } else {
                outcome = .transportError
            }
            return evaluation(
                decision: nil,
                request: request,
                response: response,
                responseBody: responseBody,
                requestedAt: requestedAt,
                startedNanoseconds: started,
                outcome: outcome,
                error: error.description
            )
        } catch {
            return evaluation(
                decision: nil,
                request: request,
                response: response,
                responseBody: responseBody,
                requestedAt: requestedAt,
                startedNanoseconds: started,
                outcome: .transportError,
                error: String(describing: error)
            )
        }
    }

    private func sendWithDeadline(_ requestBody: Data) async throws -> JevTransportResponse {
        let deadlineMilliseconds = deadlineMilliseconds
        let timeoutInterval = Double(deadlineMilliseconds) / 1_000
        let transport = transport
        let apiKey = apiKey

        return try await withThrowingTaskGroup(of: JevTransportResponse.self) { group in
            group.addTask {
                try await transport.send(
                    requestBody: requestBody,
                    apiKey: apiKey,
                    timeoutInterval: timeoutInterval
                )
            }
            group.addTask {
                try await Task.sleep(
                    nanoseconds: deadlineMilliseconds * 1_000_000
                )
                throw JevClientError.timedOut(deadlineMilliseconds)
            }

            guard let first = try await group.next() else {
                throw JevClientError.invalidHTTPResponse
            }
            group.cancelAll()
            return first
        }
    }

    private func decision(from response: JevSystemOneResponse) throws -> BassDecision {
        guard !response.model.isEmpty else {
            throw JevClientError.invalidAnswer("model is empty")
        }
        let activity = try choice(
            response.answers.activity,
            type: BassActivity.self,
            name: "activity"
        )
        let relationship = try choice(
            response.answers.relationship,
            type: BassRelationship.self,
            name: "relationship"
        )
        let motion = try choice(
            response.answers.motion,
            type: BassMotion.self,
            name: "motion"
        )
        guard response.answers.fill.type == "noul" else {
            throw JevClientError.invalidAnswer("fill type is not noul")
        }
        let fillProbability = response.answers.fill.noul
        guard fillProbability.isFinite, (0...1).contains(fillProbability) else {
            throw JevClientError.invalidAnswer("fill probability is outside 0...1")
        }
        let fillCertainty = abs(fillProbability - 0.5) * 2
        let confidence = [
            response.answers.activity.confidence,
            response.answers.relationship.confidence,
            response.answers.motion.confidence,
            fillCertainty
        ].min() ?? 0

        return BassDecision(
            activity: activity,
            relationship: relationship,
            motion: motion,
            fill: fillProbability >= 0.65,
            confidence: confidence
        )
    }

    private func choice<Value>(
        _ answer: JevChoiceAnswer,
        type: Value.Type,
        name: String
    ) throws -> Value where Value: RawRepresentable & CaseIterable, Value.RawValue == String {
        guard answer.type == "choice" else {
            throw JevClientError.invalidAnswer("\(name) type is not choice")
        }
        guard answer.confidence.isFinite, (0...1).contains(answer.confidence) else {
            throw JevClientError.invalidAnswer("\(name) confidence is outside 0...1")
        }
        let expected = Set(Value.allCases.map(\.rawValue))
        guard Set(answer.probabilities.keys) == expected else {
            throw JevClientError.invalidAnswer("\(name) probabilities have unexpected options")
        }
        guard answer.probabilities.values.allSatisfy({ $0.isFinite && (0...1).contains($0) }) else {
            throw JevClientError.invalidAnswer("\(name) probabilities are outside 0...1")
        }
        let probabilitySum = answer.probabilities.values.reduce(0, +)
        guard abs(probabilitySum - 1) <= 0.02 else {
            throw JevClientError.invalidAnswer("\(name) probabilities do not sum to 1")
        }
        guard answer.probabilities[answer.choice] != nil,
              let value = Value(rawValue: answer.choice) else {
            throw JevClientError.invalidAnswer("\(name) selected an unknown option")
        }
        return value
    }

    private func evaluation(
        decision: BassDecision?,
        request: JevSystemOneRequest,
        response: JevSystemOneResponse?,
        responseBody: String?,
        requestedAt: Date,
        startedNanoseconds: UInt64,
        outcome: JevDecisionTraceOutcome,
        error: String?,
        candidateDecision: BassDecision? = nil
    ) -> JevDecisionEvaluation {
        let completedAt = Date()
        let ended = DispatchTime.now().uptimeNanoseconds
        let elapsed = ended >= startedNanoseconds ? ended - startedNanoseconds : 0
        let trace = JevDecisionTrace(
            request: request,
            response: response,
            responseBody: responseBody,
            requestedAt: requestedAt,
            completedAt: completedAt,
            latencyMilliseconds: Double(elapsed) / 1_000_000,
            deadlineMilliseconds: deadlineMilliseconds,
            outcome: outcome,
            error: error,
            candidateDecision: candidateDecision
        )
        return JevDecisionEvaluation(decision: decision, trace: trace)
    }
}

/// Starts Jev work one bar early and only reads completed results at a bar
/// boundary. A missing, late, rejected, or failed result uses the local policy
/// immediately, so network timing cannot move a MIDI onset.
public final class JevDecisionProvider: BassDecisionProvider, @unchecked Sendable {
    public typealias TraceHandler = @Sendable (JevDecisionTrace) -> Void

    private let lock = NSLock()
    private let client: JevDecisionClient
    private let fallback: any BassDecisionProvider
    private let traceHandler: TraceHandler
    private var preparedDecisions: [Int: BassDecision] = [:]
    private var inFlightTargets: Set<Int> = []
    private var tasks: [Int: Task<Void, Never>] = [:]
    private var expiredThroughTarget = -1
    private var isCancelled = false

    public init(
        apiKey: String,
        model: String = "jev-latest",
        deadlineMilliseconds: UInt64 = 750,
        minimumConfidence: Double = 0.5,
        transport: any JevTransport = URLSessionJevTransport(),
        fallback: any BassDecisionProvider = RuleBasedBassDecisionProvider(),
        traceHandler: @escaping TraceHandler = { _ in }
    ) {
        client = JevDecisionClient(
            apiKey: apiKey,
            model: model,
            deadlineMilliseconds: deadlineMilliseconds,
            minimumConfidence: minimumConfidence,
            transport: transport
        )
        self.fallback = fallback
        self.traceHandler = traceHandler
    }

    deinit {
        cancelPendingDecisions()
    }

    public func prepare(_ input: BassDecisionInput) {
        guard input.chord != nil else {
            return
        }
        let target = input.targetBarIndex

        lock.lock()
        let mayStart = !isCancelled
            && target > expiredThroughTarget
            && preparedDecisions[target] == nil
            && !inFlightTargets.contains(target)
        if mayStart {
            inFlightTargets.insert(target)
        }
        lock.unlock()
        guard mayStart else {
            return
        }

        let task = Task { [
            weak self,
            client = self.client,
            traceHandler = self.traceHandler
        ] in
            let evaluation = await client.evaluate(input)
            guard let self else {
                traceHandler(evaluation.trace)
                return
            }
            self.complete(evaluation, target: target)
        }

        lock.lock()
        if inFlightTargets.contains(target) {
            tasks[target] = task
        }
        lock.unlock()
    }

    public func decision(for input: BassDecisionInput) -> BassDecision {
        resolution(for: input).decision
    }

    public func resolution(for input: BassDecisionInput) -> BassDecisionResolution {
        let target = input.targetBarIndex
        lock.lock()
        expiredThroughTarget = max(expiredThroughTarget, target)
        let prepared = preparedDecisions.removeValue(forKey: target)
        let staleTask = tasks.removeValue(forKey: target)
        inFlightTargets.remove(target)
        preparedDecisions = preparedDecisions.filter { $0.key > expiredThroughTarget }
        lock.unlock()

        staleTask?.cancel()
        if let prepared {
            return BassDecisionResolution(decision: prepared, source: .jev)
        }
        return BassDecisionResolution(
            decision: fallback.decision(for: input),
            source: .fallback
        )
    }

    public func cancelPendingDecisions() {
        lock.lock()
        guard !isCancelled else {
            lock.unlock()
            return
        }
        isCancelled = true
        let pendingTasks = Array(tasks.values)
        tasks.removeAll()
        inFlightTargets.removeAll()
        preparedDecisions.removeAll()
        lock.unlock()

        for task in pendingTasks {
            task.cancel()
        }
    }

    private func complete(_ evaluation: JevDecisionEvaluation, target: Int) {
        lock.lock()
        inFlightTargets.remove(target)
        tasks.removeValue(forKey: target)
        if !isCancelled,
           target > expiredThroughTarget,
           let decision = evaluation.decision {
            preparedDecisions[target] = decision
        }
        lock.unlock()

        traceHandler(evaluation.trace)
    }
}
