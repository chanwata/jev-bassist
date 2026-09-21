import Foundation
import XCTest
@testable import JevBassistCore

final class LocalBassistTests: XCTestCase {
    func testRulePolicyLeavesSpaceForDensePlayingAndMovesDuringSilence() {
        let provider = RuleBasedBassDecisionProvider()
        let chord = ChordCandidate(rootPitchClass: 0, quality: .minor, confidence: 0.9)

        let dense = provider.decision(
            for: BassDecisionInput(
                state: state(noteCount: 8, density: 2),
                chord: chord,
                isHeldChord: false,
                targetBarIndex: 4
            )
        )
        let silent = provider.decision(
            for: BassDecisionInput(
                state: state(noteCount: 0, density: 0),
                chord: chord,
                isHeldChord: true,
                targetBarIndex: 5
            )
        )

        XCTAssertEqual(dense.activity, .sparse)
        XCTAssertEqual(dense.relationship, .contrast)
        XCTAssertEqual(silent.activity, .normal)
        XCTAssertEqual(silent.relationship, .hold)
        XCTAssertLessThan(silent.confidence, dense.confidence)
    }

    func testRulePolicyRestsWithoutKnownHarmony() {
        let decision = RuleBasedBassDecisionProvider().decision(
            for: BassDecisionInput(
                state: state(noteCount: 4, density: 1),
                chord: nil,
                isHeldChord: false,
                targetBarIndex: 4
            )
        )

        XCTAssertEqual(decision.activity, .rest)
        XCTAssertEqual(decision.confidence, 1)
    }

    func testLegacyDecisionInputDefaultsToBassStyle() throws {
        let input = BassDecisionInput(
            state: state(noteCount: 1, density: 0.25),
            chord: ChordCandidate(rootPitchClass: 0, quality: .major, confidence: 1),
            isHeldChord: false,
            targetBarIndex: 4
        )
        let encoded = try JSONEncoder().encode(input)
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        object.removeValue(forKey: "style")

        let legacyData = try JSONSerialization.data(withJSONObject: object)
        let decoded = try JSONDecoder().decode(BassDecisionInput.self, from: legacyData)

        XCTAssertEqual(decoded.style, .bass)
    }

    func testModalHarmonyInfersDAsCenterForDDorianSubject() {
        let planner = ModalHarmonyPlanner(mode: .dorian)
        let notes = [
            HumanPhraseNote(note: 62, velocity: 92, positionBeats: 0),
            HumanPhraseNote(note: 65, velocity: 82, positionBeats: 0.5),
            HumanPhraseNote(note: 67, velocity: 80, positionBeats: 1),
            HumanPhraseNote(note: 69, velocity: 86, positionBeats: 1.5),
            HumanPhraseNote(note: 74, velocity: 88, positionBeats: 2)
        ]

        let center = planner.inferTonalCenter(from: notes)
        XCTAssertEqual(center, 2)
        XCTAssertEqual(
            planner.chord(tonalCenterPitchClass: 2, stage: .answer),
            ChordCandidate(rootPitchClass: 9, quality: .minor, confidence: 1)
        )
        XCTAssertEqual(
            planner.chord(tonalCenterPitchClass: 2, stage: .returnOfSubject),
            ChordCandidate(rootPitchClass: 2, quality: .minor, confidence: 1)
        )
    }

    func testFugueRequiresModeAndRejectsFixedProgression() throws {
        let musicalState = try MusicalStateConfiguration()
        XCTAssertThrowsError(
            try LocalBassistConfiguration(musicalState: musicalState, style: .fugue)
        ) { error in
            XCTAssertEqual(error as? LocalBassistError, .fugueRequiresMode)
        }
        XCTAssertThrowsError(
            try LocalBassistConfiguration(
                musicalState: musicalState,
                progression: try ChordProgressionParser.parse("Dm7,G7"),
                style: .fugue,
                mode: .dorian
            )
        ) { error in
            XCTAssertEqual(error as? LocalBassistError, .fugueDoesNotUseProgression)
        }
    }

