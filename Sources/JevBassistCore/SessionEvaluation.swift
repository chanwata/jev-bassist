import Foundation

public enum SessionEvaluationPolicy: String, Codable, Equatable, Sendable {
    case rules
}

public struct SessionEvaluationConfiguration: Codable, Equatable, Sendable {
    public let musicalState: MusicalStateConfiguration
    public let introBars: Int
    public let maximumHeldChordBars: Int
    public let outputChannel: UInt8
    public let progression: [ChordCandidate]
    public let style: AccompanimentStyle
    public let mode: MusicalMode?

    public init(configuration: LocalBassistConfiguration) {
        musicalState = configuration.musicalState
        introBars = configuration.introBars
        maximumHeldChordBars = configuration.maximumHeldChordBars
        outputChannel = configuration.outputChannel
        progression = configuration.progression
        style = configuration.style
        mode = configuration.mode
    }

    public func localBassistConfiguration() throws -> LocalBassistConfiguration {
        try LocalBassistConfiguration(
            musicalState: musicalState,
            introBars: introBars,
            maximumHeldChordBars: maximumHeldChordBars,
            outputChannel: outputChannel,
            progression: progression,
            style: style,
            mode: mode
        )
    }
}

public struct SessionEvaluationTrace: Codable, Equatable, Sendable {
    public static let currentFormatVersion = 3
    public static let supportedFormatVersions = 1...currentFormatVersion

    public let formatVersion: Int
    public let input: MIDISessionFixture
    public let configuration: SessionEvaluationConfiguration
    public let policy: SessionEvaluationPolicy
    public let snapshots: [MusicalStateSnapshot]
    public let plans: [BassBarPlan]
    public let performedNotes: [PerformedNote]
    public let phraseObservations: [PhraseObservation]
    public let motifs: [Motif]
    public let performanceDiagnostics: [PerformanceTrackerDiagnostic]
    public let scheduledMIDIEvents: [RollingMIDIEvent]
    public let schedulerCancellations: [RollingMIDICancellation]

    public init(
        formatVersion: Int = currentFormatVersion,
        input: MIDISessionFixture,
        configuration: SessionEvaluationConfiguration,
        policy: SessionEvaluationPolicy,
        snapshots: [MusicalStateSnapshot],
        plans: [BassBarPlan],
        performedNotes: [PerformedNote] = [],
        phraseObservations: [PhraseObservation] = [],
        motifs: [Motif] = [],
        performanceDiagnostics: [PerformanceTrackerDiagnostic] = [],
        scheduledMIDIEvents: [RollingMIDIEvent] = [],
        schedulerCancellations: [RollingMIDICancellation] = []
    ) throws {
        guard Self.supportedFormatVersions.contains(formatVersion) else {
            throw SessionEvaluationError.unsupportedFormatVersion(formatVersion)
        }
        self.formatVersion = formatVersion
        self.input = input
        self.configuration = configuration
        self.policy = policy
        self.snapshots = snapshots
        self.plans = plans
        self.performedNotes = performedNotes
        self.phraseObservations = phraseObservations
        self.motifs = motifs
        self.performanceDiagnostics = performanceDiagnostics
        self.scheduledMIDIEvents = scheduledMIDIEvents
        self.schedulerCancellations = schedulerCancellations
    }

    private enum CodingKeys: String, CodingKey {
        case formatVersion
        case input
        case configuration
        case policy
        case snapshots
        case plans
        case performedNotes
        case phraseObservations
        case motifs
        case performanceDiagnostics
        case scheduledMIDIEvents
        case schedulerCancellations
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            formatVersion: container.decode(Int.self, forKey: .formatVersion),
            input: container.decode(MIDISessionFixture.self, forKey: .input),
            configuration: container.decode(
                SessionEvaluationConfiguration.self,
                forKey: .configuration
            ),
            policy: container.decode(SessionEvaluationPolicy.self, forKey: .policy),
            snapshots: container.decode([MusicalStateSnapshot].self, forKey: .snapshots),
            plans: container.decode([BassBarPlan].self, forKey: .plans),
            performedNotes: container.decodeIfPresent(
                [PerformedNote].self,
                forKey: .performedNotes
            ) ?? [],
            phraseObservations: container.decodeIfPresent(
                [PhraseObservation].self,
                forKey: .phraseObservations
            ) ?? [],
            motifs: container.decodeIfPresent([Motif].self, forKey: .motifs) ?? [],
            performanceDiagnostics: container.decodeIfPresent(
                [PerformanceTrackerDiagnostic].self,
                forKey: .performanceDiagnostics
            ) ?? [],
            scheduledMIDIEvents: container.decodeIfPresent(
                [RollingMIDIEvent].self,
                forKey: .scheduledMIDIEvents
            ) ?? [],
            schedulerCancellations: container.decodeIfPresent(
                [RollingMIDICancellation].self,
                forKey: .schedulerCancellations
            ) ?? []
        )
    }
}

public enum SessionEvaluationError: Error, CustomStringConvertible, Equatable {
    case unsupportedFormatVersion(Int)

    public var description: String {
        switch self {
        case let .unsupportedFormatVersion(version):
            return "Unsupported session evaluation format version \(version)."
        }
    }
}

