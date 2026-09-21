import XCTest
@testable import JevBassistCore

final class ConversationObservationTests: XCTestCase {
    func testSameHumanPhraseRecognizesOnlyMatchingPreviousResponse() {
        let matcher = InteractionMatcher()
        let human = motif(id: 9, pitches: [67, 69, 72, 71])
        let matching = response([55, 57, 60, 59])
        let different = response([55, 52, 54, 59])

        let matchingEvidence = matcher.compare(
            human: human,
            response: matching,
            responseEndedAtMicroseconds: 2_000_000,
            beatMicroseconds: 500_000
        )
        let differentEvidence = matcher.compare(
            human: human,
            response: different,
            responseEndedAtMicroseconds: 2_000_000,
            beatMicroseconds: 500_000
        )

        XCTAssertGreaterThan(matchingEvidence.confidence, differentEvidence.confidence + 0.2)
        XCTAssertEqual(matchingEvidence.kind, .imitation)
    }

    func testAcknowledgedResponseChangesSharedThemeSentToDecisionProvider() throws {
        let provider = RecordingConversationProvider()
        var engine = ConversationEngine(
            musicalStateConfiguration: try MusicalStateConfiguration(
                tempoBPM: 120,
                beatsPerBar: 4
            ),
            mode: .dorian,
            outputChannel: 3,
            decisionProvider: provider
        )
        let first = try XCTUnwrap(engine.submit(
            motif(id: 1, pitches: [62, 64, 67, 65]),
            availableAtMicroseconds: 2_000_000
        ))
        let lineage = try XCTUnwrap(first.conversationLineage)
        let noteCount = first.phrase.messages.filter { $0.kind == .noteOn }.count
        for _ in 0..<noteCount {
            engine.acknowledgeCommittedResponseNote(responseID: lineage.responseID)
        }
        let sounded = lineage.responseGesture.map(\.note)
        let reply = motif(id: 2, pitches: sounded.map { UInt8(min(127, Int($0) + 12)) })

        _ = engine.submit(reply, availableAtMicroseconds: 4_000_000)

        let state = try XCTUnwrap(provider.inputs.last?.state)
        XCTAssertEqual(state.sharedTheme.id, 2)
        XCTAssertGreaterThanOrEqual(state.interaction.confidence, 0.58)
        XCTAssertTrue([.imitation, .rhythmicReply, .continuation].contains(state.interaction.kind))
    }

    func testMeasuredDistanceDoesNotGrowForOctaveEcho() {
        let matcher = InteractionMatcher()
        let origin = motif(id: 1, pitches: [60, 62, 65, 64])
        let octaveEcho = response([48, 50, 53, 52])

        XCTAssertLessThan(matcher.distance(origin: origin, response: octaveEcho), 0.12)
    }

    private func response(_ pitches: [UInt8]) -> [ConversationResponseNote] {
        pitches.enumerated().map { index, pitch in
            ConversationResponseNote(
                note: pitch,
                velocity: 72,
                relativeOnsetBeats: Double(index) * 0.5,
                durationBeats: 0.35
            )
        }
    }

    private func motif(id: UInt64, pitches: [UInt8]) -> Motif {
        let notes = pitches.enumerated().map { index, pitch in
            MotifNote(
                sourceNoteID: UInt64(index + 1),
                note: pitch,
                velocity: 84,
                relativeOnsetBeats: Double(index) * 0.5,
                durationBeats: 0.35,
                restBeforeBeats: index == 0 ? 0 : 0.15,
                accent: index == 0 ? 1 : 0.8,
                releaseWasInferred: false
            )
        }
        return Motif(
            id: id,
            notes: notes,
            durationBeats: Double(pitches.count) * 0.5,
            boundaryConfidence: 0.9,
            melodyConfidence: 1,
            features: MotifFeatures(
                pitchIntervals: zip(pitches.dropFirst(), pitches).map { later, earlier in
                    Int(later) - Int(earlier)
                },
                accentedNoteIndices: [0],
                restedNoteIndices: [],
                characteristicIntervalIndices: []
            ),
            finalizedAtMicroseconds: id * 2_000_000
        )
    }
}

private final class RecordingConversationProvider: ConversationDecisionProvider, @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [ConversationSelectionInput] = []

    var inputs: [ConversationSelectionInput] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func prepare(_ input: ConversationSelectionInput) {
        lock.lock()
        storage.append(input)
        lock.unlock()
    }

    func resolution(
        for input: ConversationSelectionInput
    ) -> ConversationSelectionResolution? {
        ConversationSelectionResolution(
            candidateID: input.localCandidateID,
            source: .rules
        )
    }

    func expire(revision: UInt64) {}
    func cancelPendingDecisions() {}
}
