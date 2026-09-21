import Darwin
import Dispatch
import Foundation
import JevBassistCore
import JevBassistJev
import JevBassistMIDI

private struct SoundcheckOptions {
    let destination: String
    let channel: UInt8
}

private struct EvaluationOptions {
    let inputPath: String
    let outputPath: String
    let tempoBPM: Double
    let beatsPerBar: Int
    let introBars: Int
    let outputChannel: UInt8
    let progression: [ChordCandidate]
    let style: AccompanimentStyle
    let mode: MusicalMode?
}

private enum BrainMode: String, Sendable {
    case rules
    case jev
}

private struct JamOptions: Sendable {
    let source: String
    let destination: String
    let tempoBPM: Double
    let beatsPerBar: Int
    let inputChannel: UInt8
    let outputChannel: UInt8
    let introBars: Int
    let brain: BrainMode
    let webUI: Bool
    let progression: [ChordCandidate]
    let style: AccompanimentStyle
    let mode: MusicalMode?
    let humanVolume: UInt8
    let companionVolume: UInt8
}

private enum Command {
    case devices
    case outputs
    case monitor(source: String?)
    case capture(outputPath: String, source: String?)
    case replay(inputPath: String, tempoBPM: Double, beatsPerBar: Int)
    case evaluate(EvaluationOptions)
    case soundcheck(SoundcheckOptions)
    case jam(JamOptions)
    case help

    init(arguments: [String]) throws {
        guard let first = arguments.first else {
            self = .monitor(source: nil)
            return
        }

        switch first {
        case "devices":
            try Self.requireNoOptions(arguments, command: "devices")
            self = .devices
        case "outputs":
            try Self.requireNoOptions(arguments, command: "outputs")
            self = .outputs
        case "monitor":
            self = .monitor(source: try Self.sourceOption(in: Array(arguments.dropFirst())))
        case "capture":
            self = try Self.captureCommand(arguments: Array(arguments.dropFirst()))
        case "replay":
            self = try Self.replayCommand(arguments: Array(arguments.dropFirst()))
        case "evaluate":
            self = .evaluate(try Self.evaluationOptions(in: Array(arguments.dropFirst())))
        case "soundcheck":
            self = .soundcheck(try Self.soundcheckOptions(in: Array(arguments.dropFirst())))
        case "jam":
            self = .jam(try Self.jamOptions(in: Array(arguments.dropFirst())))
        case "help", "--help", "-h":
            self = .help
        default:
            throw CLIError.invalidArguments("Unknown command '\(first)'.")
        }
    }

    private static func requireNoOptions(_ arguments: [String], command: String) throws {
        guard arguments.count == 1 else {
            throw CLIError.invalidArguments("'\(command)' does not accept options.")
        }
    }

    private static func sourceOption(in arguments: [String]) throws -> String? {
        guard !arguments.isEmpty else {
            return nil
        }
        let options = try optionValues(
            in: arguments,
            allowed: ["--source"],
            usage: "monitor [--source NAME]"
        )
        return options["--source"]
    }

    private static func captureCommand(arguments: [String]) throws -> Command {
        guard let outputPath = arguments.first, !outputPath.hasPrefix("-") else {
            throw CLIError.invalidArguments("Use 'capture FILE [--source NAME]'.")
        }
        let options = try optionValues(
            in: Array(arguments.dropFirst()),
            allowed: ["--source"],
            usage: "capture FILE [--source NAME]"
        )
        return .capture(outputPath: outputPath, source: options["--source"])
    }

    private static func replayCommand(arguments: [String]) throws -> Command {
        guard let inputPath = arguments.first, !inputPath.hasPrefix("-") else {
            throw CLIError.invalidArguments(
                "Use 'replay FILE [--bpm BPM] [--beats-per-bar N]'."
            )
        }
        let options = try optionValues(
            in: Array(arguments.dropFirst()),
            allowed: ["--bpm", "--beats-per-bar"],
            usage: "replay FILE [--bpm BPM] [--beats-per-bar N]"
        )
        let tempoBPM = try doubleOption(options, name: "--bpm", default: 120)
        let beatsPerBar = try intOption(options, name: "--beats-per-bar", default: 4)
        _ = try MusicalStateConfiguration(tempoBPM: tempoBPM, beatsPerBar: beatsPerBar)
        return .replay(
            inputPath: inputPath,
            tempoBPM: tempoBPM,
            beatsPerBar: beatsPerBar
        )
    }

    private static func soundcheckOptions(in arguments: [String]) throws -> SoundcheckOptions {
        let options = try optionValues(
            in: arguments,
            allowed: ["--destination", "--channel"],
            usage: "soundcheck --destination NAME [--channel N]"
        )
        guard let destination = options["--destination"] else {
            throw CLIError.invalidArguments("'soundcheck' requires --destination NAME.")
        }
        return SoundcheckOptions(
            destination: destination,
            channel: try channelOption(options, name: "--channel", default: 3)
        )
    }