public enum SessionEvaluationCodec {
    public static func encode(_ trace: SessionEvaluationTrace) throws -> Data {
        guard SessionEvaluationTrace.supportedFormatVersions.contains(trace.formatVersion) else {
            throw SessionEvaluationError.unsupportedFormatVersion(trace.formatVersion)
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .millisecondsSince1970
        return try encoder.encode(trace)
    }

    public static func decode(_ data: Data) throws -> SessionEvaluationTrace {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        let trace = try decoder.decode(SessionEvaluationTrace.self, from: data)
        guard SessionEvaluationTrace.supportedFormatVersions.contains(trace.formatVersion) else {
            throw SessionEvaluationError.unsupportedFormatVersion(trace.formatVersion)
        }
        try trace.input.validate()
        _ = try trace.configuration.localBassistConfiguration()
        return trace
    }

    public static func write(
        _ trace: SessionEvaluationTrace,
        to url: URL
    ) throws {
        try encode(trace).write(to: url, options: .withoutOverwriting)
    }
}

public struct LocalBassistSessionEvaluator: Sendable {
    public init() {}

    public func evaluate(
        fixture: MIDISessionFixture,
        configuration: LocalBassistConfiguration
    ) throws -> SessionEvaluationTrace {
        try fixture.validate()
        var engine = LocalBassistEngine(
            configuration: configuration,
            decisionProvider: RuleBasedBassDecisionProvider()
        )
        var snapshots: [MusicalStateSnapshot] = []
        var plans: [BassBarPlan] = []
        var performedNotes: [PerformedNote] = []
        var phraseObservations: [PhraseObservation] = []
        var motifs: [Motif] = []
        var performanceDiagnostics: [PerformanceTrackerDiagnostic] = []
        var scheduler = try RollingMIDIScheduler()
        var schedulerLineage: [UInt64: ConversationLineage] = [:]
        var pendingAcknowledgements: [(offset: UInt64, responseID: UInt64)] = []
        var scheduledMIDIEvents: [RollingMIDIEvent] = []
        var schedulerCancellations: [RollingMIDICancellation] = []

        func collect(_ update: LocalBassistUpdate) {
            snapshots.append(contentsOf: update.snapshots)
            plans.append(contentsOf: update.plans)
            performedNotes.append(contentsOf: update.performedNotes)
            phraseObservations.append(contentsOf: update.phraseObservations)
            motifs.append(contentsOf: update.motifs)
            performanceDiagnostics.append(contentsOf: update.performanceDiagnostics)
        }

        func schedule(_ newPlans: [BassBarPlan], at offset: UInt64) {
            if !newPlans.isEmpty {
                let cancellation = scheduler.yieldToHuman(at: offset)
                if !cancellation.canceledEventIDs.isEmpty {
                    schedulerCancellations.append(cancellation)
                }
                for revision in cancellation.canceledRevisions {
                    if let lineage = schedulerLineage.removeValue(forKey: revision) {
                        engine.discardUncommittedConversationResponse(
                            responseID: lineage.responseID
                        )
                    }
                }
            }
            for plan in newPlans where !plan.phrase.messages.isEmpty {
                let revision = scheduler.submit(plan.phrase.messages)
                if let lineage = plan.conversationLineage {
                    schedulerLineage[revision] = lineage
                }
            }
        }

        func acknowledgeElapsed(through offset: UInt64) {
            pendingAcknowledgements.sort { $0.offset < $1.offset }
            let elapsedCount = pendingAcknowledgements.prefix {
                $0.offset <= offset
            }.count
            guard elapsedCount > 0 else { return }
            let elapsed = pendingAcknowledgements.prefix(elapsedCount)
            pendingAcknowledgements.removeFirst(elapsedCount)
            for acknowledgement in elapsed {
                engine.acknowledgeElapsedConversationNote(
                    responseID: acknowledgement.responseID
                )
            }
        }

        func commit(through offset: UInt64) throws {
            acknowledgeElapsed(through: offset)
            let due = try scheduler.drain(through: offset)
            scheduledMIDIEvents.append(contentsOf: due)
            for event in due where event.message.kind == .noteOn {
                if let responseID = schedulerLineage[event.revision]?.responseID {
                    pendingAcknowledgements.append(
                        (event.message.offsetMicroseconds, responseID)
                    )
                }
            }
            acknowledgeElapsed(through: offset)
        }

        for event in fixture.events {
            if event.offsetMicroseconds > 0 {
                let clockOffset = event.offsetMicroseconds - 1
                let clockUpdate = try engine.advance(through: clockOffset)
                collect(clockUpdate)
                schedule(clockUpdate.plans, at: clockOffset)
                try commit(through: clockOffset)
            }
            let update = try engine.ingest(event)
            if event.kind == .noteOn, event.velocity > 0 {
                engine.yieldToHuman()
            }
            collect(update)
            schedule(update.plans, at: event.offsetMicroseconds)
            try commit(through: event.offsetMicroseconds)
        }
        let finalUpdate = try engine.finish(through: fixture.durationMicroseconds)
        collect(finalUpdate)
        schedule(finalUpdate.plans, at: fixture.durationMicroseconds)
        try commit(through: fixture.durationMicroseconds)

        return try SessionEvaluationTrace(
            input: fixture,
            configuration: SessionEvaluationConfiguration(configuration: configuration),
            policy: .rules,
            snapshots: snapshots,
            plans: plans,
            performedNotes: performedNotes,
            phraseObservations: phraseObservations,
            motifs: motifs,
            performanceDiagnostics: performanceDiagnostics,
            scheduledMIDIEvents: scheduledMIDIEvents,
            schedulerCancellations: schedulerCancellations
        )
    }
}
