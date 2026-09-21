# Product specification

## Purpose

Build a macOS-native musical session partner that listens to a live MIDI player and responds as a bassist. The defining quality is not autonomous composition. It is whether the human player feels that another performer is listening and changing attitude in response.

## Research question

Can a low-latency typed decision model make an algorithmic accompanist feel more socially and musically responsive than a fixed rule policy, while a local engine preserves timing?

## Core interaction

The intended first complete loop is:

1. A player performs on a JD-Xi or another MIDI keyboard.
2. The Mac derives a compact `MusicalState` from recent beats and bars.
3. A `BassDecisionProvider` selects behavior at phrase-safe boundaries.
4. A local phrase generator turns that behavior into concrete notes.
5. A local scheduler sends the notes to a MIDI output without waiting for the network.
6. Requests, decisions, confidence values, generated notes, and latency are logged for replay and comparison.
7. An optional loopback browser companion starts/stops the session and visualizes the authoritative Swift bar clock without scheduling MIDI itself.
8. The same browser can mix separate synth-part channels and render human and companion MIDI events as one synchronized visual field.

## Musical behavior contract

Jev is a decision maker, not a note generator. Its future typed output should remain small and inspectable, initially along these axes:

- `activity`: `rest | sparse | normal | busy`
- `relationship`: `follow | contrast | hold`
- `motion`: `root | step | approach | leap`
- `fill`: Boolean
- confidence or probability for each decision

The exact schema will be fixed only after a rule-based bassist can already complete a live session.

The local renderer may interpret those axes as a bass pocket, an ambient ensemble response, a transformed memory of the human's recent motif, or an eight-bar imitative development. Memory responses preserve recognizable contour and relative timing, enter only after a deliberate breath, and decay to silence when the player stops supplying new material. Fugue responses use one requested mode rather than a fixed chord progression, infer and lock the subject's tonal center, and preserve one qualifying subject for a complete answer-to-return cycle. Later human material waits as a candidate for the next cycle. Jev still never chooses individual notes.

## Architecture

```text
CoreMIDI input
    -> MIDI event decoder
    -> performance window
    -> MusicalState
    -> BassDecisionProvider
       |- RuleBasedDecisionProvider
       `- JevDecisionProvider
    -> PhraseGenerator
    -> local MIDI scheduler
    -> CoreMIDI output