    private static func evaluationOptions(in arguments: [String]) throws -> EvaluationOptions {
        guard arguments.count >= 2,
              !arguments[0].hasPrefix("-"),
              !arguments[1].hasPrefix("-") else {
            throw CLIError.invalidArguments(
                "Use 'evaluate INPUT OUTPUT [--bpm BPM] [--beats-per-bar N] [--intro-bars N] [--output-channel N] [--style STYLE] [--mode MODE] [--progression CHORDS]'."
            )
        }
        let optionArguments = Array(arguments.dropFirst(2))
        let options = try optionValues(
            in: optionArguments,
            allowed: [
                "--bpm", "--beats-per-bar", "--intro-bars", "--output-channel",
                "--style", "--mode", "--progression"
            ],
            usage: "evaluate INPUT OUTPUT [options]"
        )
        let tempoBPM = try doubleOption(options, name: "--bpm", default: 120)
        let beatsPerBar = try intOption(options, name: "--beats-per-bar", default: 4)
        let introBars = try intOption(options, name: "--intro-bars", default: 4)
        let outputChannel = try channelOption(options, name: "--output-channel", default: 3)
        let styleName = options["--style"] ?? AccompanimentStyle.bass.rawValue
        guard let style = AccompanimentStyle(rawValue: styleName) else {
            throw CLIError.invalidArguments(
                "--style must be 'bass', 'ambient', 'memory', or 'fugue'."
            )
        }
        let mode: MusicalMode?
        if let modeName = options["--mode"] {
            guard let parsed = MusicalMode(rawValue: modeName.lowercased()) else {
                throw CLIError.invalidArguments(
                    "--mode must be ionian, dorian, phrygian, lydian, mixolydian, aeolian, or locrian."
                )
            }
            mode = parsed
        } else {
            mode = nil
        }
        let progression: [ChordCandidate]
        if let progressionText = options["--progression"] {
            progression = try ChordProgressionParser.parse(progressionText)
        } else {
            progression = []
        }
        let musicalState = try MusicalStateConfiguration(
            tempoBPM: tempoBPM,
            beatsPerBar: beatsPerBar
        )
        _ = try LocalBassistConfiguration(
            musicalState: musicalState,
            introBars: introBars,
            outputChannel: outputChannel,
            progression: progression,
            style: style,
            mode: mode
        )
        return EvaluationOptions(
            inputPath: arguments[0],
            outputPath: arguments[1],
            tempoBPM: tempoBPM,
            beatsPerBar: beatsPerBar,
            introBars: introBars,
            outputChannel: outputChannel,
            progression: progression,
            style: style,
            mode: mode
        )
    }

    private static func jamOptions(in arguments: [String]) throws -> JamOptions {
        let webUICount = arguments.filter { $0 == "--ui" }.count
        guard webUICount <= 1 else {
            throw CLIError.invalidArguments("Use '--ui' only once.")
        }
        let valueArguments = arguments.filter { $0 != "--ui" }
        let options = try optionValues(
            in: valueArguments,
            allowed: [
                "--source", "--destination", "--bpm", "--beats-per-bar",
                "--input-channel", "--output-channel", "--intro-bars", "--brain",
                "--progression", "--style", "--mode", "--human-volume", "--companion-volume"
            ],
            usage: "jam --source NAME --destination NAME [options]"
        )
        guard let source = options["--source"] else {
            throw CLIError.invalidArguments("'jam' requires --source NAME.")
        }
        guard let destination = options["--destination"] else {
            throw CLIError.invalidArguments("'jam' requires --destination NAME.")
        }

        let tempoBPM = try doubleOption(options, name: "--bpm", default: 120)
        let beatsPerBar = try intOption(options, name: "--beats-per-bar", default: 4)
        let introBars = try intOption(options, name: "--intro-bars", default: 4)
        let inputChannel = try channelOption(options, name: "--input-channel", default: 1)
        let outputChannel = try channelOption(options, name: "--output-channel", default: 3)
        let humanVolume = try midiValueOption(
            options,
            name: "--human-volume",
            default: 100
        )
        let companionVolume = try midiValueOption(
            options,
            name: "--companion-volume",
            default: 72
        )
        let brainName = options["--brain"] ?? BrainMode.rules.rawValue
        guard let brain = BrainMode(rawValue: brainName) else {
            throw CLIError.invalidArguments("--brain must be 'rules' or 'jev'.")
        }
        let styleName = options["--style"] ?? AccompanimentStyle.bass.rawValue
        guard let style = AccompanimentStyle(rawValue: styleName) else {
            throw CLIError.invalidArguments(
                "--style must be 'bass', 'ambient', 'memory', or 'fugue'."
            )
        }
        let mode: MusicalMode?
        if let modeName = options["--mode"] {
            guard let parsed = MusicalMode(rawValue: modeName.lowercased()) else {
                throw CLIError.invalidArguments(
                    "--mode must be ionian, dorian, phrygian, lydian, mixolydian, aeolian, or locrian."
                )
            }
            mode = parsed
        } else {
            mode = nil
        }
        let progression: [ChordCandidate]
        if let progressionText = options["--progression"] {
            progression = try ChordProgressionParser.parse(progressionText)
        } else {
            progression = []
        }
        let musicalState = try MusicalStateConfiguration(
            tempoBPM: tempoBPM,
            beatsPerBar: beatsPerBar
        )
        _ = try LocalBassistConfiguration(
            musicalState: musicalState,
            introBars: introBars,
            outputChannel: outputChannel,
            progression: progression,
            style: style,
            mode: mode
        )
        return JamOptions(
            source: source,
            destination: destination,
            tempoBPM: tempoBPM,
            beatsPerBar: beatsPerBar,
            inputChannel: inputChannel,
            outputChannel: outputChannel,
            introBars: introBars,
            brain: brain,
            webUI: webUICount == 1,
            progression: progression,
            style: style,
            mode: mode,
            humanVolume: humanVolume,
            companionVolume: companionVolume
        )
    }

    private static func optionValues(
        in arguments: [String],
        allowed: Set<String>,
        usage: String
    ) throws -> [String: String] {
        guard arguments.count.isMultiple(of: 2) else {
            throw CLIError.invalidArguments("Use '\(usage)'.")
        }
        var values: [String: String] = [:]
        var index = 0
        while index < arguments.count {
            let option = arguments[index]
            let value = arguments[index + 1]
            guard allowed.contains(option), values[option] == nil, !value.isEmpty else {
                throw CLIError.invalidArguments("Use '\(usage)'.")
            }
            values[option] = value
            index += 2
        }
        return values
    }

