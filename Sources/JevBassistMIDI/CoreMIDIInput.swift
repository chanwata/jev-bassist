@preconcurrency import CoreMIDI
import Dispatch
import Foundation
import JevBassistCore

public struct MIDISource: Equatable, Sendable {
    public let endpoint: MIDIEndpointRef
    public let name: String
    public let manufacturer: String?

    public init(endpoint: MIDIEndpointRef, name: String, manufacturer: String?) {
        self.endpoint = endpoint
        self.name = name
        self.manufacturer = manufacturer
    }
}

public enum CoreMIDIInputError: Error, CustomStringConvertible {
    case clientCreation(OSStatus)
    case portCreation(OSStatus)
    case noSources
    case noMatchingSource(String)
    case connection(source: String, status: OSStatus)

    public var description: String {
        switch self {
        case let .clientCreation(status):
            return "CoreMIDI client creation failed (OSStatus \(status))."
        case let .portCreation(status):
            return "CoreMIDI input port creation failed (OSStatus \(status))."
        case .noSources:
            return "No MIDI input sources are available."
        case let .noMatchingSource(query):
            return "No MIDI input source matched '\(query)'. Run 'jev-bassist devices' to list sources."
        case let .connection(source, status):
            return "Could not connect to MIDI source '\(source)' (OSStatus \(status))."
        }
    }
}

public final class CoreMIDIInput: @unchecked Sendable {
    public typealias EventHandler = @Sendable (MIDIEvent) -> Void

    private var client = MIDIClientRef()
    private var inputPort = MIDIPortRef()
    private var connectedEndpoints: [MIDIEndpointRef] = []
    private let decoder = LockedMIDIDecoder()
    private let processingQueue = DispatchQueue(label: "dev.jev-bassist.midi-processing")
    private let handler: EventHandler

    public init(handler: @escaping EventHandler) throws {
        self.handler = handler

        var newClient = MIDIClientRef()
        let clientStatus = MIDIClientCreateWithBlock(
            "Jev Bassist" as CFString,
            &newClient
        ) { _ in }

        guard clientStatus == noErr else {
            throw CoreMIDIInputError.clientCreation(clientStatus)
        }
        client = newClient

        var newPort = MIDIPortRef()
        let portStatus = MIDIInputPortCreateWithBlock(
            client,
            "Jev Bassist Input" as CFString,
            &newPort
        ) { [weak self] packetList, _ in
            self?.receive(packetList)
        }

        guard portStatus == noErr else {
            MIDIClientDispose(client)
            client = MIDIClientRef()
            throw CoreMIDIInputError.portCreation(portStatus)
        }
        inputPort = newPort
    }

    deinit {
        for endpoint in connectedEndpoints {
            MIDIPortDisconnectSource(inputPort, endpoint)
        }
        if inputPort != 0 {
            MIDIPortDispose(inputPort)
        }
        if client != 0 {
            MIDIClientDispose(client)
        }
    }

    public static func availableSources() -> [MIDISource] {
        (0..<MIDIGetNumberOfSources()).compactMap { index in
            let endpoint = MIDIGetSource(index)
            guard endpoint != 0 else {
                return nil
            }
            return MIDISource(
                endpoint: endpoint,
                name: stringProperty(endpoint, key: kMIDIPropertyDisplayName) ?? "Unnamed source \(index + 1)",
                manufacturer: stringProperty(endpoint, key: kMIDIPropertyManufacturer)
            )
        }
    }

    @discardableResult
    public func connect(sourceMatching query: String? = nil) throws -> [MIDISource] {
        let sources = Self.availableSources()
        guard !sources.isEmpty else {
            throw CoreMIDIInputError.noSources
        }

        let selected: [MIDISource]
        if let query, !query.isEmpty {
            selected = sources.filter {
                $0.name.localizedCaseInsensitiveContains(query)
            }
            guard !selected.isEmpty else {
                throw CoreMIDIInputError.noMatchingSource(query)
            }
        } else {
            selected = sources
        }

        for source in selected where !connectedEndpoints.contains(source.endpoint) {
            let status = MIDIPortConnectSource(inputPort, source.endpoint, nil)
            guard status == noErr else {
                throw CoreMIDIInputError.connection(source: source.name, status: status)
            }
            connectedEndpoints.append(source.endpoint)
        }

        return selected
    }

    private func receive(_ packetList: UnsafePointer<MIDIPacketList>) {
        var packets: [(hostTime: UInt64, bytes: [UInt8])] = []

        withUnsafePointer(to: packetList.pointee.packet) { firstPacket in
            var packetPointer = firstPacket

            for _ in 0..<packetList.pointee.numPackets {
                let packet = packetPointer.pointee
                let bytes = withUnsafeBytes(of: packet.data) {
                    Array($0.prefix(Int(packet.length)))
                }
                packets.append((hostTime: packet.timeStamp, bytes: bytes))
                packetPointer = MIDIPacketNext(packetPointer)
            }
        }

        let receivedAt = Date()
        processingQueue.async { [weak self, packets] in
            guard let self else {
                return
            }
            for packet in packets {
                let events = decoder.decode(
                    packet.bytes,
                    hostTime: packet.hostTime,
                    receivedAt: receivedAt
                )
                for event in events {
                    handler(event)
                }
            }
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

private final class LockedMIDIDecoder: @unchecked Sendable {
    private let lock = NSLock()
    private var parser = MIDIByteParser()

    func decode(
        _ bytes: [UInt8],
        hostTime: UInt64,
        receivedAt: Date
    ) -> [MIDIEvent] {
        lock.lock()
        defer { lock.unlock() }
        return parser.parse(bytes, hostTime: hostTime, receivedAt: receivedAt)
    }
}