    func testPhraseGeneratorProducesDeterministicPairedNotesInBassRange() throws {
        let generator = BassPhraseGenerator(outputChannel: 3)
        let decision = BassDecision(
            activity: .normal,
            relationship: .follow,
            motion: .step,
            fill: false,
            confidence: 0.9
        )
        let phrase = generator.generate(
            decision: decision,
            chord: ChordCandidate(rootPitchClass: 0, quality: .minor, confidence: 1),
            barIndex: 4,
            startMicroseconds: 8_000_000,
            musicalStateConfiguration: try MusicalStateConfiguration(
                tempoBPM: 120,
                beatsPerBar: 4
            )
        )

        let noteOns = phrase.messages.filter { $0.kind == .noteOn }
        let noteOffs = phrase.messages.filter { $0.kind == .noteOff }
        XCTAssertEqual(noteOns.map(\.note), [36, 38, 39, 41])
        XCTAssertEqual(
            noteOns.map(\.offsetMicroseconds),
            [8_000_000, 8_750_000, 9_000_000, 9_750_000]
        )
        XCTAssertEqual(noteOffs.count, noteOns.count)
        XCTAssertTrue(phrase.messages.allSatisfy { (36...48).contains($0.note) })
        XCTAssertEqual(noteOns.map(\.velocity), [80, 70, 74, 70])
        XCTAssertEqual(noteOns[0].bytes, [0x92, 36, 80])
        XCTAssertEqual(noteOffs[0].bytes, [0x82, 36, 0])
    }

    func testPhraseGeneratorUsesRelationshipForRhythmicPocket() throws {
        let generator = BassPhraseGenerator(outputChannel: 3)
        let chord = ChordCandidate(rootPitchClass: 0, quality: .minor, confidence: 1)
        let configuration = try MusicalStateConfiguration(tempoBPM: 120, beatsPerBar: 4)
        let follow = generator.generate(
            decision: BassDecision(
                activity: .normal,
                relationship: .follow,
                motion: .root,
                fill: false,
                confidence: 1
            ),
            chord: chord,
            barIndex: 4,
            startMicroseconds: 0,
            musicalStateConfiguration: configuration
        )
        let contrast = generator.generate(
            decision: BassDecision(
                activity: .normal,
                relationship: .contrast,
                motion: .root,
                fill: false,
                confidence: 1
            ),
            chord: chord,
            barIndex: 4,
            startMicroseconds: 0,
            musicalStateConfiguration: configuration
        )

        XCTAssertEqual(
            follow.messages.filter { $0.kind == .noteOn }.map(\.offsetMicroseconds),
            [0, 750_000, 1_000_000, 1_750_000]
        )
        XCTAssertEqual(
            contrast.messages.filter { $0.kind == .noteOn }.map(\.offsetMicroseconds),
            [0, 750_000, 1_375_000]
        )
    }

    func testPhraseGeneratorVoiceLeadsAcrossBToCWithoutOctaveDrop() throws {
        let phrase = BassPhraseGenerator(outputChannel: 3).generate(
            decision: BassDecision(
                activity: .sparse,
                relationship: .follow,
                motion: .root,
                fill: false,
                confidence: 1
            ),
            chord: ChordCandidate(rootPitchClass: 0, quality: .major, confidence: 1),
            barIndex: 4,
            startMicroseconds: 0,
            musicalStateConfiguration: try MusicalStateConfiguration(),
            previousBassNote: 47,
            humanAverageVelocity: 80
        )

        XCTAssertEqual(
            phrase.messages.filter { $0.kind == .noteOn }.first?.note,
            48
        )
    }

    func testPhraseGeneratorUsesFlatFifthForDiminishedChord() throws {
        let phrase = BassPhraseGenerator(outputChannel: 3).generate(
            decision: BassDecision(
                activity: .normal,
                relationship: .follow,
                motion: .leap,
                fill: false,
                confidence: 1
            ),
            chord: ChordCandidate(rootPitchClass: 0, quality: .diminished, confidence: 1),
            barIndex: 4,
            startMicroseconds: 0,
            musicalStateConfiguration: try MusicalStateConfiguration()
        )

        XCTAssertEqual(
            phrase.messages.filter { $0.kind == .noteOn }.map(\.note),
            [36, 42, 39, 42]
        )
    }

