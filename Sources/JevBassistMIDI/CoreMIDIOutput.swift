@preconcurrency import CoreMIDI
import Darwin
import Foundation
import JevBassistCore

public struct MIDIDestination: Equatable, Sendable {
    public let endpoint: MIDIEndpointRef
    public let name: String
    public let manufacturer: String?

    public init(endpoint: MIDIEndpointRef, name: String, manufacturer: String?) {
        self.endpoint = endpoint
        self.name = name
        self.manufacturer = manufacturer
    }
}

public enum CoreMIDIOutputError: Error, CustomStringConvertible {
    case clientCreation(OSStatus)
    case portCreation(OSStatus)
    case noDestinations
    case noMatchingDestination(String)
    case ambiguousDestination(String, matches: [String])
    case notConnected
    case invalidControlChange(channel: UInt8, controller: UInt8, value: UInt8)
    case packetConstruction
    case send(OSStatus)
    case flush(OSStatus)

    public var description: String {
        switch self {
        case let .clientCreation(status):
            return "CoreMIDI client creation failed (OSStatus \(status))."
        case let .portCreation(status):
            return "CoreMIDI output port creation failed (OSStatus \(status))."
        case .noDestinations:
            return "No MIDI output destinations are available."
        case let .noMatchingDestination(query):
            return "No MIDI output destination matched '\(query)'. Run 'jev-bassist outputs' to list destinations."
        case let .ambiguousDestination(query, matches):
            return "MIDI output destination '\(query)' is ambiguous: \(matches.joined(separator: ", ")). Use a more specific name."
        case .notConnected:
            return "No MIDI output destination is connected."
        case let .invalidControlChange(channel, controller, value):
            return "Invalid MIDI control change: channel \(channel), controller \(controller), value \(value)."
        case .packetConstruction:
            return "Could not construct a CoreMIDI packet."
        case let .send(status):
            return "CoreMIDI send failed (OSStatus \(status))."
        case let .flush(status):
            return "CoreMIDI output flush failed (OSStatus \(status))."
        }
    }
}

public enum MIDIHostTime {
    public static var now: UInt64 {
        mach_absolute_time()
    }

    public static func addingMicroseconds(
        _ microseconds: UInt64,
        to hostTime: UInt64
    ) -> UInt64 {
        let timebase = currentTimebase()
        let ticks = Double(microseconds) * 1_000
            * Double(timebase.denom) / Double(timebase.numer)
        guard ticks < Double(UInt64.max - hostTime) else {
            return UInt64.max
        }
        return hostTime + UInt64(ticks.rounded())
    }

    public static func microseconds(from start: UInt64, to end: UInt64) -> UInt64 {
        guard end > start else {
            return 0
        }
        let timebase = currentTimebase()
        let nanoseconds = Double(end - start)
            * Double(timebase.numer) / Double(timebase.denom)
        let microseconds = nanoseconds / 1_000
        guard microseconds < Double(UInt64.max) else {
            return UInt64.max
        }
        return UInt64(microseconds.rounded())
    }

    private static func currentTimebase() -> mach_timebase_info_data_t {
        var value = mach_timebase_info_data_t()
        mach_timebase_info(&value)
        return value
    }
}

enum MIDIControlChangeEncoder {
    static func bytes(
        controller: UInt8,
        value: UInt8,
        channel: UInt8
    ) throws -> [UInt8] {
        guard (1...16).contains(channel), controller <= 127, value <= 127 else {
            throw CoreMIDIOutputError.invalidControlChange(
                channel: channel,
                controller: controller,
                value: value
            )
        }
        return [UInt8(0xB0 | ((channel - 1) & 0x0F)), controller, value]
    }
}

/// CoreMIDI client, port, and destination access are serialized by `lock` so
/// a live session may schedule from its private queue and stop from the control
/// thread without racing lifecycle changes.
public final class CoreMIDIOutput: @unchecked Sendable {
    private let lock = NSLock()
    private var client = MIDIClientRef()
    private var outputPort = MIDIPortRef()
    private var destination: MIDIDestination?

    public init() throws {
        var newClient = MIDIClientRef()
        let clientStatus = MIDIClientCreateWithBlock(
            "Jev Bassist Output" as CFString,
            &newClient
        ) { _ in }
        guard clientStatus == noErr else {
            throw CoreMIDIOutputError.clientCreation(clientStatus)
        }
        client = newClient

        var newPort = MIDIPortRef()
        let portStatus = MIDIOutputPortCreate(
            client,
            "Jev Bassist Output" as CFString,
            &newPort
        )
        guard portStatus == noErr else {
            MIDIClientDispose(client)
            client = MIDIClientRef()
            throw CoreMIDIOutputError.portCreation(portStatus)
        }
        outputPort = newPort
    }

    deinit {
        try? stop()
        lock.lock()
        if outputPort != 0 {
            MIDIPortDispose(outputPort)
        }
        if client != 0 {
            MIDIClientDispose(client)
        }
        lock.unlock()
    }