    private static func doubleOption(
        _ options: [String: String],
        name: String,
        default defaultValue: Double
    ) throws -> Double {
        guard let value = options[name] else {
            return defaultValue
        }
        guard let parsed = Double(value) else {
            throw CLIError.invalidArguments("\(name) must be a number.")
        }
        return parsed
    }

    private static func intOption(
        _ options: [String: String],
        name: String,
        default defaultValue: Int
    ) throws -> Int {
        guard let value = options[name] else {
            return defaultValue
        }
        guard let parsed = Int(value) else {
            throw CLIError.invalidArguments("\(name) must be an integer.")
        }
        return parsed
    }

    private static func channelOption(
        _ options: [String: String],
        name: String,
        default defaultValue: UInt8
    ) throws -> UInt8 {
        guard let value = options[name] else {
            return defaultValue
        }
        guard let parsed = UInt8(value), (1...16).contains(parsed) else {
            throw CLIError.invalidArguments("\(name) must be between 1 and 16.")
        }
        return parsed
    }

    private static func midiValueOption(
        _ options: [String: String],
        name: String,
        default defaultValue: UInt8
    ) throws -> UInt8 {
        guard let value = options[name] else {
            return defaultValue
        }
        guard let parsed = UInt8(value), parsed <= 127 else {
            throw CLIError.invalidArguments("\(name) must be between 0 and 127.")
        }
        return parsed
    }
}

private enum CLIError: Error, CustomStringConvertible {
    case invalidArguments(String)
    case outputAlreadyExists(String)
    case liveSession(String)

    var description: String {
        switch self {
        case let .invalidArguments(message):
            return message
        case let .outputAlreadyExists(path):
            return "Refusing to overwrite existing fixture '\(path)'."
        case let .liveSession(message):
            return "Live session stopped: \(message)"
        }
    }
}

private let usage = """
Jev Bassist MIDI session tool

USAGE
  jev-bassist devices
  jev-bassist outputs
  jev-bassist monitor [--source NAME]
  jev-bassist capture FILE [--source NAME]
  jev-bassist replay FILE [--bpm BPM] [--beats-per-bar N]
  jev-bassist evaluate INPUT OUTPUT [--bpm BPM] [--beats-per-bar N] [--intro-bars N] [--output-channel N] [--style bass|ambient|memory|fugue] [--mode MODE] [--progression CHORDS]
  jev-bassist soundcheck --destination NAME [--channel N]
  jev-bassist jam --source NAME --destination NAME [--bpm BPM] [--beats-per-bar N] [--input-channel N] [--output-channel N] [--human-volume 0...127] [--companion-volume 0...127] [--intro-bars N] [--brain rules|jev] [--style bass|ambient|memory|fugue] [--mode MODE] [--progression CHORDS] [--ui]
  jev-bassist help

COMMANDS
  devices      List CoreMIDI input sources.
  outputs      List CoreMIDI output destinations.
  monitor      Print Note On and Note Off events. With no source, listen to all sources.
  capture      Record a versioned JSON fixture. Press Return to stop and save.
  replay       Replay into the analyzer and print state. No MIDI output is sent.
  evaluate     Run a fixture through the local ensemble and save a deterministic trace. No MIDI output is sent.
  soundcheck   Send three short bass notes to one destination, then silence it.
  jam          Listen locally and schedule bass or ambient accompaniment after the intro.
"""

private func printSources(_ sources: [MIDISource]) {
    guard !sources.isEmpty else {
        print("No MIDI input sources found.")
        return
    }
    for (index, source) in sources.enumerated() {
        let manufacturer = source.manufacturer.map { " — \($0)" } ?? ""
        print("\(index + 1). \(source.name)\(manufacturer)")
    }
}

private func printDestinations(_ destinations: [MIDIDestination]) {
    guard !destinations.isEmpty else {
        print("No MIDI output destinations found.")
        return
    }
    for (index, destination) in destinations.enumerated() {
        let manufacturer = destination.manufacturer.map { " — \($0)" } ?? ""
        print("\(index + 1). \(destination.name)\(manufacturer)")
    }
}

private func format(_ event: MIDIEvent) -> String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    formatter.timeZone = .current
    let kind = event.kind.rawValue.padding(toLength: 7, withPad: " ", startingAt: 0)
    let velocity = String(event.velocity).padding(toLength: 3, withPad: " ", startingAt: 0)
    return "\(formatter.string(from: event.receivedAt)) host=\(event.hostTime) \(kind) note=\(event.note)(\(MIDINoteName.name(for: event.note))) velocity=\(velocity) channel=\(event.channel)"
}

private func format(_ snapshot: MusicalStateSnapshot) -> String {
    let state = snapshot.state
    let location: String
    switch snapshot.boundary {
    case .beat:
        location = "beat=\(snapshot.index + 1) bar=\(snapshot.barIndex + 1).\(snapshot.beatInBar ?? 0)"
    case .bar:
        location = "bar=\(snapshot.index + 1)"
    }

    let velocity = state.averageVelocity.map { String(format: "%.1f", $0) } ?? "-"
    let register = state.averageNote.map { String(format: "%.1f", $0) } ?? "-"
    let held = state.heldNotes.isEmpty
        ? "-"
        : state.heldNotes.map { "\(MIDINoteName.name(for: $0.note))@\($0.channel)" }.joined(separator: ",")
    let pulse = state.pulse.map {
        String(format: "%.1f(%.2f)", $0.bpm, $0.confidence)
    } ?? "-"
    let chords = state.chordCandidates.isEmpty
        ? "-"
        : state.chordCandidates.map {
            "\($0.displayName):\(String(format: "%.2f", $0.confidence))"
        }.joined(separator: ",")

    return "\(snapshot.boundary.rawValue) \(location) notes=\(state.noteOnCount) density=\(String(format: "%.2f", state.noteDensityPerBeat)) velocity=\(velocity) register=\(register) held=\(held) pulse=\(pulse) chords=\(chords)"
}