    func testFillApproachesKnownNextChordAndStaysSafeWithoutOne() throws {
        let generator = BassPhraseGenerator(outputChannel: 3)
        let decision = BassDecision(
            activity: .normal,
            relationship: .follow,
            motion: .approach,
            fill: true,
            confidence: 1
        )
        let configuration = try MusicalStateConfiguration()
        let currentChord = ChordCandidate(rootPitchClass: 0, quality: .major, confidence: 1)
        let withoutTarget = generator.generate(
            decision: decision,
            chord: currentChord,
            barIndex: 4,
            startMicroseconds: 0,
            musicalStateConfiguration: configuration,
            previousBassNote: nil,
            humanAverageVelocity: nil
        )
        let towardF = generator.generate(
            decision: decision,
            chord: currentChord,
            barIndex: 4,
            startMicroseconds: 0,
            musicalStateConfiguration: configuration,
            previousBassNote: nil,
            humanAverageVelocity: nil,
            nextChord: ChordCandidate(rootPitchClass: 5, quality: .major, confidence: 1)
        )

        XCTAssertEqual(withoutTarget.messages.filter { $0.kind == .noteOn }.last?.note, 43)
        XCTAssertEqual(towardF.messages.filter { $0.kind == .noteOn }.last?.note, 40)
    }

    func testAmbientGeneratorMakesOneDelayedSustainedDyad() throws {
        let phrase = AmbientPhraseGenerator(outputChannel: 2).generate(
            decision: BassDecision(
                activity: .normal,
                relationship: .contrast,
                motion: .step,
                fill: false,
                confidence: 1
            ),
            chord: ChordCandidate(rootPitchClass: 0, quality: .major, confidence: 1),
            barIndex: 4,
            startMicroseconds: 0,
            musicalStateConfiguration: try MusicalStateConfiguration(
                tempoBPM: 120,
                beatsPerBar: 4
            ),
            previousNotes: [],
            humanAverageVelocity: 80
        )

        let noteOns = phrase.messages.filter { $0.kind == .noteOn }
        let noteOffs = phrase.messages.filter { $0.kind == .noteOff }
        XCTAssertEqual(noteOns.map(\.note), [52, 55])
        XCTAssertEqual(noteOns.map(\.offsetMicroseconds), [500_000, 500_000])
        XCTAssertEqual(noteOns.map(\.velocity), [38, 35])
        XCTAssertEqual(noteOffs.map(\.offsetMicroseconds), [1_950_000, 1_950_000])
        XCTAssertTrue(noteOns.allSatisfy { $0.channel == 2 })
    }

    func testAmbientActivityChangesWidthWithoutAddingAttacks() throws {
        let generator = AmbientPhraseGenerator(outputChannel: 2)
        let chord = ChordCandidate(rootPitchClass: 2, quality: .minor, confidence: 1)
        let configuration = try MusicalStateConfiguration(tempoBPM: 90, beatsPerBar: 4)

        for (activity, expectedVoiceCount) in [
            (BassActivity.rest, 0),
            (.sparse, 1),
            (.normal, 2),
            (.busy, 3)
        ] {
            let phrase = generator.generate(
                decision: BassDecision(
                    activity: activity,
                    relationship: .follow,
                    motion: .root,
                    fill: false,
                    confidence: 1
                ),
                chord: chord,
                barIndex: 4,
                startMicroseconds: 0,
                musicalStateConfiguration: configuration,
                previousNotes: [],
                humanAverageVelocity: nil
            )
            let noteOns = phrase.messages.filter { $0.kind == .noteOn }

            XCTAssertEqual(noteOns.count, expectedVoiceCount)
            XCTAssertLessThanOrEqual(Set(noteOns.map(\.offsetMicroseconds)).count, 1)
        }
    }

    func testAmbientGeneratorVoiceLeadsWithoutAnOctaveJump() throws {
        let phrase = AmbientPhraseGenerator(outputChannel: 2).generate(
            decision: BassDecision(
                activity: .busy,
                relationship: .hold,
                motion: .leap,
                fill: true,
                confidence: 1
            ),
            chord: ChordCandidate(rootPitchClass: 0, quality: .major, confidence: 1),
            barIndex: 5,
            startMicroseconds: 0,
            musicalStateConfiguration: try MusicalStateConfiguration(),
            previousNotes: [59, 66, 71],
            humanAverageVelocity: nil
        )

        XCTAssertEqual(
            phrase.messages.filter { $0.kind == .noteOn }.map(\.note),
            [60, 64, 67]
        )
        XCTAssertTrue(
            phrase.messages.filter { $0.kind == .noteOn }.allSatisfy { $0.velocity <= 36 }
        )
    }

