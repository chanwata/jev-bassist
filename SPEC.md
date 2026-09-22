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

The local renderer may interpret those axes as a bass pocket, an ambient ensemble response, or a transformed memory of the human's motif. Memory responses preserve recognizable contour and relative timing, enter only after a deliberate breath, and decay to silence when the player stops supplying new material. Fugue responses use one requested mode rather than a fixed chord progression, infer and lock the origin's tonal center, and choose transformations from the changing performance context. Jev still never chooses individual notes.

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

### M12 P5: phrase-boundary Jev selection

- ask Jev only to choose an ID from the bounded, locally rendered response candidates after a motif is finalized;
- keep candidate generation, pitch projection, articulation, scheduling, and MIDI safety local;
- tag each request with a monotonic revision and reject any completion after that revision expires or is superseded;
- poll prepared results without blocking the live queue and reserve a future shared beat while remote work is pending;
- use the local candidate at the musical deadline for timeout, low confidence, invalid output, transport failure, or an unknown candidate ID;
- emit a complete secret-free decision trace separate from MIDI timing diagnostics.

### M12 P6: committed lineage visual

- associate each submitted response revision with its origin motif, source response, parent, generation, and transformation;
- publish lineage only when the rolling scheduler actually commits the corresponding MIDI message;
- render stable origin-seeded forms whose geometry changes materially for sequence, inversion, fragmentation, augmentation, and return;
- make original return visibly converge and flash across the field while preserving motion-reduction behavior;
- keep clock and controls nearly invisible until hover or focus so the performance remains the primary surface.

### M12 P7: musical phrase shaping and shared trajectory field

- place generated pitches into the companion register as one phrase, preserving contour across octave boundaries;
- express sequence and inversion in modal scale degrees before register placement;
- retain the opening, salient interior events, and ending when a long motif must be bounded;
- score the rendered notes for recognition, contour, modal fit, voice leading, cadence, continuity, and space;
- shape velocity and articulation as a phrase while preserving relative rhythm and characteristic accents;
- advance response continuity and divergence only after a scheduled Note On's onset time has elapsed;
- include bounded pitches, intervals, timing, landing, and continuity features in Jev candidate descriptions while keeping note generation local;
- carry origin, current source, and response gestures with lineage and reveal only the committed response prefix in the browser;
- replace relationship polygons with layered curve trajectories whose spacing, direction, gaps, scale, and convergence reflect the audible transformation;
- allow an explicit browser audio-input selection for optional local energy and brightness analysis without treating the default microphone as the session mix.

### M12 P8: reciprocal ensemble state

- compare each completed human phrase with the audible prefix of the preceding companion response, the preceding human phrase, the shared theme, and the immutable origin;
- classify bounded evidence for imitation, rhythmic reply, continuation, self-repetition, a new proposal, or ambiguity without treating one shared ending as proof;
- keep an immutable origin and a separately revisable shared theme, requiring repeated or sufficiently strong evidence before replacing the theme;
- choose an explicit intent—acknowledge, continue, question, support, settle, or wait—before selecting a locally safe response;
- permit at most one short autonomous continuation after a reply, then wait instead of allowing a machine-only chain;
- reserve the next fine straight or swung response opportunity with a bounded scheduling lead and derive the Jev deadline from it; a timeout uses the local candidate at the same onset;
- preserve already elapsed response notes when a later phrase replaces an unsent suffix, including paired releases already handed to CoreMIDI;
- send Jev bounded conversation state and candidate IDs while retaining pitch, rhythm, mode, register, timing, and MIDI safety locally;
- write scheduler events and cancellations to evaluation trace v3 while continuing to decode v1 and v2 without inventing absent history;
- map browser events from Swift session offsets to `performance.now()`, keep stable note/source IDs, coalesce slow SSE clients, and draw recorded note correspondence rather than array-position links.

### M13: shared rhythm-box ensemble

