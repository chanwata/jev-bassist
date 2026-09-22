import Foundation

public struct RollingMIDIEvent: Codable, Equatable, Sendable {
    public let id: UInt64
    public let revision: UInt64
    public let noteID: UInt64?
    public let noteOnIndex: Int?
    public let message: ScheduledMIDIMessage

    public init(
        id: UInt64,
        revision: UInt64,
        noteID: UInt64?,
        noteOnIndex: Int? = nil,
        message: ScheduledMIDIMessage
    ) {
        self.id = id
        self.revision = revision
        self.noteID = noteID
        self.noteOnIndex = noteOnIndex
        self.message = message
    }
}

public struct RollingMIDICancellation: Codable, Equatable, Sendable {
    public let revision: UInt64
    public let canceledEventIDs: [UInt64]
    public let canceledNoteIDs: [UInt64]
    public let canceledRevisions: [UInt64]

    public init(
        revision: UInt64,
        canceledEventIDs: [UInt64],
        canceledNoteIDs: [UInt64],
        canceledRevisions: [UInt64] = []
    ) {
        self.revision = revision
        self.canceledEventIDs = canceledEventIDs
        self.canceledNoteIDs = canceledNoteIDs
        self.canceledRevisions = canceledRevisions
    }
}

public enum RollingMIDISchedulerError: Error, CustomStringConvertible, Equatable {
    case invalidHorizon(UInt64)

    public var description: String {
        switch self {
        case let .invalidHorizon(value):
            return "Scheduler horizon must be between 1,000 and 500,000 microseconds; received \(value)."
        }
    }
}

public struct RollingMIDIScheduler: Sendable {
    private struct NoteKey: Hashable, Sendable {
        let channel: UInt8
        let note: UInt8
    }

    public let horizonMicroseconds: UInt64

    private var pendingEvents: [RollingMIDIEvent] = []
    private var committedNoteIDs: Set<UInt64> = []
    private var nextEventID: UInt64 = 1
    private var nextNoteID: UInt64 = 1
    private var revision: UInt64 = 0
    private var lastDrainOffset: UInt64?

    public var pendingEventCount: Int {
        pendingEvents.count
    }

    public init(horizonMicroseconds: UInt64 = 50_000) throws {
        guard (1_000...500_000).contains(horizonMicroseconds) else {
            throw RollingMIDISchedulerError.invalidHorizon(horizonMicroseconds)
        }
        self.horizonMicroseconds = horizonMicroseconds
    }

    @discardableResult
    public mutating func submit(_ messages: [ScheduledMIDIMessage]) -> UInt64 {
        revision += 1
        var openNotes: [NoteKey: [UInt64]] = [:]
        var nextNoteOnIndex = 0
        let ordered = messages.sorted(by: messageOrder)
        for message in ordered {
            let key = NoteKey(channel: message.channel, note: message.note)
            let noteID: UInt64?
            let noteOnIndex: Int?
            switch message.kind {
            case .noteOn:
                noteID = nextNoteID
                noteOnIndex = nextNoteOnIndex
                openNotes[key, default: []].append(nextNoteID)
                nextNoteID += 1
                nextNoteOnIndex += 1
            case .noteOff:
                noteOnIndex = nil
                if var matches = openNotes[key], !matches.isEmpty {
                    noteID = matches.removeFirst()
                    openNotes[key] = matches
                } else {
                    noteID = nil
                }
            }
            pendingEvents.append(
                RollingMIDIEvent(
                    id: nextEventID,
                    revision: revision,
                    noteID: noteID,
                    noteOnIndex: noteOnIndex,
                    message: message
                )
            )
            nextEventID += 1
        }
        pendingEvents.sort(by: eventOrder)
        return revision
    }

    public mutating func drain(
        through offsetMicroseconds: UInt64
    ) throws -> [RollingMIDIEvent] {
        let effectiveOffset = max(offsetMicroseconds, lastDrainOffset ?? 0)
        lastDrainOffset = effectiveOffset
        let deadline = effectiveOffset.addingReportingOverflow(horizonMicroseconds)
        let maximumOffset = deadline.overflow ? UInt64.max : deadline.partialValue
        let dueCount = pendingEvents.prefix {
            $0.message.offsetMicroseconds <= maximumOffset
        }.count
        guard dueCount > 0 else { return [] }
        let due = Array(pendingEvents.prefix(dueCount))
        pendingEvents.removeFirst(dueCount)
        for event in due {
            guard let noteID = event.noteID else { continue }
            switch event.message.kind {
            case .noteOn:
                committedNoteIDs.insert(noteID)
            case .noteOff:
                committedNoteIDs.remove(noteID)
            }
        }
        return due
    }

    public mutating func yieldToHuman(
        at offsetMicroseconds: UInt64
    ) -> RollingMIDICancellation {
        revision += 1
        let canceledNoteIDs = Set(
            pendingEvents.compactMap { event -> UInt64? in
                guard event.message.kind == .noteOn,
                      event.message.offsetMicroseconds >= offsetMicroseconds else {
                    return nil
                }
                return event.noteID
            }
        )
        let canceledEvents = pendingEvents.filter { event in
            guard let noteID = event.noteID else { return false }
            return canceledNoteIDs.contains(noteID)
                && !committedNoteIDs.contains(noteID)
        }
        let canceledEventIDs = Set(canceledEvents.map(\.id))
        pendingEvents.removeAll { canceledEventIDs.contains($0.id) }
        return RollingMIDICancellation(
            revision: revision,
            canceledEventIDs: canceledEvents.map(\.id).sorted(),
            canceledNoteIDs: canceledNoteIDs.sorted(),
            canceledRevisions: Array(Set(canceledEvents.map(\.revision))).sorted()
        )
    }

    public mutating func cancelAllPending() -> RollingMIDICancellation {
        revision += 1
        let cancellation = RollingMIDICancellation(
            revision: revision,
            canceledEventIDs: pendingEvents.map(\.id).sorted(),
            canceledNoteIDs: Array(Set(pendingEvents.compactMap(\.noteID))).sorted(),
            canceledRevisions: Array(Set(pendingEvents.map(\.revision))).sorted()
        )
        pendingEvents.removeAll(keepingCapacity: false)
        return cancellation
    }

    private func messageOrder(
        _ left: ScheduledMIDIMessage,
        _ right: ScheduledMIDIMessage
    ) -> Bool {
        if left.offsetMicroseconds != right.offsetMicroseconds {
            return left.offsetMicroseconds < right.offsetMicroseconds
        }
        if left.kind != right.kind {
            return left.kind == .noteOff
        }
        if left.channel != right.channel {
            return left.channel < right.channel
        }
        return left.note < right.note
    }

    private func eventOrder(_ left: RollingMIDIEvent, _ right: RollingMIDIEvent) -> Bool {
        if messageOrder(left.message, right.message) {
            return true
        }
        if messageOrder(right.message, left.message) {
            return false
        }
        return left.id < right.id
    }
}