    func testMemoryGeneratorReturnsRecognizableDelayedContour() throws {
        let result = MemoryPhraseGenerator(outputChannel: 2).generate(
            decision: BassDecision(
                activity: .normal,
                relationship: .follow,
                motion: .root,
                fill: false,
                confidence: 1
            ),
            chord: ChordCandidate(rootPitchClass: 2, quality: .minor, confidence: 1),
            barIndex: 4,
            startMicroseconds: 0,
            musicalStateConfiguration: try MusicalStateConfiguration(
                tempoBPM: 120,
                beatsPerBar: 4
            ),
            memory: HumanPhraseMemory(
                notes: [
                    HumanPhraseNote(note: 60, velocity: 86, positionBeats: 0),
                    HumanPhraseNote(note: 63, velocity: 82, positionBeats: 0.5),
                    HumanPhraseNote(note: 67, velocity: 78, positionBeats: 1)
                ]
            ),
            previousNotes: [],
            humanAverageVelocity: 80
        )

        let noteOns = result.phrase.messages.filter { $0.kind == .noteOn }
        XCTAssertEqual(noteOns.map(\.note), [62, 65, 69])
        XCTAssertEqual(noteOns.map(\.offsetMicroseconds), [375_000, 875_000, 1_375_000])
        XCTAssertTrue(noteOns.allSatisfy { $0.channel == 2 && $0.velocity <= 52 })
        XCTAssertGreaterThan(result.expression.memory, 0.7)
        XCTAssertGreaterThan(result.expression.resonance, 0.5)
    }

    func testMemoryGeneratorLetsOldPhraseFadeToSilence() throws {
        let generator = MemoryPhraseGenerator(outputChannel: 2)
        let decision = BassDecision(
            activity: .sparse,
            relationship: .contrast,
            motion: .approach,
            fill: true,
            confidence: 1
        )
        let configuration = try MusicalStateConfiguration(tempoBPM: 90, beatsPerBar: 4)
        let notes = [HumanPhraseNote(note: 64, velocity: 88, positionBeats: 1)]
        let remembered = generator.generate(
            decision: decision,
            chord: ChordCandidate(rootPitchClass: 0, quality: .major, confidence: 1),
            barIndex: 3,
            startMicroseconds: 0,
            musicalStateConfiguration: configuration,
            memory: HumanPhraseMemory(notes: notes, ageBars: 2),
            previousNotes: [],
            humanAverageVelocity: nil
        )
        let forgotten = generator.generate(
            decision: decision,
            chord: ChordCandidate(rootPitchClass: 0, quality: .major, confidence: 1),
            barIndex: 4,
            startMicroseconds: 0,
            musicalStateConfiguration: configuration,
            memory: HumanPhraseMemory(notes: notes, ageBars: 3),
            previousNotes: [],
            humanAverageVelocity: nil
        )

        XCTAssertEqual(remembered.phrase.messages.filter { $0.kind == .noteOn }.count, 1)
        XCTAssertLessThan(remembered.expression.memory, 0.5)
        XCTAssertTrue(forgotten.phrase.messages.isEmpty)
        XCTAssertEqual(forgotten.expression, .quiet)
    }

    func testFugueGeneratorAnswersOnDominantWithContraryCountersubject() throws {
        let result = FuguePhraseGenerator(outputChannel: 2).generate(
            decision: BassDecision(
                activity: .normal,
                relationship: .follow,
                motion: .root,
                fill: false,
                confidence: 1
            ),
            chord: ChordCandidate(rootPitchClass: 0, quality: .major, confidence: 1),
            nextChord: nil,
            barIndex: 4,
            startMicroseconds: 0,
            musicalStateConfiguration: try MusicalStateConfiguration(
                tempoBPM: 120,
                beatsPerBar: 4
            ),
            memory: HumanPhraseMemory(
                notes: [
                    HumanPhraseNote(note: 60, velocity: 88, positionBeats: 0),
                    HumanPhraseNote(note: 62, velocity: 84, positionBeats: 0.5),
                    HumanPhraseNote(note: 64, velocity: 82, positionBeats: 1),
                    HumanPhraseNote(note: 67, velocity: 78, positionBeats: 1.5)
                ]
            ),
            previousNotes: [],
            humanAverageVelocity: 82
        )

        let noteOns = result.phrase.messages.filter { $0.kind == .noteOn }
        let subject = noteOns.filter { $0.note >= 55 }
        let counter = noteOns.filter { $0.note < 55 }
        XCTAssertEqual(subject.map(\.note), [67, 69, 71, 74])
        XCTAssertEqual(subject.map(\.offsetMicroseconds), [250_000, 500_000, 750_000, 1_000_000])
        XCTAssertEqual(counter.map(\.note), [48, 44])
        XCTAssertTrue(noteOns.allSatisfy { $0.channel == 2 })
        XCTAssertGreaterThan(result.expression.activity, 0.7)
        XCTAssertGreaterThan(result.expression.memory, 0.8)
    }