- add an opt-in deterministic rhythm-box layer on a dedicated drum channel, using kick, rim click, closed hi-hat, and sparse hand percussion without copying a recorded pattern;
- put the rhythm box on the authoritative Swift session clock from the first intro bar so it acts as the audible count-in;
- subtract offbeats, hand percussion, and keyboard punctuation as measured human density rises;
- generate only short, one-note modal keyboard punctuation on a separate part after a stable tonal center is available;
- align fugue note shapes to the adjustable swing while allowing entrances on its finer subdivisions, keeping all scheduling local;
- keep human, keyboard, companion, and drum channels distinct and expose independent bounded CC7 levels for all four parts;
- expose swing and groove intensity in the loopback browser while applying changes only to future scheduled material;
- publish rhythm and keyboard MIDI events through the existing committed visual-event path without moving MIDI scheduling into the browser;
- leave bank and program selection on the instrument, avoiding device-specific patch mutation;
- preserve identical behavior when the groove is off, including existing CLI defaults and deterministic conversation tests.

### M14: shared engraved performance surface

- replace the membrane, per-note glow, left/right performer split, and decorative correspondence lines with one large shared surface;
- derive human and companion contours from actual pitch, onset, duration, and rest geometry in one common coordinate system;
- identify every sounded companion attack by its explicit response-note index so packet loss, cancellation, or reconnection cannot reveal the wrong prefix;
- restore retained phrase geometry after reconnection without replaying old transient attacks, while keeping visual history bounded to 256 events and eight phrase forms;
- make kick compress the surface, rim click shear it, hi-hat incise it briefly, and keyboard punctuation create only local interference;
- use optional local audio energy and spectral brightness for line texture and decay, without claiming pitch, reverb, or lineage inference;
- expire phrase memory in tempo-relative beats, keep percussion transients short in milliseconds, and preserve existing cancellation semantics;
- expose a browser-local -120...+120 ms visual timing adjustment for instrument and monitoring latency;
- honor reduced-motion preferences while preserving the recognizable phrase relationship;
- provide a deterministic browser-only visual demo and run it in CI with mocked canvas and clock state;
- keep the Start action visible while ready and remove performance controls from the foreground after the session begins.

### M15: kinetic score and low-latency reply

- replace the soft layered plate aesthetic with a restrained black, white, cyan, and signal-red kinetic score built from precision traces, correspondence vectors, scan pulses, and a beat-driven perspective grid;
- make spatial motion follow committed pitch/time lineage, shared clock phase, drum role, keyboard pitch, and optional local audio energy rather than an unrelated decorative simulation;
- keep human and companion identity distinct while drawing both in one coordinate system and preserving exact sounded-prefix, cancellation, reconnect, and reduced-motion behavior;
- shorten adaptive phrase-release detection from 0.5–1.5 beats to 0.4–1.25 beats without splitting an established phrase across an ordinary articulation gap;
- reserve only 60 ms of response scheduling lead and use quarter-beat or fine swung entry opportunities instead of waiting for a full eighth-note grid location;
- retain local deterministic fallback at the reserved onset when Jev misses the musical deadline, with decision provenance visible in the terminal and browser state;
- add deterministic tests for the tightened phrase boundary, straight response grid, swung response grid, and browser render loop.

### M16: single-phase ensemble grid

- treat the Swift session clock as the only rhythmic origin for drums, keyboard punctuation, and every companion Note On;
- convert candidate-relative onsets to absolute session beats before applying swing, then quantize exactly once;
- never restart swing phase at a companion response boundary, including an entrance on a swung or fine subdivision;
- use full shared-grid strength for all automatic parts and reserve expressive microtiming for a future bounded post-grid layer;
- preserve candidate timing summaries after grid placement so Jev selects among the same rhythms that local rendering will schedule;
- realign safely if a stalled live queue moves a pending response to a later opportunity;
- test absolute companion onsets rather than only relative intervals or the response start.

## Out of scope for the early MVP

- audio transcription;
- free-form text generation during performance;
- a SwiftUI interface;
- per-note cloud inference;
- automatic model training;
- multi-agent band simulation.
