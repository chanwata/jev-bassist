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

/// Own this object and call `connect` from one control thread. Event delivery is
/// handed to a private serial queue, but CoreMIDI lifecycle state is not Sendable.
public final class CoreMIDIInput {
    public typealias EventHandler = @Sendable (MIDIEvent) -> Void

    private var client = MIDIClientRef()
    private var inputPort = MIDIPortRef()
    private var connectionContexts: [MIDIEndpointRef: MIDIConnectionContext] = [:]
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
        ) { [weak self] packetList, sourceConnectionRefCon in
            guard let self, let sourceConnectionRefCon else {
                return
            }
            let context = Unmanaged<MIDIConnectionContext>
                .fromOpaque(sourceConnectionRefCon)
                .takeUnretainedValue()
            receive(packetList, sourceID: context.endpoint)
        }

        guard portStatus == noErr else {
            MIDIClientDispose(client)
            client = MIDIClientRef()
            throw CoreMIDIInputError.portCreation(portStatus)
        }
        inputPort = newPort
    }

    deinit {
        for endpoint in connectionContexts.keys {
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

        for source in selected where connectionContexts[source.endpoint] == nil {
            let context = MIDIConnectionContext(endpoint: source.endpoint)
            let opaqueContext = Unmanaged.passUnretained(context).toOpaque()
            let status = MIDIPortConnectSource(inputPort, source.endpoint, opaqueContext)
            guard status == noErr else {
                throw CoreMIDIInputError.connection(source: source.name, status: status)
            }
            connectionContexts[source.endpoint] = context
        }

        return selected
    }

    private func receive(
        _ packetList: UnsafePointer<MIDIPacketList>,
        sourceID: MIDIEndpointRef
    ) {
        let packets = MIDIPacketListReader.copyPackets(from: packetList)

        let receivedAt = Date()
        let decoder = decoder
        let handler = handler
        processingQueue.async { [packets, decoder, handler] in
            for packet in packets {
                let events = decoder.decode(
                    packet.bytes,
                    streamID: sourceID,
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

private final class MIDIConnectionContext: @unchecked Sendable {
    let endpoint: MIDIEndpointRef

    init(endpoint: MIDIEndpointRef) {
        self.endpoint = endpoint
    }
}

private final class LockedMIDIDecoder: @unchecked Sendable {
    private let lock = NSLock()
    private var parser = MIDIStreamParser<MIDIEndpointRef>()

    func decode(
        _ bytes: [UInt8],
        streamID: MIDIEndpointRef,
        hostTime: UInt64,
        receivedAt: Date
    ) -> [MIDIEvent] {
        lock.lock()
        defer { lock.unlock() }
        return parser.parse(
            bytes,
            streamID: streamID,
            hostTime: hostTime,
            receivedAt: receivedAt
        )
    }
}