private func format(_ plan: BassBarPlan, style: AccompanimentStyle) -> String {
    let chord = plan.chord.map(\.displayName) ?? "none"
    let held = plan.usedHeldChord ? " held" : ""
    let notes = plan.phrase.messages
        .filter { $0.kind == .noteOn }
        .map { MIDINoteName.name(for: $0.note) }
        .joined(separator: ",")
    let expression = style == .memory || style == .fugue
        ? " memory=\(String(format: "%.2f", plan.expression.memory)) tension=\(String(format: "%.2f", plan.expression.tension)) resonance=\(String(format: "%.2f", plan.expression.resonance))"
        : ""
    let development = plan.developmentStage.map { " development=\($0.rawValue)" } ?? ""
    let center = plan.tonalCenterPitchClass.map { " center=\(pitchClassName($0))" } ?? ""
    return "\(style.rawValue) bar=\(plan.targetBarIndex + 1) brain=\(plan.decisionSource.rawValue) chord=\(chord)\(held)\(development)\(center) activity=\(plan.decision.activity.rawValue) relationship=\(plan.decision.relationship.rawValue) motion=\(plan.decision.motion.rawValue) fill=\(plan.decision.fill) notes=\(notes.isEmpty ? "rest" : notes)\(expression)"
}

private func pitchClassName(_ pitchClass: UInt8) -> String {
    return ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"][Int(pitchClass % 12)]
}

private let jevTraceLock = NSLock()

private func log(_ trace: JevDecisionTrace) {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = [.sortedKeys]
    guard let data = try? encoder.encode(trace) else {
        return
    }
    jevTraceLock.lock()
    defer { jevTraceLock.unlock() }
    FileHandle.standardError.write(Data("jev-trace ".utf8))
    FileHandle.standardError.write(data)
    FileHandle.standardError.write(Data("\n".utf8))
}

private func log(_ trace: JevConversationTrace) {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    guard let data = try? encoder.encode(trace) else { return }
    jevTraceLock.lock()
    defer { jevTraceLock.unlock() }
    FileHandle.standardError.write(Data("jev-conversation-trace ".utf8))
    FileHandle.standardError.write(data)
    FileHandle.standardError.write(Data("\n".utf8))
}

private func fileURL(for path: String) -> URL {
    URL(
        fileURLWithPath: path,
        relativeTo: URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    ).standardizedFileURL
}

private func runMonitor(source: String?) throws {
    let monitor = try CoreMIDIInput { event in
        print(format(event))
    }
    let connected = try monitor.connect(sourceMatching: source)
    print("Listening to \(connected.map(\.name).joined(separator: ", ")). Press Control-C to stop.")
    withExtendedLifetime(monitor) {
        RunLoop.current.run()
    }
}

private func runCapture(outputPath: String, source: String?) throws {
    let outputURL = fileURL(for: outputPath)
    guard !FileManager.default.fileExists(atPath: outputURL.path) else {
        throw CLIError.outputAlreadyExists(outputURL.path)
    }

    let capture = MIDISessionCapture()
    let monitor = try CoreMIDIInput { event in
        capture.append(event)
        print(format(event))
    }
    let connected = try monitor.connect(sourceMatching: source)
    let sourceNames = connected.map(\.name)
    print("Recording \(sourceNames.joined(separator: ", ")). Press Return to stop and save.")
    _ = readLine()
    monitor.flushPendingEvents()

    let fixture = try capture.fixture(sourceNames: sourceNames)
    try MIDISessionFixtureCodec.write(fixture, to: outputURL)
    print("Saved \(fixture.events.count) events to \(outputURL.path).")
}

private func runReplay(inputPath: String, tempoBPM: Double, beatsPerBar: Int) throws {
    let inputURL = fileURL(for: inputPath)
    let fixture = try MIDISessionFixtureCodec.decode(Data(contentsOf: inputURL))
    let configuration = try MusicalStateConfiguration(
        tempoBPM: tempoBPM,
        beatsPerBar: beatsPerBar
    )
    var tracker = MusicalStateTracker(configuration: configuration)

    print("Analyzing \(fixture.events.count) recorded events from \(fixture.sourceNames.joined(separator: ", ")) at \(tempoBPM) BPM, \(beatsPerBar)/4. No MIDI output is sent.")
    for event in fixture.events {
        for snapshot in try tracker.ingest(event) {
            print(format(snapshot))
        }
        print(format(event.midiEvent(relativeTo: fixture.startedAt)))
    }
    for snapshot in try tracker.finish(through: fixture.durationMicroseconds) {
        print(format(snapshot))
    }
}

private func runEvaluation(_ options: EvaluationOptions) throws {
    let inputURL = fileURL(for: options.inputPath)
    let outputURL = fileURL(for: options.outputPath)
    let fixture = try MIDISessionFixtureCodec.decode(Data(contentsOf: inputURL))
    let configuration = try LocalBassistConfiguration(
        musicalState: MusicalStateConfiguration(
            tempoBPM: options.tempoBPM,
            beatsPerBar: options.beatsPerBar
        ),
        introBars: options.introBars,
        outputChannel: options.outputChannel,
        progression: options.progression,
        style: options.style,
        mode: options.mode
    )
    let trace = try LocalBassistSessionEvaluator().evaluate(
        fixture: fixture,
        configuration: configuration
    )
    try SessionEvaluationCodec.write(trace, to: outputURL)
    let eventCount = trace.plans.reduce(0) { $0 + $1.phrase.messages.count }
    print(
        "Saved deterministic \(trace.policy.rawValue) evaluation with "
            + "\(trace.plans.count) plans, \(trace.motifs.count) remembered motifs, "
            + "and \(eventCount) scheduled MIDI events "
            + "to \(outputURL.path). No MIDI output was sent."
    )
}

