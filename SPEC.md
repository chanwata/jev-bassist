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

The local renderer may interpret those axes as either a bass pocket or an ambient ensemble response. Ambient activity changes voicing width rather than attack rate; timing remains sparse and sustained, and Jev still never chooses individual notes.

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

## Out of scope for the early MVP

- audio transcription;
- free-form text generation during performance;
- a SwiftUI interface;
- per-note cloud inference;
- automatic model training;
- multi-agent band simulation.
