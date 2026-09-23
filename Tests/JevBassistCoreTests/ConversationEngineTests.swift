import XCTest
@testable import JevBassistCore

final class ConversationEngineTests: XCTestCase {
    func testClearMotifProducesRecognizableOneVoiceAnswerOnNextBeat() throws {
        let configuration = try MusicalStateConfiguration(tempoBPM: 120, beatsPerBar: 4)
        var engine = ConversationEngine(
            musicalStateConfiguration: configuration,
            mode: .dorian,
            outputChannel: 3
        )
        let plan = try XCTUnwrap(engine.plan(for: motif()))
        let noteOns = plan.phrase.messages.filter { $0.kind == .noteOn }
        let noteOffs = plan.phrase.messages.filter { $0.kind == .noteOff }

        XCTAssertEqual(plan.phrase.startMicroseconds, 2_500_000)
        XCTAssertEqual(plan.developmentStage, nil)
        XCTAssertEqual(noteOns.map(\.offsetMicroseconds), [2_500_000, 2_800_000, 3_320_000])
        XCTAssertEqual(noteOns.map(\.note), [50, 53, 55])
        XCTAssertEqual(noteOns.count, noteOffs.count)
        XCTAssertLessThan(noteOffs[0].offsetMicroseconds, noteOns[1].offsetMicroseconds)
        XCTAssertLessThan(noteOffs[1].offsetMicroseconds, noteOns[2].offsetMicroseconds)
        XCTAssertTrue(plan.phrase.messages.allSatisfy { $0.channel == 3 })
    }

    func testModalProjectionMovesOnlyOutOfModePitchToNearestTone() {
        let context = ModalPitchContext(mode: .dorian, tonalCenterPitchClass: 2)

        XCTAssertEqual(context.conservativeProjection(62), 62)
        XCTAssertEqual(context.conservativeProjection(66), 65)
        XCTAssertTrue(context.contains(context.conservativeProjection(66)))
    }

    func testPhrasePlacementPreservesContourAcrossFormerRegisterBoundary() {
        let context = ModalPitchContext(
            mode: .ionian,
            tonalCenterPitchClass: 0
        )

        let placed = context.placePhrase([52, 53, 55])

        XCTAssertEqual(placed, [52, 53, 55])
        XCTAssertEqual(
            zip(placed.dropFirst(), placed).map { later, earlier in
                Int(later) - Int(earlier)
            },
            [1, 2]
        )
    }

    func testHighSubjectMovesAsOnePhraseIntoCompanionRegister() {
        let context = ModalPitchContext(
            mode: .dorian,
            tonalCenterPitchClass: 2
        )

        XCTAssertEqual(context.placePhrase([62, 65, 67]), [50, 53, 55])
    }

    func testModalInversionUsesScaleDegreesAndStaysSingleVoice() {
        let context = ModalPitchContext(
            mode: .dorian,
            tonalCenterPitchClass: 2
        )

        let inversion = context.invertByScaleDegrees([62, 65, 67])

        XCTAssertEqual(inversion, [62, 59, 57])
        XCTAssertTrue(inversion.allSatisfy(context.contains))
    }

    func testContextualDevelopmentKeepsOriginAndAdvancesHeardGeneration() throws {
        let configuration = try MusicalStateConfiguration(tempoBPM: 120, beatsPerBar: 4)
        var engine = ConversationEngine(
            musicalStateConfiguration: configuration,
            mode: .dorian,
            outputChannel: 3
        )

        let echo = try XCTUnwrap(engine.plan(for: motif(id: 1)))
        let second = try XCTUnwrap(engine.plan(for: motif(
            id: 2,
            pitches: [67, 70, 72],
            finalizedAt: 4_215_000
        )))
        let third = try XCTUnwrap(engine.plan(for: motif(
            id: 3,
            pitches: [62, 64, 65, 67, 69, 71],
            durationBeats: 2,
            finalizedAt: 6_215_000
        )))

        XCTAssertEqual(echo.conversationLineage?.relationship, .echo)
        XCTAssertEqual(second.conversationLineage?.originMotifID, 1)
        XCTAssertEqual(third.conversationLineage?.originMotifID, 1)
        XCTAssertEqual(echo.conversationLineage?.generation, 0)
        XCTAssertEqual(second.conversationLineage?.generation, 1)
        XCTAssertEqual(third.conversationLineage?.generation, 2)
        XCTAssertEqual(third.conversationLineage?.originGesture.map(\.note), [62, 65, 67])
        XCTAssertFalse(third.conversationLineage?.responseGesture.isEmpty ?? true)
    }

