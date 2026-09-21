import Foundation

public enum PerformedNoteRelease: String, Codable, Equatable, Sendable {
    case observed
    case inferredAtSessionEnd
}

public struct PerformedNote: Codable, Equatable, Sendable {
    public let id: UInt64
    public let channel: UInt8
    public let note: UInt8
    public let velocity: UInt8
    public let onsetMicroseconds: UInt64
    public let releaseMicroseconds: UInt64
    public let release: PerformedNoteRelease

    public var durationMicroseconds: UInt64 {
        releaseMicroseconds - onsetMicroseconds
    }

    public init(
        id: UInt64,
        channel: UInt8,
        note: UInt8,
        velocity: UInt8,
        onsetMicroseconds: UInt64,
        releaseMicroseconds: UInt64,
        release: PerformedNoteRelease
    ) {
        self.id = id
        self.channel = channel
        self.note = note
        self.velocity = velocity
        self.onsetMicroseconds = onsetMicroseconds
        self.releaseMicroseconds = releaseMicroseconds
        self.release = release
    }
}

public enum PerformanceTrackerDiagnostic: Codable, Equatable, Sendable {
    case orphanNoteOff(channel: UInt8, note: UInt8, offsetMicroseconds: UInt64)
}

public struct PerformanceTrackerUpdate: Codable, Equatable, Sendable {
    public let completedNotes: [PerformedNote]
    public let diagnostics: [PerformanceTrackerDiagnostic]

    public init(
        completedNotes: [PerformedNote] = [],
        diagnostics: [PerformanceTrackerDiagnostic] = []
    ) {
        self.completedNotes = completedNotes
        self.diagnostics = diagnostics
    }
}

public enum PerformanceTrackerError: Error, CustomStringConvertible, Equatable {
    case tooManyActiveNotes(Int)
    case nonMonotonicEvent(offsetMicroseconds: UInt64)
    case nonMonotonicFinish(offsetMicroseconds: UInt64)
    case eventAfterFinish

    public var description: String {
        switch self {
        case let .tooManyActiveNotes(value):
            return "Performance tracker exceeded its \(value)-note active limit."
        case let .nonMonotonicEvent(offset):
            return "Performance event at \(offset) microseconds is earlier than the preceding event."
        case let .nonMonotonicFinish(offset):
            return "Performance finish at \(offset) microseconds is earlier than the preceding event."
        case .eventAfterFinish:
            return "Cannot ingest performance events after finish."
        }
    }
}

public struct PerformanceTracker: Sendable {
    private struct NoteKey: Hashable, Sendable {
        let channel: UInt8
        let note: UInt8
    }

    private struct ActiveNote: Sendable {
        let id: UInt64
        let channel: UInt8
        let note: UInt8
        let velocity: UInt8
        let onsetMicroseconds: UInt64
    }

    public let maximumActiveNotes: Int

    private var active: [NoteKey: [ActiveNote]] = [:]
    private var nextID: UInt64 = 1
    private var lastEventOffset: UInt64?
    private var finished = false

    public var activeNoteCount: Int {
        active.values.reduce(0) { $0 + $1.count }
    }

    public var hasActiveNotes: Bool {
        activeNoteCount > 0
    }

    public init(maximumActiveNotes: Int = 64) {
        precondition((1...256).contains(maximumActiveNotes))
        self.maximumActiveNotes = maximumActiveNotes
    }

    public mutating func ingest(
        _ event: SessionMIDIEvent
    ) throws -> PerformanceTrackerUpdate {
        guard !finished else {
            throw PerformanceTrackerError.eventAfterFinish
        }
        if let lastEventOffset, event.offsetMicroseconds < lastEventOffset {
            throw PerformanceTrackerError.nonMonotonicEvent(
                offsetMicroseconds: event.offsetMicroseconds
            )
        }

        let treatsAsRelease = event.kind == .noteOff
            || (event.kind == .noteOn && event.velocity == 0)
        let update: PerformanceTrackerUpdate
        if treatsAsRelease {
            update = release(
                channel: event.channel,
                note: event.note,
                at: event.offsetMicroseconds
            )
        } else {
            guard activeNoteCount < maximumActiveNotes else {
                throw PerformanceTrackerError.tooManyActiveNotes(maximumActiveNotes)
            }
            let key = NoteKey(channel: event.channel, note: event.note)
            active[key, default: []].append(
                ActiveNote(
                    id: nextID,
                    channel: event.channel,
                    note: event.note,
                    velocity: event.velocity,
                    onsetMicroseconds: event.offsetMicroseconds
                )
            )
            nextID += 1
            update = PerformanceTrackerUpdate()
        }
        lastEventOffset = event.offsetMicroseconds
        return update
    }

    public mutating func finish(
        through offsetMicroseconds: UInt64
    ) throws -> PerformanceTrackerUpdate {
        if let lastEventOffset, offsetMicroseconds < lastEventOffset {
            throw PerformanceTrackerError.nonMonotonicFinish(
                offsetMicroseconds: offsetMicroseconds
            )
        }
        guard !finished else {
            return PerformanceTrackerUpdate()
        }
        finished = true
        let completed = active.values
            .flatMap { $0 }
            .sorted {
                if $0.onsetMicroseconds != $1.onsetMicroseconds {
                    return $0.onsetMicroseconds < $1.onsetMicroseconds
                }
                return $0.id < $1.id
            }
            .map { note in
                PerformedNote(
                    id: note.id,
                    channel: note.channel,
                    note: note.note,
                    velocity: note.velocity,
                    onsetMicroseconds: note.onsetMicroseconds,
                    releaseMicroseconds: max(offsetMicroseconds, note.onsetMicroseconds),
                    release: .inferredAtSessionEnd
                )
            }
        active.removeAll(keepingCapacity: false)
        return PerformanceTrackerUpdate(completedNotes: completed)
    }

    private mutating func release(
        channel: UInt8,
        note: UInt8,
        at offsetMicroseconds: UInt64
    ) -> PerformanceTrackerUpdate {
        let key = NoteKey(channel: channel, note: note)
        guard var matches = active[key], !matches.isEmpty else {
            return PerformanceTrackerUpdate(
                diagnostics: [
                    .orphanNoteOff(
                        channel: channel,
                        note: note,
                        offsetMicroseconds: offsetMicroseconds
                    )
                ]
            )
        }
        let started = matches.removeFirst()
        if matches.isEmpty {
            active.removeValue(forKey: key)
        } else {
            active[key] = matches
        }
        return PerformanceTrackerUpdate(
            completedNotes: [
                PerformedNote(
                    id: started.id,
                    channel: started.channel,
                    note: started.note,
                    velocity: started.velocity,
                    onsetMicroseconds: started.onsetMicroseconds,
                    releaseMicroseconds: max(offsetMicroseconds, started.onsetMicroseconds),
                    release: .observed
                )
            ]
        )
    }
}
