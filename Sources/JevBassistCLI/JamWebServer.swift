import Dispatch
import Foundation
import JevBassistCore
import Network

struct JamWebState: Codable, Sendable {
    let running: Bool
    let tempoBPM: Double
    let beatsPerBar: Int
    let introBars: Int
    let brain: String
    let source: String
    let destination: String
    let startedAtUnixMilliseconds: Double?
    let bar: Int?
    let beat: Int?
    let phase: String
    let chord: String?
    let nextChord: String?
    let decisionSource: String?
    let decision: BassDecision?
    let lastNote: String?
    let appliedUserCue: BassUserCue?
    let queuedUserCue: BassUserCue?
    let queuedCueTargetBar: Int?
}

protocol JamWebControlling: AnyObject, Sendable {
    func startClockFromWeb()
    func setUserCueFromWeb(_ cue: BassUserCue?)
}

/// A loopback-only HTTP/SSE bridge. It never handles MIDI inside a Network
/// callback; commands are handed to JamSession's serial queue instead.
final class JamWebServer: @unchecked Sendable {
    private let queue = DispatchQueue(label: "dev.jev-bassist.web")
    private let listener: NWListener
    private let html: Data
    private let stopSignal: @Sendable () -> Void
    private var clients: [UUID: NWConnection] = [:]
    private var latestState: Data?
    private weak var controller: (any JamWebControlling)?

    init(port: UInt16 = 8765, stopSignal: @escaping @Sendable () -> Void) throws {
        guard let resourceURL = Bundle.module.url(forResource: "index", withExtension: "html") else {
            throw JamWebServerError.missingResource
        }
        html = try Data(contentsOf: resourceURL)
        self.stopSignal = stopSignal
        guard let endpointPort = NWEndpoint.Port(rawValue: port) else {
            throw JamWebServerError.invalidPort(port)
        }
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: endpointPort)
        listener = try NWListener(using: parameters)
    }

    func attach(controller: any JamWebControlling) {
        queue.async { [weak self, weak controller] in
            self?.controller = controller
        }
    }

    func start() {
        listener.newConnectionHandler = { [weak self] connection in
            self?.accept(connection)
        }
        listener.stateUpdateHandler = { state in
            if case let .failed(error) = state {
                FileHandle.standardError.write(Data("Web UI stopped: \(error)\n".utf8))
            }
        }
        listener.start(queue: queue)
    }

    func stop() {
        queue.sync {
            clients.values.forEach { $0.cancel() }
            clients.removeAll()
            listener.cancel()
        }
    }

    func publish(_ state: JamWebState) {
        queue.async { [weak self] in
            guard let self else { return }
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            guard let data = try? encoder.encode(state) else {
                return
            }
            latestState = data
            let frame = Self.eventFrame(data)
            for (id, connection) in clients {
                connection.send(content: frame, completion: .contentProcessed { [weak self] error in
                    if error != nil {
                        self?.queue.async { self?.removeClient(id) }
                    }
                })
            }
        }
    }

    private func accept(_ connection: NWConnection) {
        connection.stateUpdateHandler = { [weak self, weak connection] state in
            if case .failed = state {
                self?.remove(connection)
            } else if case .cancelled = state {
                self?.remove(connection)
            }
        }
        connection.start(queue: queue)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) {
            [weak self, weak connection] data, _, _, _ in
            guard let self, let connection, let data,
                  let request = String(data: data, encoding: .utf8) else {
                connection?.cancel()
                return
            }
            handle(request, connection: connection)
        }
    }

    private func handle(_ request: String, connection: NWConnection) {
        guard let requestLine = request.split(separator: "\n", maxSplits: 1).first else {
            respond(status: "400 Bad Request", body: Data(), connection: connection)
            return
        }
        let parts = requestLine.split(separator: " ")
        guard parts.count >= 2 else {
            respond(status: "400 Bad Request", body: Data(), connection: connection)
            return
        }

        switch (String(parts[0]), String(parts[1])) {
        case ("GET", "/"):
            respond(status: "200 OK", contentType: "text/html; charset=utf-8", body: html, connection: connection)
        case ("GET", "/events"):
            openEventStream(connection)
        case ("POST", "/api/start"):
            guard isTrustedBrowserRequest(request) else {
                respond(status: "403 Forbidden", body: Data(), connection: connection)
                return
            }
            controller?.startClockFromWeb()
            respond(status: "202 Accepted", body: Data("starting".utf8), connection: connection)
        case ("POST", "/api/stop"):
            guard isTrustedBrowserRequest(request) else {
                respond(status: "403 Forbidden", body: Data(), connection: connection)
                return
            }
            respond(status: "202 Accepted", body: Data("stopping".utf8), connection: connection) {
                self.stopSignal()
            }
        case ("POST", "/api/cue/give-space"):
            handleCue(.giveSpace, request: request, connection: connection)
        case ("POST", "/api/cue/lock-in"):
            handleCue(.lockIn, request: request, connection: connection)
        case ("POST", "/api/cue/push"):
            handleCue(.push, request: request, connection: connection)
        case ("POST", "/api/cue/surprise"):
            handleCue(.surprise, request: request, connection: connection)
        default:
            respond(status: "404 Not Found", body: Data("not found".utf8), connection: connection)
        }
    }

    private func handleCue(
        _ cue: BassUserCue?,
        request: String,
        connection: NWConnection
    ) {
        guard isTrustedBrowserRequest(request) else {
            respond(status: "403 Forbidden", body: Data(), connection: connection)
            return
        }
        controller?.setUserCueFromWeb(cue)
        respond(status: "202 Accepted", body: Data("queued".utf8), connection: connection)
    }

    private func isTrustedBrowserRequest(_ request: String) -> Bool {
        request.lowercased().contains("\r\norigin: http://127.0.0.1:8765\r\n")
    }

    private func openEventStream(_ connection: NWConnection) {
        let id = UUID()
        clients[id] = connection
        let headers = Data(
            "HTTP/1.1 200 OK\r\nContent-Type: text/event-stream\r\nCache-Control: no-cache\r\nConnection: keep-alive\r\n\r\n".utf8
        )
        var payload = headers
        if let latestState {
            payload.append(Self.eventFrame(latestState))
        }
        connection.send(content: payload, completion: .contentProcessed { [weak self] error in
            if error != nil {
                self?.queue.async { self?.removeClient(id) }
            }
        })
    }

    private func respond(
        status: String,
        contentType: String = "text/plain; charset=utf-8",
        body: Data,
        connection: NWConnection,
        completion: (@Sendable () -> Void)? = nil
    ) {
        var response = Data(
            "HTTP/1.1 \(status)\r\nContent-Type: \(contentType)\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n".utf8
        )
        response.append(body)
        connection.send(content: response, completion: .contentProcessed { _ in
            connection.cancel()
            completion?()
        })
    }

    private func remove(_ connection: NWConnection?) {
        guard let connection else { return }
        clients = clients.filter { $0.value !== connection }
    }

    private func removeClient(_ id: UUID) {
        clients.removeValue(forKey: id)?.cancel()
    }

    private static func eventFrame(_ json: Data) -> Data {
        var data = Data("data: ".utf8)
        data.append(json)
        data.append(Data("\n\n".utf8))
        return data
    }
}

enum JamWebServerError: Error, CustomStringConvertible {
    case invalidPort(UInt16)
    case missingResource

    var description: String {
        switch self {
        case let .invalidPort(port):
            return "Invalid Web UI port: \(port)."
        case .missingResource:
            return "The Web UI resource is missing from the executable."
        }
    }
}