```

Supporting paths record raw input, derived state, decisions, generated output, and latency as replayable session data.

## Non-negotiable constraints

- Network latency never directly controls note onset timing.
- The MIDI callback does no network, file, UI, or musical-analysis work.
- The complete session engine works without Jev.
- External AI calls sit behind a replaceable protocol.
- Inputs and decisions are serializable and replayable.
- Musical decisions occur at beat, bar, or phrase boundaries rather than once per note.
- Rule and Jev modes can consume the same recorded performance.
- A failure or timeout produces a local fallback decision and never hangs playback.
- Browser rendering and transport controls remain outside the note scheduling path and never receive an API key.
- Browser mix commands become bounded MIDI CC messages on the session queue; browser visuals consume copied event metadata, never audio callbacks.
- Phrase memory remains local, deterministic, and bounded; the browser receives only copied note events and normalized expression values.

## MVP success criteria

A useful MVP must demonstrate all of the following:

- after a four-bar human introduction, bass can enter on a musical boundary;
- denser human playing tends to produce sparser bass behavior;
- human silence allows a modest increase in bass activity;
- repetition in the human phrase can trigger a visible or audible response;
- `rules` and `jev` modes can be switched without changing the rest of the pipeline;
- p50, p95, and p99 decision latency can be reported;
- a session can be replayed deterministically enough to compare policies.

The primary human evaluation is a short rating of “this felt like another player was listening,” supported by logs rather than replaced by them.

## Milestones

### M1: MIDI input foundation

- list available CoreMIDI sources;
- select a source by name or monitor all sources;
- decode Note On and Note Off, including velocity-zero Note On and running status;
- print receipt timestamp, host timestamp, note number, note name, velocity, and channel;
- keep CoreMIDI isolated from the pure decoder;
- pass unit tests and macOS CI.

### M2: Capture and musical state

- write timestamped session fixtures;
- replay fixtures without hardware;
- estimate note density, velocity, register, held notes, pulse, and chord candidates;
- expose stable beat/bar snapshots.

### M3: Local bassist

- generate conservative bass phrases from chord and activity state;
- schedule MIDI locally with no network dependency;
- support silence and safe fallback behavior.

### M4: Jev decision provider

- finalize the typed Jev schema against the working rule policy;
- log full request/response and latency metadata without secrets;
- use deadlines, cancellation, and deterministic local fallback;
- expose `--brain rules|jev`.

### M5: Musicality and evaluation harness

- provide a browser-based shared bar/beat display driven by the Swift session clock;
- accept a known looping chord progression so the target and following harmony are available before generation;
- use following harmony for intentional approaches and avoid chromatic fills when no resolution target is known;
- replay identical fixtures through both providers;
- report timing and decision stability;
- conduct live A/B sessions focused on perceived responsiveness.

### M6–M11: Ambient, mix, memory, and motif development ensemble

- render sparse sustained ambient voicings from the same bounded decisions;
- expose independent human and companion channel volume controls;
- preserve a recent human motif and return a delayed transformed trace for at most two silent bars;
- derive shared memory, tension, activity, and resonance values from each local plan;
- drive one persistent membrane visual from those values and the authoritative MIDI timeline.
- render a recent human subject as a deterministic dominant answer with optional two-voice counterpoint;
- amplify membrane displacement and mirror imitative answers so live musical changes are visually legible.
- preserve subject identity across an eight-bar development arc ending in an explicit return;
- queue new human material for the next cycle rather than replacing the active subject mid-development.
- derive fugue harmony from one selected mode and a subject-inferred tonal center instead of a fixed progression;
- make note attacks produce broad membrane displacement, full-field flash, and expanding shockwaves.

### M12 P0: deterministic conversation evaluation

- preserve the existing analyzer-only `replay` command;
- run a captured input fixture through the complete local ensemble engine without opening a MIDI output;
- save the input, exact configuration, snapshots, bounded rule decisions, generated plans, and scheduled MIDI messages in one versioned trace;
- make identical fixture/configuration evaluations byte-stable enough for direct implementation comparisons;
- keep this milestone observational: it records the current fixed eight-stage fugue but does not describe that behavior as conversational;
- use the trace foundation for duration-aware phrase memory, short-horizon scheduling, and a later context-driven response engine.

### M12 P1: duration-aware motif memory

- pair Note On/Off events on normalized session time, including overlapping retriggers of the same channel/note;
- mark releases inferred at session end instead of presenting them as observed duration;
- finalize phrases from tempo-relative adaptive silence and recent onset spacing, not bar boundaries;
- preserve cross-bar phrasing, relative onset, duration, rests, velocity accents, and characteristic intervals in an immutable bounded motif;
- group simultaneous attacks and reject low-confidence chord extraction as a multi-note melody subject;
- add performed notes, phrase observations, diagnostics, and motifs to evaluation trace v2 while continuing to decode trace v1;
- project a finalized motif into the legacy generator without yet replacing the fixed eight-stage fugue or whole-bar scheduler.

### M12 P2: rolling MIDI commitment

- keep complete generated plans in Core while committing only the next 50 ms of MIDI events to CoreMIDI;
- assign stable event, revision, and paired-note identifiers before commitment;
- on human re-entry, remove unsent Note On events and their paired Note Off events while retaining releases for attacks already handed to CoreMIDI;
- keep overlapping attacks of the same channel/note independent so one cancellation cannot steal another attack's release;
- publish companion visual events only after the corresponding MIDI event crosses the commitment horizon;
- clear the internal queue on explicit stop, then use the existing destination flush and channel silence as the terminal safety action.

### M12 P3: local one-voice conversation

- route finalized `fugue` motifs into a conversation engine instead of the fixed eight-stage live path;
- generate a bounded candidate set: silence, close echo, final-note variation, and held tone;
- start the selected response on the next shared beat rather than waiting for a bar boundary;
- preserve relative onset, duration, rests, and velocity contour unless a candidate explicitly changes that feature;
- project only generated out-of-mode pitches to the nearest conservative modal tone while retaining the observed human motif unchanged;
- render one companion voice with paired releases and no overlapping machine attacks;
- retain the legacy fugue generator as directly testable comparison code, not a hidden live fallback.

### M12 P4: contextual development and return

- retain the first accepted motif as an immutable origin while later human motifs shape the response context;
- choose sequence, inversion, fragmentation, or augmentation from observed density, contour similarity, duration, and register movement rather than a fixed stage order;
- accumulate a bounded divergence measure and return to the unchanged origin when transformations have moved sufficiently far away;
- attach origin, source motif, parent response, generation, and relationship lineage to every conversation plan;
- quantize from the time a completed motif actually becomes available, never from an earlier inferred boundary that would schedule attacks in the past;
- keep generated notes modal while never rewriting the captured human motif.

## Out of scope for the early MVP

- audio transcription;
- free-form text generation during performance;
- a SwiftUI interface;
- per-note cloud inference;
- automatic model training;
- multi-agent band simulation.