    func testPreparedRemoteCandidateNeverBlocksAndKeepsFutureOnset() throws {
        let provider = DeferredConversationProvider()
        var engine = ConversationEngine(
            musicalStateConfiguration: try MusicalStateConfiguration(
                tempoBPM: 120,
                beatsPerBar: 4
            ),
            mode: .dorian,
            outputChannel: 3,
            decisionProvider: provider
        )

        XCTAssertNil(engine.submit(motif(), availableAtMicroseconds: 2_215_000))
        XCTAssertEqual(provider.preparedRevisions, [1])
        provider.complete(revision: 1, candidateID: "inversion")
        let plan = try XCTUnwrap(engine.advance(through: 2_300_000))

        XCTAssertEqual(plan.decisionSource, .jev)
        XCTAssertEqual(plan.conversationLineage?.relationship, .inversion)
        XCTAssertEqual(plan.phrase.startMicroseconds, 2_375_000)
    }

    func testRemoteDeadlineExpiresRevisionAndUsesLocalCandidate() throws {
        let provider = DeferredConversationProvider()
        var engine = ConversationEngine(
            musicalStateConfiguration: try MusicalStateConfiguration(
                tempoBPM: 120,
                beatsPerBar: 4
            ),
            mode: .dorian,
            outputChannel: 3,
            decisionProvider: provider
        )

        XCTAssertNil(engine.submit(motif(), availableAtMicroseconds: 2_215_000))
        XCTAssertNil(engine.advance(through: 2_314_999))
        let plan = try XCTUnwrap(engine.advance(through: 2_315_000))

        XCTAssertEqual(plan.decisionSource, .fallback)
        XCTAssertEqual(plan.conversationLineage?.relationship, .echo)
        XCTAssertEqual(provider.expiredRevisions, [1])
    }

    func testGrooveConversationUsesFineSwungResponseGrid() throws {
        var engine = ConversationEngine(
            musicalStateConfiguration: try MusicalStateConfiguration(
                tempoBPM: 120,
                beatsPerBar: 4
            ),
            mode: .dorian,
            outputChannel: 3,
            grooveTiming: GrooveTiming(swing: 0.6, strength: 0.72)
        )

        let plan = try XCTUnwrap(engine.submit(
            motif(),
            availableAtMicroseconds: 2_215_000
        ))

        XCTAssertEqual(plan.phrase.startMicroseconds, 2_300_000)
        XCTAssertLessThan(plan.phrase.startMicroseconds - 2_215_000, 100_000)
        XCTAssertEqual(
            plan.phrase.messages
                .filter { $0.kind == .noteOn }
                .map(\.offsetMicroseconds),
            [2_300_000, 2_650_000, 3_150_000]
        )
    }