    public static func availableDestinations() -> [MIDIDestination] {
        (0..<MIDIGetNumberOfDestinations()).compactMap { index in
            let endpoint = MIDIGetDestination(index)
            guard endpoint != 0 else {
                return nil
            }
            return MIDIDestination(
                endpoint: endpoint,
                name: stringProperty(endpoint, key: kMIDIPropertyDisplayName)
                    ?? "Unnamed destination \(index + 1)",
                manufacturer: stringProperty(endpoint, key: kMIDIPropertyManufacturer)
            )
        }
    }

    @discardableResult
    public func connect(destinationMatching query: String) throws -> MIDIDestination {
        let destinations = Self.availableDestinations()
        guard !destinations.isEmpty else {
            throw CoreMIDIOutputError.noDestinations
        }

        let exactMatches = destinations.filter {
            $0.name.compare(query, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        }
        let matches = exactMatches.isEmpty
            ? destinations.filter { $0.name.localizedCaseInsensitiveContains(query) }
            : exactMatches
        guard !matches.isEmpty else {
            throw CoreMIDIOutputError.noMatchingDestination(query)
        }
        guard matches.count == 1 else {
            throw CoreMIDIOutputError.ambiguousDestination(
                query,
                matches: matches.map(\.name)
            )
        }

        lock.lock()
        destination = matches[0]
        lock.unlock()
        return matches[0]
    }

    public func schedule(
        _ messages: [ScheduledMIDIMessage],
        anchorHostTime: UInt64
    ) throws {
        lock.lock()
        defer { lock.unlock() }
        guard let destination else {
            throw CoreMIDIOutputError.notConnected
        }

        for message in messages {
            let hostTime = MIDIHostTime.addingMicroseconds(
                message.offsetMicroseconds,
                to: anchorHostTime
            )
            try sendPacket(
                message.bytes,
                at: hostTime,
                destination: destination.endpoint
            )
        }
    }

    /// Sends an immediate MIDI Control Change. Live mix controls use CC7 on
    /// separate synth-part channels; this method never runs in the input callback.
    public func sendControlChange(
        controller: UInt8,
        value: UInt8,
        channel: UInt8
    ) throws {
        let bytes = try MIDIControlChangeEncoder.bytes(
            controller: controller,
            value: value,
            channel: channel
        )
        lock.lock()
        defer { lock.unlock() }
        guard let destination else {
            throw CoreMIDIOutputError.notConnected
        }
        try sendPacket(
            bytes,
            at: MIDIHostTime.now,
            destination: destination.endpoint
        )
    }

    /// Cancels timestamped packets not yet delivered, then silences the active
    /// output channel with All Notes Off and All Sound Off.
    public func stop(channel: UInt8 = 1) throws {
        lock.lock()
        defer { lock.unlock() }
        guard let destination else {
            return
        }

        let flushStatus = MIDIFlushOutput(destination.endpoint)
        let controlStatus = UInt8(0xB0 | ((channel - 1) & 0x0F))
        let now = MIDIHostTime.now
        try sendPacket(
            [controlStatus, 123, 0],
            at: now,
            destination: destination.endpoint
        )
        try sendPacket(
            [controlStatus, 120, 0],
            at: now,
            destination: destination.endpoint
        )
        guard flushStatus == noErr else {
            throw CoreMIDIOutputError.flush(flushStatus)
        }
    }

    private func sendPacket(
        _ bytes: [UInt8],
        at hostTime: MIDITimeStamp,
        destination: MIDIEndpointRef
    ) throws {
        let capacity = MemoryLayout<MIDIPacketList>.size
        let storage = UnsafeMutableRawPointer.allocate(
            byteCount: capacity,
            alignment: MemoryLayout<MIDIPacketList>.alignment
        )
        defer { storage.deallocate() }

        let packetList = storage.bindMemory(to: MIDIPacketList.self, capacity: 1)
        let packet = MIDIPacketListInit(packetList)
        let addedPacket = bytes.withUnsafeBufferPointer { buffer in
            guard let baseAddress = buffer.baseAddress else {
                return Optional<UnsafeMutablePointer<MIDIPacket>>.none
            }
            return MIDIPacketListAdd(
                packetList,
                capacity,
                packet,
                hostTime,
                buffer.count,
                baseAddress
            )
        }
        guard addedPacket != nil else {
            throw CoreMIDIOutputError.packetConstruction
        }

        let status = MIDISend(outputPort, destination, packetList)
        guard status == noErr else {
            throw CoreMIDIOutputError.send(status)
        }
    }

    private static func stringProperty(
        _ object: MIDIObjectRef,
        key: CFString
    ) -> String? {
        var value: Unmanaged<CFString>?
        guard MIDIObjectGetStringProperty(object, key, &value) == noErr else {
            return nil
        }
        return value?.takeRetainedValue() as String?
    }
}