private func runSoundcheck(_ options: SoundcheckOptions) throws {
    let output = try CoreMIDIOutput()
    let destination = try output.connect(destinationMatching: options.destination)
    let anchor = MIDIHostTime.addingMicroseconds(100_000, to: MIDIHostTime.now)
    let notes: [UInt8] = [36, 43, 48]
    var messages: [ScheduledMIDIMessage] = []
    for (index, note) in notes.enumerated() {
        let onset = UInt64(index) * 450_000
        messages.append(
            ScheduledMIDIMessage(
                offsetMicroseconds: onset,
                kind: .noteOn,
                channel: options.channel,
                note: note,
                velocity: 76
            )
        )
        messages.append(
            ScheduledMIDIMessage(
                offsetMicroseconds: onset + 280_000,
                kind: .noteOff,
                channel: options.channel,
                note: note,
                velocity: 0
            )
        )
    }

    print("Sending C2, G2, C3 to \(destination.name) on MIDI channel \(options.channel).")
    try output.schedule(messages, anchorHostTime: anchor)
    RunLoop.current.run(until: Date().addingTimeInterval(1.6))
    try output.stop(channel: options.channel)
    print("Soundcheck complete; pending output was flushed and the channel was silenced.")
}

/// Mutable session state is confined to `queue`; the unchecked conformance is
/// used only so CoreMIDI's Sendable callback can enqueue copied events.
private final class JamSession: @unchecked Sendable, JamWebControlling {
    private struct PendingConversationAcknowledgement {
        let onsetMicroseconds: UInt64
        let responseID: UInt64
    }

    private static let inputGraceMicroseconds: UInt64 = 8_000
    private static let outputSafetyOffsetMicroseconds: UInt64 = 12_000
    private static let schedulingHorizonMicroseconds: UInt64 = 50_000

    private let queue = DispatchQueue(label: "dev.jev-bassist.live-session")
    private let sessionID = UUID().uuidString
    private let options: JamOptions
    private let output: CoreMIDIOutput
    private let stopSignal: @Sendable () -> Void
    private let stateHandler: @Sendable (JamWebState) -> Void
    private var engine: LocalBassistEngine
    private var scheduler: RollingMIDIScheduler
    private var schedulerLineage: [UInt64: ConversationLineage] = [:]
    private var pendingConversationAcknowledgements: [PendingConversationAcknowledgement] = []
    private var anchorHostTime: UInt64?
    private var startedAt: Date?
    private var timer: DispatchSourceTimer?
    private var stopped = false
    private var failureDescription: String?
    private var lastPublishedBeat: Int?
    private var lastChord: String?
    private var lastDecisionSource: String?
    private var lastDevelopmentStage: String?
    private var lastTonalCenter: String?
    private var lastNote: String?
    private var lastExpression: EnsembleExpression = .quiet
    private var humanVolume: UInt8
    private var companionVolume: UInt8
    private var visualEvents: [JamVisualEvent] = []
    private var nextVisualEventID: UInt64 = 1

