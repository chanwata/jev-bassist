import Darwin
import Dispatch
import Foundation
import JevBassistCore
import JevBassistMIDI

private struct SoundcheckOptions {
    let destination: String
    let channel: UInt8
}

private struct JamOptions: Sendable {
    let source: String
    let destination: String
    let tempoBPM: Double
    let beatsPerBar: Int
    let inputChannel: UInt8
    let outputChannel: UInt8
    let introBars: Int
}

private enum Command {
    case devices
    case outputs
    case monitor(source: String?)
    case capture(outputPath: String, source: String?)
    case replay(inputPath: String, tempoBPM: Double, beatsPerBar: Int)
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

    private static func jamOptions(in arguments: [String]) throws -> JamOptions {
        let options = try optionValues(
            in: arguments,
            allowed: [
                "--source", "--destination", "--bpm", "--beats-per-bar",
                "--input-channel", "--output-channel", "--intro-bars"
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
        let outputChannel = try channelOption(options, name: "--output-channel", default: 3)
        let musicalState = try MusicalStateConfiguration(
            tempoBPM: tempoBPM,
            beatsPerBar: beatsPerBar
        )
        _ = try LocalBassistConfiguration(
            musicalState: musicalState,
            introBars: introBars,
            outputChannel: outputChannel
        )
        return JamOptions(
            source: source,
            destination: destination,
            tempoBPM: tempoBPM,
            beatsPerBar: beatsPerBar,
            inputChannel: try channelOption(options, name: "--input-channel", default: 1),
            outputChannel: outputChannel,
            introBars: introBars
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
  jev-bassist soundcheck --destination NAME [--channel N]
  jev-bassist jam --source NAME --destination NAME [--bpm BPM] [--beats-per-bar N] [--input-channel N] [--output-channel N] [--intro-bars N]
  jev-bassist help

COMMANDS
  devices      List CoreMIDI input sources.
  outputs      List CoreMIDI output destinations.
  monitor      Print Note On and Note Off events. With no source, listen to all sources.
  capture      Record a versioned JSON fixture. Press Return to stop and save.
  replay       Replay into the analyzer and print state. No MIDI output is sent.
  soundcheck   Send three short bass notes to one destination, then silence it.
  jam          Listen locally and schedule rule-based bass after the intro. Press Return to stop.
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

private func format(_ plan: BassBarPlan) -> String {
    let chord = plan.chord.map(\.displayName) ?? "none"
    let held = plan.usedHeldChord ? " held" : ""
    let notes = plan.phrase.messages
        .filter { $0.kind == .noteOn }
        .map { MIDINoteName.name(for: $0.note) }
        .joined(separator: ",")
    return "bass bar=\(plan.targetBarIndex + 1) chord=\(chord)\(held) activity=\(plan.decision.activity.rawValue) relationship=\(plan.decision.relationship.rawValue) motion=\(plan.decision.motion.rawValue) fill=\(plan.decision.fill) notes=\(notes.isEmpty ? "rest" : notes)"
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
private final class JamSession: @unchecked Sendable {
    private static let inputGraceMicroseconds: UInt64 = 8_000
    private static let outputSafetyOffsetMicroseconds: UInt64 = 12_000

    private let queue = DispatchQueue(label: "dev.jev-bassist.live-session")
    private let options: JamOptions
    private let output: CoreMIDIOutput
    private let stopSignal: @Sendable () -> Void
    private var engine: LocalBassistEngine
    private var anchorHostTime: UInt64?
    private var timer: DispatchSourceTimer?
    private var stopped = false
    private var failureDescription: String?

    init(
        options: JamOptions,
        output: CoreMIDIOutput,
        stopSignal: @escaping @Sendable () -> Void
    ) throws {
        self.options = options
        self.output = output
        self.stopSignal = stopSignal
        let musicalState = try MusicalStateConfiguration(
            tempoBPM: options.tempoBPM,
            beatsPerBar: options.beatsPerBar
        )
        engine = LocalBassistEngine(
            configuration: try LocalBassistConfiguration(
                musicalState: musicalState,
                introBars: options.introBars,
                outputChannel: options.outputChannel
            )
        )
    }

    func receive(_ event: MIDIEvent) {
        queue.async { [weak self] in
            self?.handle(event)
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
            do {
                try output.stop(channel: options.outputChannel)
            } catch {
                failureDescription = failureDescription ?? String(describing: error)
            }
            return failureDescription
        }
    }

    private func handle(_ event: MIDIEvent) {
        guard !stopped, event.channel == options.inputChannel else {
            return
        }
        let eventHostTime = event.hostTime == 0 ? MIDIHostTime.now : event.hostTime

        if anchorHostTime == nil {
            guard event.kind == .noteOn else {
                return
            }
            anchorHostTime = eventHostTime
            startTimer()
            print("Clock started on \(MIDINoteName.name(for: event.note)); bass enters after \(options.introBars) complete bars.")
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
            try process(engine.ingest(sessionEvent), anchorHostTime: anchorHostTime)
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
            try process(
                engine.advance(through: safeElapsed),
                anchorHostTime: anchorHostTime
            )
        } catch {
            fail(error)
        }
    }

    private func process(
        _ update: LocalBassistUpdate,
        anchorHostTime: UInt64
    ) throws {
        for snapshot in update.snapshots where snapshot.boundary == .bar {
            print(format(snapshot))
        }
        let outputAnchor = MIDIHostTime.addingMicroseconds(
            Self.outputSafetyOffsetMicroseconds,
            to: anchorHostTime
        )
        for plan in update.plans {
            print(format(plan))
            try output.schedule(
                plan.phrase.messages,
                anchorHostTime: outputAnchor
            )
        }
    }

    private func fail(_ error: Error) {
        guard !stopped else {
            return
        }
        stopped = true
        failureDescription = String(describing: error)
        timer?.cancel()
        timer = nil
        try? output.stop(channel: options.outputChannel)
        stopSignal()
    }
}

private func runJam(_ options: JamOptions) throws {
    let output = try CoreMIDIOutput()
    let destination = try output.connect(destinationMatching: options.destination)
    let stopSemaphore = DispatchSemaphore(value: 0)
    let session = try JamSession(
        options: options,
        output: output,
        stopSignal: { stopSemaphore.signal() }
    )
    let monitor = try CoreMIDIInput { event in
        session.receive(event)
    }
    let connectedSources = try monitor.connect(sourceMatching: options.source)

    print("Listening to \(connectedSources.map(\.name).joined(separator: ", ")) on channel \(options.inputChannel).")
    print("Bass output: \(destination.name), channel \(options.outputChannel), \(options.tempoBPM) BPM, \(options.beatsPerBar)/4.")
    print("Play one note to start the bar clock. Press Return to stop safely.")
    DispatchQueue.global(qos: .userInitiated).async {
        _ = readLine()
        stopSemaphore.signal()
    }
    stopSemaphore.wait()
    monitor.flushPendingEvents()
    if let failure = session.stop() {
        throw CLIError.liveSession(failure)
    }
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
    case let .soundcheck(options):
        try runSoundcheck(options)
    case let .jam(options):
        try runJam(options)
    }
} catch {
    FileHandle.standardError.write(Data("Error: \(error)\n\n\(usage)\n".utf8))
    exit(EXIT_FAILURE)
}