    func testFugueGeneratorCanInvertTheSubject() throws {
        let result = FuguePhraseGenerator(outputChannel: 2).generate(
            decision: BassDecision(
                activity: .normal,
                relationship: .contrast,
                motion: .approach,
                fill: false,
                confidence: 1
            ),
            chord: ChordCandidate(rootPitchClass: 0, quality: .minor, confidence: 1),
            nextChord: nil,
            barIndex: 5,
            startMicroseconds: 0,
            musicalStateConfiguration: try MusicalStateConfiguration(),
            memory: HumanPhraseMemory(
                notes: [
                    HumanPhraseNote(note: 60, velocity: 80, positionBeats: 0),
                    HumanPhraseNote(note: 62, velocity: 80, positionBeats: 0.5),
                    HumanPhraseNote(note: 65, velocity: 80, positionBeats: 1)
                ]
            ),
            previousNotes: [],
            humanAverageVelocity: nil
        )

        XCTAssertEqual(
            result.phrase.messages
                .filter { $0.kind == .noteOn && $0.note >= 55 }
                .map(\.note),
            [67, 65, 62]
        )
    }

    func testFugueReturnRestatesTheCompleteSubjectEvenAfterRestDecision() throws {
        let result = FuguePhraseGenerator(outputChannel: 2).generate(
            decision: BassDecision(
                activity: .rest,
                relationship: .contrast,
                motion: .leap,
                fill: true,
                confidence: 1
            ),
            chord: ChordCandidate(rootPitchClass: 0, quality: .major, confidence: 1),
            nextChord: ChordCandidate(rootPitchClass: 7, quality: .major, confidence: 1),
            barIndex: 11,
            startMicroseconds: 0,
            musicalStateConfiguration: try MusicalStateConfiguration(),
            memory: HumanPhraseMemory(
                notes: [
                    HumanPhraseNote(note: 60, velocity: 88, positionBeats: 0),
                    HumanPhraseNote(note: 62, velocity: 84, positionBeats: 0.5),
                    HumanPhraseNote(note: 65, velocity: 82, positionBeats: 1),
                    HumanPhraseNote(note: 64, velocity: 78, positionBeats: 1.5)
                ],
                ageBars: 9
            ),
            previousNotes: [],
            humanAverageVelocity: 82,
            stage: .returnOfSubject
        )

        let noteOns = result.phrase.messages.filter { $0.kind == .noteOn }
        XCTAssertEqual(noteOns.map(\.note), [60, 62, 65, 64])
        XCTAssertEqual(noteOns.map(\.offsetMicroseconds), [125_000, 375_000, 625_000, 875_000])
        XCTAssertEqual(result.expression.memory, 0.87, accuracy: 0.000_001)
    }