    func testDeferredGrooveDecisionRebasesCanonicalRhythmWithoutDoubleSwing() throws {
        let provider = DeferredConversationProvider()
        var engine = ConversationEngine(
            musicalStateConfiguration: try MusicalStateConfiguration(
                tempoBPM: 120,
                beatsPerBar: 4
            ),
            mode: .dorian,
            outputChannel: 3,
            grooveTiming: GrooveTiming(swing: 0.6, strength: 1),
            decisionProvider: provider
        )
        let source = motif(
            grooveStartSubdivision: 2,
            grooveOnsets: [0, 0.5, 1],
            groovePerformedOnsets: [0, 0.4, 1]
        )

        XCTAssertNil(engine.submit(source, availableAtMicroseconds: 2_215_000))
        let inversionSummary = try XCTUnwrap(
            provider.input(revision: 1)?.candidates.first { $0.id == "inversion" }
        )
        XCTAssertEqual(inversionSummary.relativeOnsets.count, 3)
        XCTAssertEqual(inversionSummary.relativeOnsets[0], 0, accuracy: 0.0001)
        XCTAssertEqual(inversionSummary.relativeOnsets[1], 0.4, accuracy: 0.0001)
        XCTAssertEqual(inversionSummary.relativeOnsets[2], 1, accuracy: 0.0001)
        provider.complete(revision: 1, candidateID: "inversion")
        let plan = try XCTUnwrap(engine.advance(through: 2_350_000))
        let onsets = plan.phrase.messages
            .filter { $0.kind == .noteOn }
            .map(\.offsetMicroseconds)

        XCTAssertEqual(plan.phrase.startMicroseconds, 2_800_000)
        XCTAssertEqual(onsets, [2_800_000, 3_000_000, 3_300_000])
    }

    func testHumanAttackDoesNotErasePendingPhraseDecision() throws {
        let provider = DeferredConversationProvider()
        var engine = ConversationEngine(
            musicalStateConfiguration: try MusicalStateConfiguration(
                tempoBPM: 120,
                beatsPerBar: 4
            ),
            mode: .dorian,
            outputChannel: 3,
            decisionProvider: provider
        )

        XCTAssertNil(engine.submit(motif(), availableAtMicroseconds: 2_215_000))
        engine.yieldToHuman()
        provider.complete(revision: 1, candidateID: "inversion")

        let plan = try XCTUnwrap(engine.advance(through: 2_300_000))
        XCTAssertEqual(plan.conversationLineage?.relationship, .inversion)
        XCTAssertTrue(provider.expiredRevisions.isEmpty)
    }

    func testConversationMemoryAdvancesOnlyAfterElapsedNoteOn() throws {
        var engine = ConversationEngine(
            musicalStateConfiguration: try MusicalStateConfiguration(
                tempoBPM: 120,
                beatsPerBar: 4
            ),
            mode: .dorian,
            outputChannel: 3
        )

        let first = try XCTUnwrap(engine.submit(
            motif(id: 1),
            availableAtMicroseconds: 2_215_000
        ))
        let firstResponseID = try XCTUnwrap(first.conversationLineage?.responseID)
        let beforeCommit = try XCTUnwrap(engine.submit(
            motif(id: 2, finalizedAt: 4_215_000),
            availableAtMicroseconds: 4_215_000
        ))
        XCTAssertNil(beforeCommit.conversationLineage?.parentResponseID)

        engine.acknowledgeElapsedResponseNote(responseID: firstResponseID)
        let afterCommit = try XCTUnwrap(engine.submit(
            motif(id: 3, finalizedAt: 6_215_000),
            availableAtMicroseconds: 6_215_000
        ))
        XCTAssertEqual(afterCommit.conversationLineage?.parentResponseID, firstResponseID)
    }

    func testSilenceProducesOneAutonomousProposalThenWaits() throws {
        var engine = ConversationEngine(
            musicalStateConfiguration: try MusicalStateConfiguration(
                tempoBPM: 120,
                beatsPerBar: 4
            ),
            mode: .dorian,
            outputChannel: 3
        )

        let answer = try XCTUnwrap(engine.submit(
            motif(id: 1),
            availableAtMicroseconds: 2_215_000
        ))
        let answerID = try XCTUnwrap(answer.conversationLineage?.responseID)
        let answerAttacks = answer.phrase.messages.filter { $0.kind == .noteOn }
        for _ in answerAttacks {
            engine.acknowledgeElapsedResponseNote(responseID: answerID)
        }
        let answerEnd = try XCTUnwrap(
            answer.phrase.messages.map(\.offsetMicroseconds).max()
        )

        let proposal = try XCTUnwrap(
            engine.advance(through: answerEnd + 1_000_000)
        )
        XCTAssertEqual(proposal.conversationLineage?.intent, .question)
        XCTAssertTrue(
            proposal.conversationLineage.map {
                [
                    ConversationRelationship.fragmentation,
                    .tailVariation,
                    .hold
                ].contains($0.relationship)
            } == true
        )

        let proposalID = try XCTUnwrap(proposal.conversationLineage?.responseID)
        for _ in proposal.phrase.messages.filter({ $0.kind == .noteOn }) {
            engine.acknowledgeElapsedResponseNote(responseID: proposalID)
        }
        let proposalEnd = try XCTUnwrap(
            proposal.phrase.messages.map(\.offsetMicroseconds).max()
        )
        XCTAssertNil(engine.advance(through: proposalEnd + 4_000_000))
    }

