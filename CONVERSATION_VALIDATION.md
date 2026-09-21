# Reciprocal ensemble validation

This record separates reproducible software checks from listening and hardware checks. Passing CI establishes deterministic behavior and safety properties; it does not establish that the session feels musical on a JD-Xi.

## Automated coverage

Run on a Mac with the full Xcode toolchain selected:

```bash
swift build
swift test
swift test --sanitize=address
```

CI also extracts the browser program and runs `node --check` before the Swift tests.

| Scenario group | Automated evidence |
| --- | --- |
| Response matching | `ConversationObservationTests` compares contour/rhythm evidence, distinguishes preceding responses with the same ending, and accepts octave-transposed imitation. |
| Heard history | `ConversationEngineTests.testConversationMemoryAdvancesOnlyAfterElapsedNoteOn` plus the live/evaluator onset queues keep future scheduled notes out of conversation memory. |
| Shared material | `testSharedThemeIsSentToDecisionProviderAfterHumanTakesUpResponse` verifies that a matching human reply can revise the shared theme. |
| Silence and agency | `testSilenceProducesOneAutonomousProposalThenWaits` prevents a machine-only continuation loop. |
| Remote timing | Deferred-provider tests cover a ready decision, same-onset deadline fallback, and a human attack that does not blindly erase an in-flight phrase decision. |
| Continuous playing | `PhraseMemoryTests.testContinuousPlayingEmitsBoundedObservationWithoutSilence` bounds observation without discarding captured events. |
| Scheduler safety | `RollingMIDISchedulerTests` cover note pairing, overlapping retriggers, committed releases, cancellation, and deterministic ordering. |
| Trace compatibility | `SessionEvaluationTests` check deterministic trace v3 output, scheduled events, and backward decoding of v1/v2 with absent fields left empty. |
| Jev boundary | `JevConversationDecisionProviderTests` verify bounded IDs, serialized intent/turn/theme context, expiry, typed validation, and secret-free traces. |
| Browser transport | CI syntax-checks the browser; runtime code uses session/event/note/response IDs, source-note correspondence, bounded collections, monotonic offsets, reconnection watermarks, and coalesced SSE snapshots. |

## Three-minute listening protocol

Use the integrated fugue command from README with the same patch, mode, BPM, and channel volumes for both `--brain rules` and `--brain jev`.

1. Play a clear three-to-six-note idea and leave a breath.
2. Answer one part of Jev's response by transposing it; verify that the next reply preserves a feature of the exchanged version rather than only the origin.
3. Repeat your own earlier phrase; verify that this is not treated as high-confidence imitation of an unrelated Jev line.
4. Add one short note during a Jev response; verify that the already audible line remains coherent and the whole unsent response is not erased immediately.
5. Start a sustained, denser new phrase; verify that Jev yields at the next phrase boundary rather than adding another independent voice.
6. After Jev finishes, remain silent; verify one short proposal followed by silence.
7. Repeat with `--brain jev`; compare candidate choice separately from onset timing. A late request must fall back locally without moving the onset.

Rate recognizable pickup, influence on the next response, overlap behavior, room to lead/stop, and whether the visual field shows the same exchange from 1–5. Add one sentence identifying the exact human change that Jev appeared to pick up. Two concrete reciprocal exchanges are required before calling the experience complete.

## Hardware and endurance checks

These remain manual and must not be inferred from CI:

- JD-Xi/UR22mkII routing, independent volume, patch gain, and safe stop;
- audible onset against the browser trajectory, including background/foreground and reconnect;
- repeated same-pitch attacks without stolen releases;
- a 30-minute session with no stuck notes, growing latency, unbounded browser state, or loss of control;
- a short screen-and-audio capture for rules/Jev comparison under the same sound and volume.

Record macOS, Swift/Xcode, interface, synth patch, BPM, mode, channels, and date with the result. Until these checks are recorded, the code is integrated but the live experience is not declared validated.