    init(
        options: JamOptions,
        output: CoreMIDIOutput,
        stateHandler: @escaping @Sendable (JamWebState) -> Void = { _ in },
        stopSignal: @escaping @Sendable () -> Void
    ) throws {
        self.options = options
        self.output = output
        self.stateHandler = stateHandler
        self.stopSignal = stopSignal
        humanVolume = options.inputChannel == options.outputChannel
            ? options.companionVolume
            : options.humanVolume
        companionVolume = options.companionVolume
        scheduler = try RollingMIDIScheduler(
            horizonMicroseconds: Self.schedulingHorizonMicroseconds
        )
        let musicalState = try MusicalStateConfiguration(
            tempoBPM: options.tempoBPM,
            beatsPerBar: options.beatsPerBar
        )
        let decisionProvider: any BassDecisionProvider
        let conversationDecisionProvider: any ConversationDecisionProvider
        switch options.brain {
        case .rules:
            decisionProvider = RuleBasedBassDecisionProvider()
            conversationDecisionProvider = LocalConversationDecisionProvider()
        case .jev:
            guard let apiKey = ProcessInfo.processInfo.environment["TYPESAFE_API_KEY"],
                  !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw CLIError.invalidArguments(
                    "--brain jev requires TYPESAFE_API_KEY in the environment."
                )
            }
            let barMilliseconds = 60_000 * Double(options.beatsPerBar) / options.tempoBPM
            let deadlineMilliseconds = UInt64(
                min(750, max(100, barMilliseconds - 50)).rounded(.down)
            )
            decisionProvider = JevDecisionProvider(
                apiKey: apiKey,
                deadlineMilliseconds: deadlineMilliseconds,
                traceHandler: log
            )
            conversationDecisionProvider = JevConversationDecisionProvider(
                apiKey: apiKey,
                deadlineMilliseconds: min(350, deadlineMilliseconds),
                traceHandler: log
            )
        }
        engine = LocalBassistEngine(
            configuration: try LocalBassistConfiguration(
                musicalState: musicalState,
                introBars: options.introBars,
                outputChannel: options.outputChannel,
                progression: options.progression,
                style: options.style,
                mode: options.mode
            ),
            decisionProvider: decisionProvider,
            conversationDecisionProvider: conversationDecisionProvider
        )
        try output.sendControlChange(
            controller: 7,
            value: humanVolume,
            channel: options.inputChannel
        )
        if options.outputChannel != options.inputChannel {
            try output.sendControlChange(
                controller: 7,
                value: companionVolume,
                channel: options.outputChannel
            )
        }
    }

    func receive(_ event: MIDIEvent) {
        queue.async { [weak self] in
            self?.handle(event)
        }
    }

    func startClockFromWeb() {
        queue.async { [weak self] in
            self?.beginClock(hostTime: MIDIHostTime.now, trigger: "Web UI")
        }
    }

    func setHumanVolumeFromWeb(_ value: UInt8) {
        queue.async { [weak self] in
            guard let self else { return }
            setVolume(value, channel: options.inputChannel)
        }
    }

    func setCompanionVolumeFromWeb(_ value: UInt8) {
        queue.async { [weak self] in
            guard let self else { return }
            setVolume(value, channel: options.outputChannel)
        }
    }

    func publishInitialState() {
        queue.async { [weak self] in
            self?.publishState(elapsedMicroseconds: nil)
        }
    }

    func stop() -> String? {
        queue.sync {
            guard !stopped else {
                return failureDescription
            }
            stopped = true
            timer?.cancel()
            timer = nil
            engine.cancelPendingDecisions()
            _ = scheduler.cancelAllPending()
            do {
                try output.stop(channel: options.outputChannel)
            } catch {
                failureDescription = failureDescription ?? String(describing: error)
            }
            publishState(elapsedMicroseconds: nil)
            return failureDescription
        }
    }

    private func handle(_ event: MIDIEvent) {
        guard !stopped, event.channel == options.inputChannel else {
            return
        }
        let eventHostTime = event.hostTime == 0 ? MIDIHostTime.now : event.hostTime

        if event.kind == .noteOn {
            lastNote = MIDINoteName.name(for: event.note)
        }

        if anchorHostTime == nil {
            guard event.kind == .noteOn else {
                return
            }
            guard !options.webUI else {
                publishState(elapsedMicroseconds: nil)
                return
            }
            beginClock(
                hostTime: eventHostTime,
                trigger: MIDINoteName.name(for: event.note)
            )
        }

        guard let anchorHostTime else {
            return
        }
        let offset = MIDIHostTime.microseconds(from: anchorHostTime, to: eventHostTime)
        let sessionEvent = SessionMIDIEvent(
            offsetMicroseconds: offset,
            hostTime: event.hostTime,
            channel: event.channel,
            kind: event.kind,
            note: event.note,
            velocity: event.velocity
        )
        do {
            acknowledgeElapsedConversationNotes(through: offset)
            let update = try engine.ingest(sessionEvent)
            let isHumanAttack = event.kind == .noteOn && event.velocity > 0
            if isHumanAttack {
                engine.yieldToHuman()
            }
            try process(
                update,
                anchorHostTime: anchorHostTime,
                currentOffsetMicroseconds: offset
            )
            if options.webUI {
                appendVisualEvent(
                    performer: "human",
                    kind: event.kind.rawValue,
                    note: event.note,
                    velocity: event.velocity,
                    sessionOffsetMicroseconds: offset
                )
                publishState(elapsedMicroseconds: offset)
            }
        } catch let error as MusicalStateError {
            switch error {
            case .nonMonotonicEvent, .eventBeforeCompletedBoundary:
                print("warning: dropped late MIDI event: \(error)")
            default:
                fail(error)
            }
        } catch {
            fail(error)
        }
    }

    private func beginClock(hostTime: UInt64, trigger: String) {
        guard !stopped, anchorHostTime == nil else {
            return
        }
        anchorHostTime = hostTime
        startedAt = Date()
        lastPublishedBeat = nil
        startTimer()
        publishState(elapsedMicroseconds: 0)
        print("Clock started by \(trigger); \(options.style.rawValue) accompaniment enters after \(options.introBars) complete bars.")
    }

    private func startTimer() {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(
            deadline: .now() + .milliseconds(4),
            repeating: .milliseconds(4),
            leeway: .milliseconds(1)
        )
        timer.setEventHandler { [weak self] in
            self?.tick()
        }
        self.timer = timer
        timer.resume()
    }

    private func tick() {
        guard !stopped, let anchorHostTime else {
            return
        }
        let elapsed = MIDIHostTime.microseconds(from: anchorHostTime, to: MIDIHostTime.now)
        let safeElapsed = elapsed > Self.inputGraceMicroseconds
            ? elapsed - Self.inputGraceMicroseconds
            : 0
        do {
            acknowledgeElapsedConversationNotes(through: safeElapsed)
            try process(
                engine.advance(through: safeElapsed),
                anchorHostTime: anchorHostTime,
                currentOffsetMicroseconds: safeElapsed
            )
            let absoluteBeat = Int(
                Double(safeElapsed) * options.tempoBPM / 60_000_000
            )
            if lastPublishedBeat != absoluteBeat {
                lastPublishedBeat = absoluteBeat
                publishState(elapsedMicroseconds: safeElapsed)
            }
        } catch {
            fail(error)
        }
    }

    private func process(
        _ update: LocalBassistUpdate,
        anchorHostTime: UInt64,
        currentOffsetMicroseconds: UInt64
    ) throws {
        for snapshot in update.snapshots where snapshot.boundary == .bar {
            print(format(snapshot))
            lastChord = snapshot.state.chordCandidates.first?.displayName
        }
        if !update.plans.isEmpty {
            let cancellation = scheduler.yieldToHuman(at: currentOffsetMicroseconds)
            for revision in cancellation.canceledRevisions {
                if let lineage = schedulerLineage[revision] {
                    engine.discardUncommittedConversationResponse(
                        responseID: lineage.responseID
                    )
                    if options.webUI {
                        appendVisualEvent(
                            performer: "companion",
                            kind: "cancel",
                            note: 0,
                            velocity: 0,
                            sessionOffsetMicroseconds: currentOffsetMicroseconds,
                            lineage: lineage
                        )
                    }
                }
                schedulerLineage.removeValue(forKey: revision)
            }
        }
        for plan in update.plans {
            print(format(plan, style: options.style))
            lastChord = plan.chord?.displayName
            lastDecisionSource = plan.decisionSource.rawValue
            lastDevelopmentStage = plan.developmentStage?.rawValue
            lastTonalCenter = plan.tonalCenterPitchClass.map(pitchClassName)
            lastExpression = plan.expression
            if !plan.phrase.messages.isEmpty {
                let revision = scheduler.submit(plan.phrase.messages)
                if let lineage = plan.conversationLineage {
                    schedulerLineage[revision] = lineage
                    if schedulerLineage.count > 64,
                       let oldest = schedulerLineage.keys.min() {
                        schedulerLineage.removeValue(forKey: oldest)
                    }
                }
            }
        }
        try sendDueEvents(
            currentOffsetMicroseconds: currentOffsetMicroseconds,
            anchorHostTime: anchorHostTime
        )
    }

    private func sendDueEvents(
        currentOffsetMicroseconds: UInt64,
        anchorHostTime: UInt64
    ) throws {
        let due = try scheduler.drain(through: currentOffsetMicroseconds)
        guard !due.isEmpty else { return }
        let outputAnchor = MIDIHostTime.addingMicroseconds(
            Self.outputSafetyOffsetMicroseconds,
            to: anchorHostTime
        )
        try output.schedule(
            due.map(\.message),
            anchorHostTime: outputAnchor
        )
        for event in due where event.message.kind == .noteOn {
            guard let responseID = schedulerLineage[event.revision]?.responseID else {
                continue
            }
            let onset = event.message.offsetMicroseconds
                .addingReportingOverflow(Self.outputSafetyOffsetMicroseconds)
            pendingConversationAcknowledgements.append(
                PendingConversationAcknowledgement(
                    onsetMicroseconds: onset.overflow ? UInt64.max : onset.partialValue,
                    responseID: responseID
                )
            )
        }
        pendingConversationAcknowledgements.sort {
            $0.onsetMicroseconds < $1.onsetMicroseconds
        }
        acknowledgeElapsedConversationNotes(through: currentOffsetMicroseconds)
        if options.webUI {
            for event in due {
                let message = event.message
                appendVisualEvent(
                    performer: "companion",
                    kind: message.kind.rawValue,
                    note: message.note,
                    velocity: message.velocity,
                    sessionOffsetMicroseconds: message.offsetMicroseconds
                        + Self.outputSafetyOffsetMicroseconds,
                    noteID: event.noteID,
                    lineage: schedulerLineage[event.revision]
                )
            }
            publishState(elapsedMicroseconds: currentOffsetMicroseconds)
        }
    }

    private func acknowledgeElapsedConversationNotes(through offset: UInt64) {
        let elapsedCount = pendingConversationAcknowledgements.prefix {
            $0.onsetMicroseconds <= offset
        }.count
        guard elapsedCount > 0 else { return }
        let elapsed = pendingConversationAcknowledgements.prefix(elapsedCount)
        pendingConversationAcknowledgements.removeFirst(elapsedCount)
        for acknowledgement in elapsed {
            engine.acknowledgeElapsedConversationNote(
                responseID: acknowledgement.responseID
            )
        }
    }

    private func publishState(elapsedMicroseconds: UInt64?) {
        let absoluteBeat = elapsedMicroseconds.map {
            Int(Double($0) * options.tempoBPM / 60_000_000)
        }
        let barIndex = absoluteBeat.map { $0 / options.beatsPerBar }
        let phase: String
        if stopped {
            phase = "stopped"
        } else if let barIndex {
            phase = barIndex < options.introBars ? "intro" : "live"
        } else {
            phase = "ready"
        }
        stateHandler(
            JamWebState(
                sessionID: sessionID,
                running: !stopped && anchorHostTime != nil,
                tempoBPM: options.tempoBPM,
                beatsPerBar: options.beatsPerBar,
                introBars: options.introBars,
                brain: options.brain.rawValue,
                style: options.style.rawValue,
                mode: options.mode?.rawValue,
                source: options.source,
                destination: options.destination,
                startedAtUnixMilliseconds: startedAt.map { $0.timeIntervalSince1970 * 1_000 },
                sessionElapsedMicroseconds: elapsedMicroseconds
                    ?? currentElapsedMicroseconds(),
                bar: barIndex.map { $0 + 1 },
                beat: absoluteBeat.map { $0 % options.beatsPerBar + 1 },
                phase: phase,
                chord: barIndex.flatMap { progressionChord(for: $0)?.displayName } ?? lastChord,
                nextChord: barIndex.flatMap { progressionChord(for: $0 + 1)?.displayName },
                decisionSource: lastDecisionSource,
                developmentStage: lastDevelopmentStage,
                tonalCenter: lastTonalCenter,
                lastNote: lastNote,
                humanChannel: options.inputChannel,
                companionChannel: options.outputChannel,
                humanVolume: humanVolume,
                companionVolume: companionVolume,
                expressionMemory: lastExpression.memory,
                expressionTension: lastExpression.tension,
                expressionActivity: lastExpression.activity,
                expressionResonance: lastExpression.resonance,
                visualEvents: visualEvents
            )
        )
    }

    private func setVolume(_ value: UInt8, channel: UInt8) {
        guard !stopped else {
            return
        }
        do {
            try output.sendControlChange(controller: 7, value: value, channel: channel)
            if options.inputChannel == options.outputChannel {
                humanVolume = value
                companionVolume = value
            } else if channel == options.inputChannel {
                humanVolume = value
            } else {
                companionVolume = value
            }
            publishState(elapsedMicroseconds: currentElapsedMicroseconds())
        } catch {
            fail(error)
        }
    }

    private func currentElapsedMicroseconds() -> UInt64? {
        guard let anchorHostTime else {
            return nil
        }
        return MIDIHostTime.microseconds(from: anchorHostTime, to: MIDIHostTime.now)
    }

    private func appendVisualEvent(
        performer: String,
        kind: String,
        note: UInt8,
        velocity: UInt8,
        sessionOffsetMicroseconds: UInt64,
        noteID: UInt64? = nil,
        lineage: ConversationLineage? = nil
    ) {
        guard let startedAt else {
            return
        }
        visualEvents.append(
            JamVisualEvent(
                sessionID: sessionID,
                id: nextVisualEventID,
                noteID: noteID,
                performer: performer,
                kind: kind,
                note: note,
                velocity: velocity,
                sessionOffsetMicroseconds: sessionOffsetMicroseconds,
                atUnixMilliseconds: startedAt.timeIntervalSince1970 * 1_000
                    + Double(sessionOffsetMicroseconds) / 1_000,
                originMotifID: lineage?.originMotifID,
                sourceMotifID: lineage?.sourceMotifID,
                developmentSourceMotifID: lineage?.developmentSourceMotifID,
                responseID: lineage?.responseID,
                parentResponseID: lineage?.parentResponseID,
                generation: lineage?.generation,
                relationship: lineage?.relationship.rawValue,
                intent: lineage?.intent.rawValue,
                interaction: lineage?.interaction.kind.rawValue,
                interactionConfidence: lineage?.interaction.confidence,
                originGesture: lineage?.originGesture,
                sourceGesture: lineage?.sourceGesture,
                responseGesture: lineage?.responseGesture
            )
        )
        nextVisualEventID += 1
        if visualEvents.count > 64 {
            visualEvents.removeFirst(visualEvents.count - 64)
        }
    }

    private func progressionChord(for barIndex: Int) -> ChordCandidate? {
        guard !options.progression.isEmpty, barIndex >= options.introBars else {
            return nil
        }
        let index = (barIndex - options.introBars) % options.progression.count
        return options.progression[index]
    }

    private func fail(_ error: Error) {
        guard !stopped else {
            return
        }
        stopped = true
        failureDescription = String(describing: error)
        timer?.cancel()
        timer = nil
        engine.cancelPendingDecisions()
        try? output.stop(channel: options.outputChannel)
        publishState(elapsedMicroseconds: nil)
        stopSignal()
    }
}

