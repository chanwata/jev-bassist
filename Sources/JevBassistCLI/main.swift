import Darwin
import Foundation
import JevBassistCore
import JevBassistMIDI

enum Command {
    case devices
    case monitor(source: String?)
    case capture(outputPath: String, source: String?)
    case replay(inputPath: String, tempoBPM: Double, beatsPerBar: Int)
    case help

    init(arguments: [String]) throws {
        guard let first = arguments.first else {
            self = .monitor(source: nil)
            return
        }

        switch first {
        case "devices":
            guard arguments.count == 1 else {
                throw CLIError.invalidArguments("'devices' does not accept options.")
            }
            self = .devices
        case "monitor":
            self = .monitor(source: try Self.sourceOption(in: Array(arguments.dropFirst())))
        case "capture":
            self = try Self.captureCommand(arguments: Array(arguments.dropFirst()))
        case "replay":
            self = try Self.replayCommand(arguments: Array(arguments.dropFirst()))
        case "help", "--help", "-h":
            self = .help
        default:
            throw CLIError.invalidArguments("Unknown command '\(first)'.")
        }
    }

    private static func sourceOption(in arguments: [String]) throws -> String? {
        guard !arguments.isEmpty else {
            return nil
        }
        guard arguments.count == 2, arguments[0] == "--source", !arguments[1].isEmpty else {
            throw CLIError.invalidArguments("Use 'monitor [--source NAME]'.")
        }
        return arguments[1]
    }

    private static func captureCommand(arguments: [String]) throws -> Command {
        guard let outputPath = arguments.first, !outputPath.hasPrefix("-") else {
            throw CLIError.invalidArguments("Use 'capture FILE [--source NAME]'.")
        }
        let trailingArguments = Array(arguments.dropFirst())
        let source: String?
        if trailingArguments.isEmpty {
            source = nil
        } else {
            guard trailingArguments.count == 2,
                  trailingArguments[0] == "--source",
                  !trailingArguments[1].isEmpty else {
                throw CLIError.invalidArguments("Use 'capture FILE [--source NAME]'.")
            }
            source = trailingArguments[1]
        }
        return .capture(outputPath: outputPath, source: source)
    }

    private static func replayCommand(arguments: [String]) throws -> Command {
        guard let inputPath = arguments.first, !inputPath.hasPrefix("-") else {
            throw CLIError.invalidArguments(
                "Use 'replay FILE [--bpm BPM] [--beats-per-bar N]'."
            )
        }

        var tempoBPM = 120.0
        var beatsPerBar = 4
        var seenOptions = Set<String>()
        let options = Array(arguments.dropFirst())
        var index = 0

        while index < options.count {
            let option = options[index]
            guard !seenOptions.contains(option), index + 1 < options.count else {
                throw CLIError.invalidArguments(
                    "Use 'replay FILE [--bpm BPM] [--beats-per-bar N]'."
                )
            }
            seenOptions.insert(option)
            let value = options[index + 1]

            switch option {
            case "--bpm":
                guard let parsed = Double(value) else {
                    throw CLIError.invalidArguments("BPM must be a number.")
                }
                tempoBPM = parsed
            case "--beats-per-bar":
                guard let parsed = Int(value) else {
                    throw CLIError.invalidArguments("Beats per bar must be an integer.")
                }
                beatsPerBar = parsed
            default:
                throw CLIError.invalidArguments("Unknown replay option '\(option)'.")
            }
            index += 2
        }

        _ = try MusicalStateConfiguration(
            tempoBPM: tempoBPM,
            beatsPerBar: beatsPerBar
        )
        return .replay(
            inputPath: inputPath,
            tempoBPM: tempoBPM,
            beatsPerBar: beatsPerBar
        )
    }
}

enum CLIError: Error, CustomStringConvertible {
    case invalidArguments(String)
    case outputAlreadyExists(String)

    var description: String {
        switch self {
        case let .invalidArguments(message):
            return message
        case let .outputAlreadyExists(path):
            return "Refusing to overwrite existing fixture '\(path)'."
        }
    }
}

let usage = """
Jev Bassist MIDI session tool

USAGE
  jev-bassist devices
  jev-bassist monitor [--source NAME]
  jev-bassist capture FILE [--source NAME]
  jev-bassist replay FILE [--bpm BPM] [--beats-per-bar N]
  jev-bassist help

COMMANDS
  devices   List CoreMIDI input sources.
  monitor   Print Note On and Note Off events. With no source, listen to all sources.
  capture   Record a versioned JSON fixture. Press Return to stop and save.
  replay    Replay into the analyzer and print state. No MIDI output is sent.
"""

func printSources(_ sources: [MIDISource]) {
    guard !sources.isEmpty else {
        print("No MIDI input sources found.")
        return
    }

    for (index, source) in sources.enumerated() {
        let manufacturer = source.manufacturer.map { " — \($0)" } ?? ""
        print("\(index + 1). \(source.name)\(manufacturer)")
    }
}

func format(_ event: MIDIEvent) -> String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    formatter.timeZone = .current
    let kind = event.kind.rawValue.padding(toLength: 7, withPad: " ", startingAt: 0)
    let velocity = String(event.velocity).padding(toLength: 3, withPad: " ", startingAt: 0)
    return "\(formatter.string(from: event.receivedAt)) host=\(event.hostTime) \(kind) note=\(event.note)(\(MIDINoteName.name(for: event.note))) velocity=\(velocity) channel=\(event.channel)"
}

func format(_ snapshot: MusicalStateSnapshot) -> String {
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

func fileURL(for path: String) -> URL {
    URL(fileURLWithPath: path, relativeTo: URL(fileURLWithPath: FileManager.default.currentDirectoryPath))
        .standardizedFileURL
}

func runMonitor(source: String?) throws {
    let monitor = try CoreMIDIInput { event in
        print(format(event))
    }
    let connected = try monitor.connect(sourceMatching: source)
    print("Listening to \(connected.map(\.name).joined(separator: ", ")). Press Control-C to stop.")
    withExtendedLifetime(monitor) {
        RunLoop.current.run()
    }
}

func runCapture(outputPath: String, source: String?) throws {
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

func runReplay(inputPath: String, tempoBPM: Double, beatsPerBar: Int) throws {
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

do {
    let command = try Command(arguments: Array(CommandLine.arguments.dropFirst()))

    switch command {
    case .help:
        print(usage)
    case .devices:
        printSources(CoreMIDIInput.availableSources())
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
    }
} catch {
    FileHandle.standardError.write(Data("Error: \(error)\n\n\(usage)\n".utf8))
    exit(EXIT_FAILURE)
}