    func testFugueEngineAnswersFinalizedMotifOnNextBeatWithoutFixedDevelopment() throws {
        var engine = LocalBassistEngine(
            configuration: try LocalBassistConfiguration(
                musicalState: MusicalStateConfiguration(tempoBPM: 120, beatsPerBar: 4),
                introBars: 0,
                outputChannel: 2,
                style: .fugue,
                mode: .ionian
            )
        )
        let firstSubjectEvents: [(UInt64, MIDIEvent.Kind, UInt8, UInt8)] = [
            (0, .noteOn, 60, 84),
            (120_000, .noteOff, 60, 0),
            (250_000, .noteOn, 62, 84),
            (370_000, .noteOff, 62, 0),
            (500_000, .noteOn, 64, 84),
            (620_000, .noteOff, 64, 0)
        ]
        for (offset, kind, note, velocity) in firstSubjectEvents {
            _ = try engine.ingest(SessionMIDIEvent(
                offsetMicroseconds: offset,
                hostTime: offset,
                channel: 1,
                kind: kind,
                note: note,
                velocity: velocity
            ))
        }
        let firstUpdate = try engine.advance(through: 2_000_000)
        let secondSubjectEvents: [(UInt64, MIDIEvent.Kind, UInt8, UInt8)] = [
            (2_100_000, .noteOn, 65, 82),
            (2_220_000, .noteOff, 65, 0),
            (2_350_000, .noteOn, 68, 82),
            (2_470_000, .noteOff, 68, 0),
            (2_600_000, .noteOn, 72, 82),
            (2_720_000, .noteOff, 72, 0)
        ]
        for (offset, kind, note, velocity) in secondSubjectEvents {
            _ = try engine.ingest(SessionMIDIEvent(
                offsetMicroseconds: offset,
                hostTime: offset,
                channel: 1,
                kind: kind,
                note: note,
                velocity: velocity
            ))
        }
        let secondUpdate = try engine.advance(through: 4_000_000)

        let firstPlan = try XCTUnwrap(firstUpdate.plans.first)
        let secondPlan = try XCTUnwrap(secondUpdate.plans.first)
        let firstNoteOns = firstPlan.phrase.messages.filter { $0.kind == .noteOn }
        let firstNoteOffs = firstPlan.phrase.messages.filter { $0.kind == .noteOff }

        XCTAssertEqual(firstUpdate.plans.count, 1)
        XCTAssertEqual(firstPlan.developmentStage, nil)
        XCTAssertEqual(firstPlan.tonalCenterPitchClass, 0)
        XCTAssertEqual(firstPlan.phrase.startMicroseconds, 1_000_000)
        XCTAssertEqual(firstNoteOns.map(\.note), [60, 62, 64])
        XCTAssertEqual(firstNoteOns.count, firstNoteOffs.count)
        XCTAssertLessThan(firstNoteOffs[0].offsetMicroseconds, firstNoteOns[1].offsetMicroseconds)
        XCTAssertLessThan(firstNoteOffs[1].offsetMicroseconds, firstNoteOns[2].offsetMicroseconds)
        XCTAssertEqual(secondUpdate.plans.count, 1)
        XCTAssertNil(secondPlan.developmentStage)
        XCTAssertNotEqual(secondPlan.phrase.startMicroseconds % 2_000_000, 0)
    }

    func testPhraseGeneratorProducesSilenceForRestDecision() throws {
        let phrase = BassPhraseGenerator(outputChannel: 3).generate(
            decision: BassDecision(
                activity: .rest,
                relationship: .hold,
                motion: .root,
                fill: false,
                confidence: 1
            ),
            chord: nil,
            barIndex: 4,
            startMicroseconds: 8_000_000,
            musicalStateConfiguration: try MusicalStateConfiguration()
        )

        XCTAssertTrue(phrase.messages.isEmpty)
    }

    func testEngineWaitsFourCompleteBarsBeforePlanningBarFive() throws {
        var engine = try makeEngine(introBars: 4)
        var plans: [BassBarPlan] = []

        for bar in 0..<4 {
            let start = UInt64(bar) * 2_000_000
            plans += try ingestTriad(at: start, into: &engine)
            plans += try engine.advance(through: start + 2_000_000).plans
            if bar < 3 {
                XCTAssertTrue(plans.isEmpty)
            }
        }

        XCTAssertEqual(plans.count, 1)
        XCTAssertEqual(plans[0].sourceBarIndex, 3)
        XCTAssertEqual(plans[0].targetBarIndex, 4)
        XCTAssertEqual(plans[0].phrase.startMicroseconds, 8_000_000)
        XCTAssertFalse(plans[0].phrase.messages.isEmpty)
    }

    func testEnginePrefetchesRemoteDecisionOneBarBeforeFirstBassPlan() throws {
        let provider = ImmediatePreparedProvider()
        var engine = LocalBassistEngine(
            configuration: try LocalBassistConfiguration(
                musicalState: MusicalStateConfiguration(
                    tempoBPM: 120,
                    beatsPerBar: 4
                ),
                introBars: 4,
                outputChannel: 3
            ),
            decisionProvider: provider
        )
        var plans: [BassBarPlan] = []

        for bar in 0..<4 {
            let start = UInt64(bar) * 2_000_000
            plans += try ingestTriad(at: start, into: &engine)
            plans += try engine.advance(through: start + 2_000_000).plans
        }

        XCTAssertEqual(provider.preparedTargets, [4, 5])
        XCTAssertEqual(provider.resolvedTargets, [4])
        XCTAssertEqual(plans.count, 1)
        XCTAssertEqual(plans[0].decisionSource, .jev)
        XCTAssertEqual(plans[0].decision.activity, .busy)
    }

