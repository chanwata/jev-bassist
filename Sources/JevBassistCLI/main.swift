import Darwin
import Foundation
import JevBassistCore
import JevBassistMIDI

enum Command {
    case devices
    case monitor(source: String?)
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
}

enum CLIError: Error, CustomStringConvertible {
    case invalidArguments(String)

    var description: String {
        switch self {
        case let .invalidArguments(message):
            return message
        }
    }
}

let usage = """
Jev Bassist MIDI monitor

USAGE
  jev-bassist devices
  jev-bassist monitor [--source NAME]
  jev-bassist help

COMMANDS
  devices   List CoreMIDI input sources.
  monitor   Print Note On and Note Off events. With no source, listen to all sources.
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

do {
    let command = try Command(arguments: Array(CommandLine.arguments.dropFirst()))

    switch command {
    case .help:
        print(usage)
    case .devices:
        printSources(CoreMIDIInput.availableSources())
    case let .monitor(source):
        let monitor = try CoreMIDIInput { event in
            print(format(event))
        }
        let connected = try monitor.connect(sourceMatching: source)
        print("Listening to \(connected.map(\.name).joined(separator: ", ")). Press Control-C to stop.")
        RunLoop.current.run()
    }
} catch {
    FileHandle.standardError.write(Data("Error: \(error)\n\n\(usage)\n".utf8))
    exit(EXIT_FAILURE)
}