    private func motif(
        id: UInt64 = 1,
        pitches: [UInt8] = [62, 65, 67],
        durationBeats: Double = 2.12,
        finalizedAt: UInt64 = 2_215_000,
        grooveStartSubdivision: Int? = nil,
        grooveOnsets: [Double?]? = nil,
        groovePerformedOnsets: [Double]? = nil
    ) -> Motif {
        let onsetStep = durationBeats / Double(max(1, pitches.count))
        let preservedOnsets = [0.0, 0.6, 1.64]
        let preservedDurations = [0.32, 0.72, 0.48]
        let notes = pitches.enumerated().map { index, pitch in
            MotifNote(
                sourceNoteID: UInt64(index + 1),
                note: pitch,
                velocity: index == 0 ? 96 : 82,
                relativeOnsetBeats: groovePerformedOnsets?[index]
                    ?? (pitches.count == 3
                        ? preservedOnsets[index]
                        : Double(index) * onsetStep),
                grooveOnsetBeats: grooveOnsets?[index],
                durationBeats: pitches.count == 3
                    ? preservedDurations[index]
                    : max(0.12, onsetStep * 0.7),
                restBeforeBeats: index == 0 ? 0 : onsetStep * 0.3,
                accent: index == 0 ? 1 : 0.85,
                releaseWasInferred: false
            )
        }
        let intervals = zip(pitches.dropFirst(), pitches).map { later, earlier in
            Int(later) - Int(earlier)
        }
        return Motif(
            id: id,
            notes: notes,
            durationBeats: durationBeats,
            boundaryConfidence: 0.9,
            melodyConfidence: 1,
            features: MotifFeatures(
                pitchIntervals: intervals,
                accentedNoteIndices: [0],
                restedNoteIndices: Array(notes.indices.dropFirst()),
                characteristicIntervalIndices: []
            ),
            finalizedAtMicroseconds: finalizedAt,
            grooveStartSubdivision: grooveStartSubdivision
        )
    }
}

private final class DeferredConversationProvider: ConversationDecisionProvider, @unchecked Sendable {
    private let lock = NSLock()
    private var inputs: [UInt64: ConversationSelectionInput] = [:]
    private var completed: [UInt64: String] = [:]
    private(set) var preparedRevisions: [UInt64] = []
    private(set) var expiredRevisions: [UInt64] = []

    func prepare(_ input: ConversationSelectionInput) {
        lock.lock()
        inputs[input.revision] = input
        preparedRevisions.append(input.revision)
        lock.unlock()
    }

    func resolution(
        for input: ConversationSelectionInput
    ) -> ConversationSelectionResolution? {
        lock.lock()
        let candidateID = completed.removeValue(forKey: input.revision)
        lock.unlock()
        return candidateID.map {
            ConversationSelectionResolution(candidateID: $0, source: .jev)
        }
    }

    func expire(revision: UInt64) {
        lock.lock()
        inputs.removeValue(forKey: revision)
        completed.removeValue(forKey: revision)
        expiredRevisions.append(revision)
        lock.unlock()
    }

    func cancelPendingDecisions() {}

    func complete(revision: UInt64, candidateID: String) {
        lock.lock()
        if inputs[revision] != nil {
            completed[revision] = candidateID
        }
        lock.unlock()
    }

    func input(revision: UInt64) -> ConversationSelectionInput? {
        lock.lock()
        defer { lock.unlock() }
        return inputs[revision]
    }
}