private func runJam(_ options: JamOptions) throws {
    let output = try CoreMIDIOutput()
    let destination = try output.connect(destinationMatching: options.destination)
    let stopSemaphore = DispatchSemaphore(value: 0)
    let webServer: JamWebServer?
    if options.webUI {
        webServer = try JamWebServer(stopSignal: { stopSemaphore.signal() })
    } else {
        webServer = nil
    }
    let session = try JamSession(
        options: options,
        output: output,
        stateHandler: { state in webServer?.publish(state) },
        stopSignal: { stopSemaphore.signal() }
    )
    webServer?.attach(controller: session)
    webServer?.start()
    session.publishInitialState()
    let monitor = try CoreMIDIInput { event in
        session.receive(event)
    }
    let connectedSources = try monitor.connect(sourceMatching: options.source)

    print("Listening to \(connectedSources.map(\.name).joined(separator: ", ")) on channel \(options.inputChannel).")
    print("Output: \(destination.name), channel \(options.outputChannel), \(options.tempoBPM) BPM, \(options.beatsPerBar)/4.")
    if options.inputChannel == options.outputChannel {
        print("Mix: shared=\(options.companionVolume) on channel \(options.inputChannel).")
        print("warning: input and output use the same MIDI channel, so their volume controls are linked.")
    } else {
        print("Mix: you=\(options.humanVolume) on channel \(options.inputChannel), companion=\(options.companionVolume) on channel \(options.outputChannel).")
    }
    let mode = options.mode.map { " · mode \($0.rawValue)" } ?? ""
    print("Style: \(options.style.rawValue)\(mode).")
    print("Brain: \(options.brain.rawValue)\(options.brain == .jev ? " (one-bar prefetch with rules fallback)" : "").")
    if !options.progression.isEmpty {
        print("Harmony: \(options.progression.map(\.displayName).joined(separator: " → ")) (loops after the intro).")
    } else {
        print("Harmony: live detection (experimental, one-bar response).")
    }
    if options.webUI {
        print("Shared clock: http://127.0.0.1:8765")
        print("Click Start in the browser. Press Return in this terminal to stop safely.")
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + .milliseconds(250)) {
            let opener = Process()
            opener.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            opener.arguments = ["http://127.0.0.1:8765"]
            try? opener.run()
        }
    } else {
        print("Play one note to start the bar clock. Press Return to stop safely.")
    }
    DispatchQueue.global(qos: .userInitiated).async {
        _ = readLine()
        stopSemaphore.signal()
    }
    stopSemaphore.wait()
    monitor.flushPendingEvents()
    if let failure = session.stop() {
        webServer?.stop()
        throw CLIError.liveSession(failure)
    }
    webServer?.stop()
    print("Stopped; pending MIDI was flushed and output channel \(options.outputChannel) was silenced.")
}

do {
    let command = try Command(arguments: Array(CommandLine.arguments.dropFirst()))

    switch command {
    case .help:
        print(usage)
    case .devices:
        printSources(CoreMIDIInput.availableSources())
    case .outputs:
        printDestinations(CoreMIDIOutput.availableDestinations())
    case let .monitor(source):
        try runMonitor(source: source)
    case let .capture(outputPath, source):
        try runCapture(outputPath: outputPath, source: source)
    case let .replay(inputPath, tempoBPM, beatsPerBar):
        try runReplay(
            inputPath: inputPath,
            tempoBPM: tempoBPM,
            beatsPerBar: beatsPerBar
        )
    case let .evaluate(options):
        try runEvaluation(options)
    case let .soundcheck(options):
        try runSoundcheck(options)
    case let .jam(options):
        try runJam(options)
    }
} catch {
    FileHandle.standardError.write(Data("Error: \(error)\n\n\(usage)\n".utf8))
    exit(EXIT_FAILURE)
}