    func testEngineUsesPlannedHarmonyAndApproachesTheNextChord() throws {
        let progression = try ChordProgressionParser.parse("Dm7,G7,Cmaj7,Cmaj7")
        var engine = LocalBassistEngine(
            configuration: try LocalBassistConfiguration(
                musicalState: MusicalStateConfiguration(
                    tempoBPM: 120,
                    beatsPerBar: 4
                ),
                introBars: 4,
                outputChannel: 3,
                progression: progression
            )
        )
        var plans: [BassBarPlan] = []
        for bar in 1...4 {
            plans += try engine.advance(through: UInt64(bar) * 2_000_000).plans
        }

        let firstPlan = try XCTUnwrap(plans.first)
        XCTAssertEqual(firstPlan.targetBarIndex, 4)
        XCTAssertEqual(firstPlan.chord, progression[0])
        XCTAssertFalse(firstPlan.usedHeldChord)
        XCTAssertEqual(
            firstPlan.phrase.messages.filter { $0.kind == .noteOn }.last?.note,
            42
        )
    }

    func testEngineRoutesAmbientStyleToSustainedVoicing() throws {
        let progression = try ChordProgressionParser.parse("Cmaj7")
        var engine = LocalBassistEngine(
            configuration: try LocalBassistConfiguration(
                musicalState: MusicalStateConfiguration(
                    tempoBPM: 120,
                    beatsPerBar: 4
                ),
                introBars: 0,
                outputChannel: 2,
                progression: progression,
                style: .ambient
            )
        )

        let plan = try XCTUnwrap(
            engine.advance(through: 2_000_000).plans.first
        )
        let noteOns = plan.phrase.messages.filter { $0.kind == .noteOn }
        let noteOffs = plan.phrase.messages.filter { $0.kind == .noteOff }

        XCTAssertEqual(plan.targetBarIndex, 1)
        XCTAssertEqual(noteOns.map(\.note), [52, 55])
        XCTAssertEqual(noteOns.map(\.offsetMicroseconds), [2_000_000, 2_000_000])
        XCTAssertEqual(noteOffs.map(\.offsetMicroseconds), [3_950_000, 3_950_000])
        XCTAssertTrue(plan.phrase.messages.allSatisfy { $0.channel == 2 })
    }

    func testEngineRemembersHumanMotifForTwoSilentBars() throws {
        let progression = try ChordProgressionParser.parse("Cmaj7")
        var engine = LocalBassistEngine(
            configuration: try LocalBassistConfiguration(
                musicalState: MusicalStateConfiguration(tempoBPM: 120, beatsPerBar: 4),
                introBars: 0,
                outputChannel: 2,
                progression: progression,
                style: .memory
            )
        )
        let motifEvents: [(UInt64, MIDIEvent.Kind, UInt8, UInt8)] = [
            (0, .noteOn, 60, 84),
            (80_000, .noteOff, 60, 0),
            (125_000, .noteOn, 64, 84),
            (205_000, .noteOff, 64, 0),
            (250_000, .noteOn, 67, 84),
            (330_000, .noteOff, 67, 0)
        ]
        for (offset, kind, note, velocity) in motifEvents {
            _ = try engine.ingest(
                SessionMIDIEvent(
                    offsetMicroseconds: offset,
                    hostTime: offset,
                    channel: 1,
                    kind: kind,
                    note: note,
                    velocity: velocity
                )
            )
        }

        let fresh = try XCTUnwrap(engine.advance(through: 2_000_000).plans.first)
        let firstEcho = try XCTUnwrap(engine.advance(through: 4_000_000).plans.first)
        let secondEcho = try XCTUnwrap(engine.advance(through: 6_000_000).plans.first)
        let forgotten = try XCTUnwrap(engine.advance(through: 8_000_000).plans.first)

        XCTAssertEqual(
            fresh.phrase.messages.filter { $0.kind == .noteOn }.map(\.note),
            [60, 64, 67]
        )
        XCTAssertFalse(firstEcho.phrase.messages.isEmpty)
        XCTAssertFalse(secondEcho.phrase.messages.isEmpty)
        XCTAssertGreaterThan(fresh.expression.memory, firstEcho.expression.memory)
        XCTAssertGreaterThan(firstEcho.expression.memory, secondEcho.expression.memory)
        XCTAssertTrue(forgotten.phrase.messages.isEmpty)
    }

