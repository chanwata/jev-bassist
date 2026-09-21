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
    public static let currentFormatVersion = 1

    public let formatVersion: Int
    public let input: MIDISessionFixture
    public let configuration: SessionEvaluationConfiguration
    public let policy: SessionEvaluationPolicy
    public let snapshots: [MusicalStateSnapshot]
    public let plans: [BassBarPlan]

    public init(
        formatVersion: Int = currentFormatVersion,
        input: MIDISessionFixture,
        configuration: SessionEvaluationConfiguration,
        policy: SessionEvaluationPolicy,
        snapshots: [MusicalStateSnapshot],
        plans: [BassBarPlan]
    ) throws {
        guard formatVersion == Self.currentFormatVersion else {
            throw SessionEvaluationError.unsupportedFormatVersion(formatVersion)
        }
        self.formatVersion = formatVersion
        self.input = input
        self.configuration = configuration
        self.policy = policy
        self.snapshots = snapshots
        self.plans = plans
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
        guard trace.formatVersion == SessionEvaluationTrace.currentFormatVersion else {
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
        guard trace.formatVersion == SessionEvaluationTrace.currentFormatVersion else {
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

        for event in fixture.events {
            let update = try engine.ingest(event)
            snapshots.append(contentsOf: update.snapshots)
            plans.append(contentsOf: update.plans)
        }
        let finalUpdate = try engine.finish(through: fixture.durationMicroseconds)
        snapshots.append(contentsOf: finalUpdate.snapshots)
        plans.append(contentsOf: finalUpdate.plans)

        return try SessionEvaluationTrace(
            input: fixture,
            configuration: SessionEvaluationConfiguration(configuration: configuration),
            policy: .rules,
            snapshots: snapshots,
            plans: plans
        )
    }
}