    func testEngineHoldsChordForTwoSilentBarsThenFallsBackToRest() throws {
        var engine = try makeEngine(introBars: 0, maximumHeldChordBars: 2)
        _ = try ingestTriad(at: 0, into: &engine)

        let known = try XCTUnwrap(engine.advance(through: 2_000_000).plans.first)
        let heldOnce = try XCTUnwrap(engine.advance(through: 4_000_000).plans.first)
        let heldTwice = try XCTUnwrap(engine.advance(through: 6_000_000).plans.first)
        let expired = try XCTUnwrap(engine.advance(through: 8_000_000).plans.first)

        XCTAssertFalse(known.usedHeldChord)
        XCTAssertTrue(heldOnce.usedHeldChord)
        XCTAssertTrue(heldTwice.usedHeldChord)
        XCTAssertFalse(heldOnce.phrase.messages.isEmpty)
        XCTAssertFalse(heldTwice.phrase.messages.isEmpty)
        XCTAssertNil(expired.chord)
        XCTAssertEqual(expired.decision.activity, .rest)
        XCTAssertTrue(expired.phrase.messages.isEmpty)
    }

    private func makeEngine(
        introBars: Int,
        maximumHeldChordBars: Int = 2
    ) throws -> LocalBassistEngine {
        LocalBassistEngine(
            configuration: try LocalBassistConfiguration(
                musicalState: MusicalStateConfiguration(
                    tempoBPM: 120,
                    beatsPerBar: 4
                ),
                introBars: introBars,
                maximumHeldChordBars: maximumHeldChordBars,
                outputChannel: 3
            )
        )
    }

    private func ingestTriad(
        at start: UInt64,
        into engine: inout LocalBassistEngine
    ) throws -> [BassBarPlan] {
        var plans: [BassBarPlan] = []
        for (offset, note) in [(UInt64(0), UInt8(60)), (100_000, 63), (200_000, 67)] {
            plans += try engine.ingest(
                SessionMIDIEvent(
                    offsetMicroseconds: start + offset,
                    hostTime: start + offset,
                    channel: 1,
                    kind: .noteOn,
                    note: note,
                    velocity: 90
                )
            ).plans
        }
        for (offset, note) in [(UInt64(300_000), UInt8(60)), (310_000, 63), (320_000, 67)] {
            plans += try engine.ingest(
                SessionMIDIEvent(
                    offsetMicroseconds: start + offset,
                    hostTime: start + offset,
                    channel: 1,
                    kind: .noteOff,
                    note: note,
                    velocity: 0
                )
            ).plans
        }
        return plans
    }

    private func state(noteCount: Int, density: Double) -> MusicalState {
        MusicalState(
            noteOnCount: noteCount,
            noteDensityPerBeat: density,
            averageVelocity: nil,
            averageNote: nil,
            lowestNote: nil,
            highestNote: nil,
            heldNotes: [],
            pulse: nil,
            chordCandidates: []
        )
    }
}

private final class ImmediatePreparedProvider: BassDecisionProvider, @unchecked Sendable {
    private let lock = NSLock()
    private var prepared: Set<Int> = []
    private var recordedPreparedTargets: [Int] = []
    private var recordedResolvedTargets: [Int] = []

    var preparedTargets: [Int] {
        lock.lock()
        defer { lock.unlock() }
        return recordedPreparedTargets
    }

    var resolvedTargets: [Int] {
        lock.lock()
        defer { lock.unlock() }
        return recordedResolvedTargets
    }

    func prepare(_ input: BassDecisionInput) {
        lock.lock()
        prepared.insert(input.targetBarIndex)
        recordedPreparedTargets.append(input.targetBarIndex)
        lock.unlock()
    }

    func decision(for input: BassDecisionInput) -> BassDecision {
        RuleBasedBassDecisionProvider().decision(for: input)
    }

    func resolution(for input: BassDecisionInput) -> BassDecisionResolution {
        lock.lock()
        recordedResolvedTargets.append(input.targetBarIndex)
        let wasPrepared = prepared.remove(input.targetBarIndex) != nil
        lock.unlock()
        guard wasPrepared else {
            return BassDecisionResolution(
                decision: decision(for: input),
                source: .fallback
            )
        }
        return BassDecisionResolution(
            decision: BassDecision(
                activity: .busy,
                relationship: .contrast,
                motion: .approach,
                fill: true,
                confidence: 0.9
            ),
            source: .jev
        )
    }
}

private struct ConstantDecisionProvider: BassDecisionProvider {
    let decisionValue: BassDecision

    init(decision: BassDecision) {
        decisionValue = decision
    }

    func decision(for input: BassDecisionInput) -> BassDecision {
        decisionValue
    }
}
