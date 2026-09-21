# Jev Bassist

Jev Bassist is an experimental macOS session partner that listens to a human MIDI performance and answers as a bassist.

The project deliberately separates two jobs:

- a local, deterministic engine schedules and generates MIDI notes;
- Jev can choose bounded musical behavior such as `follow`, `contrast`, `rest`, or `fill`.

Network latency must never sit in the note-timing path.

## Current milestone: motif development ensemble

The CLI completes its audible loop with either local rules or a pipelined Jev decision provider. It can:

- list CoreMIDI input sources;
- list CoreMIDI output destinations;
- connect to all sources or one source selected by name;
- decode MIDI 1.0 Note On and Note Off messages, including running status;
- print receipt time, CoreMIDI host time, MIDI note number, note name, velocity, and channel;
- capture a performance as a versioned, timestamped JSON fixture;
- replay a fixture without MIDI hardware;
- evaluate a fixture through the complete local ensemble engine and save its snapshots, bounded decisions, and scheduled MIDI messages as a deterministic trace;
- derive beat and bar snapshots containing note density, velocity, register, held notes, a pulse estimate, and ranked chord candidates;
- make a bounded rule-based bass decision once per completed bar;
- ask Jev for `activity`, `relationship`, `motion`, and `fill` in one typed request;
- prefetch Jev decisions one bar ahead and fall back to the deterministic rule policy without delaying a note;
- log the complete secret-free Jev request, response, resolved model, outcome, and latency;
- generate voice-led, dynamically restrained bass pockets and schedule them with CoreMIDI host timestamps;
- render the same bounded decisions as one quiet, sustained ambient voicing per bar;
- remember a human motif and return a delayed, locally transformed trace that fades over two silent bars;
- preserve a short human subject through an eight-bar arc of answer, transformation, climax, and return;
- mix the human and companion parts independently with MIDI Channel Volume controls;
- render both MIDI performances as one strongly reactive, beat-synchronized membrane;
- flush pending output and silence the selected channel when a live session stops.

The snapshot grid is explicitly configured with tempo and meter so the same input produces the same state and phrase. Pulse, chord, and bass decisions remain deliberately small and inspectable. The default `rules` brain is fully offline; `jev` only chooses bounded behavior and never generates or schedules individual MIDI notes. An optional browser companion reads the authoritative Swift clock and can start or stop the same live session without entering the MIDI output path.

## Requirements

- macOS 14 or later
- Xcode Command Line Tools with Swift 6
- a MIDI device; simultaneous DIN input and output requires an interface with both ports and two MIDI cables

Check the toolchain:

```bash
xcode-select --install
swift --version
```

## Wire a JD-Xi through a UR22mkII

For the live bassist loop, connect both directions:

```text
JD-Xi MIDI OUT -> UR22mkII MIDI IN   (your playing reaches the Mac)
UR22mkII MIDI OUT -> JD-Xi MIDI IN   (the generated bass reaches the JD-Xi)
```

This needs two 5-pin MIDI cables. Set the JD-Xi's `Local Switch` to **On** so the keyboard plays the selected human part directly, and keep `Soft Thru` **Off** to avoid a hardware feedback loop. The application listens to the human channel but deliberately does not echo it back; only generated bass is sent to the output. Monitor audio from the JD-Xi itself. A direct JD-Xi USB MIDI connection is another valid route if its Roland driver exposes both a CoreMIDI source and destination.

The JD-Xi uses separate MIDI channels for its four parts: Digital Synth 1 on 1, Digital Synth 2 on 2, Analog Synth on 3, and Drums on 10. The examples listen to the played Digital Synth 1 part on channel 1 and send bass to the Analog Synth part on channel 3. Select a bass sound for that part before starting. See Roland's [JD-Xi manuals and MIDI implementation](https://www.roland.com/global/support/by_product/jd-xi/owners_manuals/) for the instrument-side settings.

Open **Audio MIDI Setup** on the Mac and confirm the interface, then list both directions from the repository root:

```bash
swift run jev-bassist devices
swift run jev-bassist outputs
```

The source and destination match are case-insensitive and may be a substring. A JD-Xi connected through a MIDI interface appears under the interface name, such as `Steinberg UR22mkII`.

## Verify MIDI output first

Before running the listening loop, send three short notes to the output:

```bash
swift run jev-bassist soundcheck --destination "Steinberg UR22mkII" --channel 3
```

This schedules C2, G2, and C3, then flushes pending packets and sends All Notes Off plus All Sound Off. If there is no sound, do not start `jam` yet: verify the second cable is connected from the UR22mkII **OUT** to the JD-Xi **IN**, confirm the Analog Synth part is audible, and try the channel assigned to the intended part.

## Start a local bassist session

At 120 BPM in 4/4, listening on channel 1 and answering on channel 3:

```bash
swift run jev-bassist jam \
  --source "Steinberg UR22mkII" \
  --destination "Steinberg UR22mkII" \
  --bpm 120 \
  --input-channel 1 \
  --output-channel 3 \
  --brain rules
```

Play the first note exactly where bar 1 should begin; that Note On starts the configured bar clock. After four complete human-only bars, the first bass phrase is scheduled for bar 5. Press `Return` to stop safely. `--beats-per-bar` defaults to `4`, and `--intro-bars` defaults to `4`.

For reliable harmony, provide a looping chord progression. Its first chord begins with the first bass bar after the intro:

```bash
swift run jev-bassist jam \
  --source "Steinberg UR22mkII" \
  --destination "Steinberg UR22mkII" \
  --bpm 120 \
  --input-channel 1 \
  --output-channel 3 \
  --progression "Dm7,G7,Cmaj7,Cmaj7" \
  --brain rules
```

Common major, minor, dominant-seventh, major-seventh, minor-seventh, and diminished symbols are accepted, including sharps and flats. The current engine reduces seventh chords to their major/minor triad family, then uses the following chord as the target for restrained fills and chromatic approaches. Without `--progression`, live chord detection remains available as an experimental one-bar response mode.

The fugue style is the exception: it rejects `--progression` and requires one modal color such as `--mode dorian`. Its tonal center is inferred from the locked subject and remains stable for the complete eight-bar cycle.

The M3 rule policy is intentionally conservative:

- no usable chord means rest;
- 1.5 or more human note onsets per beat produces a sparse bass answer;
- lighter playing produces root-oriented normal or sparse phrases;
- a silent bar can use the last chord and move modestly for at most two bars;
- longer harmonic uncertainty returns to rest instead of repeating a stale chord;
- sequential melody notes are not collapsed into a fictional chord; harmony needs a three-note strike, quick arpeggiation, or held triad;
- `follow`, `contrast`, and `hold` now select different rhythmic pockets instead of producing the same metronomic pattern;
- chord tones are voice-led across bar boundaries, including B2 to C3 without an octave drop;
- bass velocity follows the human bar at a restrained level, with a stronger downbeat and softer offbeats;
- generated notes stay in MIDI 36–48 (C2–C3), with a paired Note Off for every Note On.

All phrase notes are scheduled locally. The live loop waits 8 ms for near-boundary input and applies a fixed 12 ms output safety offset; network latency is not present in the timing path.

## Use the ambient ensemble style

`--style ambient` maps the same bounded Jev decisions to slow, sustained accompaniment instead of a walking or syncopated bass line. Activity changes the width of a single pad voicing—silence, one note, two notes, or three notes—rather than increasing rhythmic attack rate. Relationship controls whether the response enters on the boundary, slightly behind it, or after leaving the downbeat open. A fill becomes an earlier release that leaves air before the next chord.

On a JD-Xi, select a soft pad or slowly evolving sound for Digital Synth 2 and send the companion to its usual MIDI channel 2. Keep your played part on channel 1:

```bash
swift run jev-bassist jam \
  --source "Steinberg UR22mkII" \
  --destination "Steinberg UR22mkII" \
  --bpm 90 \
  --input-channel 1 \
  --output-channel 2 \
  --human-volume 100 \
  --companion-volume 72 \
  --intro-bars 2 \
  --progression "Dm7,G7,Cmaj7,Cmaj7" \
  --style ambient \
  --brain jev \
  --ui
```

Ambient notes stay between MIDI 48 and 72 (C3–C5), use restrained velocity, and sustain for most of the bar. A supplied progression is strongly recommended: it gives both the local voicing engine and Jev stable current/next harmony. Start around 70–100 BPM and use a patch with a slow attack, long release, modest reverb, and no tempo-synced arpeggiator.

## Use the memory ensemble style

`--style memory` listens for the contour, relative timing, and dynamics of the notes you play in each completed bar. The following bar begins with at least half a beat of space, then returns a reduced trace of that motif. Jev still chooses only the bounded `activity`, `relationship`, `motion`, and `fill` axes; the local engine selects and schedules every note.

```bash
swift run jev-bassist jam \
  --source "Steinberg UR22mkII" \
  --destination "Steinberg UR22mkII" \
  --bpm 84 \
  --input-channel 1 \
  --output-channel 2 \
  --human-volume 100 \
  --companion-volume 68 \
  --intro-bars 2 \
  --progression "Dm7,G7,Cmaj7,Cmaj7" \
  --style memory \
  --brain jev \
  --ui
```

Activity selects one, three, or four representative notes rather than adding a generic accompaniment pattern. `root` transposes the remembered contour to the chord root, `step` compresses wide intervals, `approach` reverses the motif, and `leap` expands alternating intervals. A silent bar reuses the memory more quietly; after two silent bars it disappears. Responses remain in MIDI 48–72 and use low velocity so a slow pad, glass, or soft pluck patch can retain the human phrase's identity without covering it.

## Use the fugue ensemble style

`--style fugue` treats the first qualifying three-to-eight-note idea as a subject and keeps it intact for a complete eight-bar development cycle. Material played during that cycle becomes a candidate for the next cycle instead of erasing the active subject. The companion therefore develops one recognizable idea over time rather than replacing it every bar.

```bash
swift run jev-bassist jam \
  --source "Steinberg UR22mkII" \
  --destination "Steinberg UR22mkII" \
  --bpm 96 \
  --input-channel 1 \
  --output-channel 2 \
  --human-volume 100 \
  --companion-volume 74 \
  --intro-bars 2 \
  --style fugue \
  --mode dorian \
  --brain jev \
  --ui
```

Play a concise subject, then leave roughly a beat of room for the first answer. The engine infers the subject's tonal center, holds that center and the selected mode for the complete cycle, and derives each stage's triad locally. The deterministic form moves through `answer`, `sequence`, `inversion`, `fragmentation`, `augmentation`, `diminution`, `stretto`, and `return`. The final bar restates the complete original contour even when the bounded Jev activity decision requests rest. Jev still controls density, temporal attitude, secondary motion, and cadence inside each formal stage; it cannot discard the subject or select individual notes.

During the cycle, keep playing naturally. A new bar containing at least three notes is remembered as a possible next subject, and the most recent candidate takes over only after the current subject has returned. A short pluck, organ, harpsichord-like patch, or restrained strings will keep overlapping entries clearer than a long pad. The terminal log and browser header show the current development stage.

`--human-volume` and `--companion-volume` accept MIDI values from 0 to 127 and default to 100 and 72. They send Channel Volume (CC7) to the input and output part channels, so the parts must use different MIDI channels for independent control. If both channel options are the same, the two GUI controls are linked because one MIDI part cannot have two CC7 values.

## Open the shared beat display

Add `--ui` to `jam`:

```bash
swift run jev-bassist jam \
  --source "Steinberg UR22mkII" \
  --destination "Steinberg UR22mkII" \
  --bpm 120 \
  --input-channel 1 \
  --output-channel 3 \
  --intro-bars 4 \
  --progression "Dm7,G7,Cmaj7,Cmaj7" \
  --brain jev \
  --ui
```

The command starts a loopback-only server and opens `http://127.0.0.1:8765`. Click **Start** on the downbeat. That single action starts the Swift/CoreMIDI bar clock and the browser display together; the browser does not open MIDI itself and does not run a second independent clock. **Stop** ends the live process safely. You can also press `Return` in Terminal.

The **You** and **Jev** sliders send CC7 directly to their configured JD-Xi parts, including before the clock starts. The visual field is a single simulated membrane driven by the combined MIDI timeline. Human notes strike it from the left and companion notes return from the right; every attack launches an expanding luminous shockwave as well as a broad membrane displacement. Velocity and channel volume control the flash, wave radius, deformation, and persistence. Fugue answers also create a mirrored secondary disturbance, making imitation visible across the entire field. In memory and fugue modes the engine publishes four slow expression values: remembered strength controls coupling, tension changes stiffness, activity changes line weight, and resonance controls damping and afterimage length. No microphone permission or audio stream is required.

For the membrane to follow the actual mixed sound and reverb as well, connect the JD-Xi audio outputs to the UR22mkII inputs, select the UR22mkII as the browser or macOS input, and click **Audio**. Chrome will request input permission once. The page analyzes only RMS energy and spectral brightness inside the browser; it does not play, upload, or send the audio to Swift. Leave Audio off when only MIDI response is desired.

Swift sends state changes with server-sent events. Between updates the page renders progress from Swift's original wall-clock start time, so animation jitter does not accumulate into musical clock drift. The TypeSafe API key remains in the Swift process and is never sent to the page.

## Switch the bassist brain to Jev

Create an API key in the [TypeSafe dashboard](https://console.typesafe.ai/) and place it in the environment. Do not put the key in a command-line option, fixture, or log:

```bash
export TYPESAFE_API_KEY='your-key-here'
```

Then run the same session with `--brain jev`:

```bash
swift run jev-bassist jam \
  --source "Steinberg UR22mkII" \
  --destination "Steinberg UR22mkII" \
  --bpm 120 \
  --input-channel 1 \
  --output-channel 3 \
  --brain jev
```

The integration uses TypeSafe's documented `POST /v1/systemone` contract and `jev-latest` model alias. Four independent questions are evaluated together: three `choice` questions for activity, relationship, and motion, plus one `noul` question for fill. The request contains compact musical state, not raw MIDI bytes.

Jev work starts one full bar before the result can be used. At the next bar boundary the engine only reads an already completed result; it never waits. A missing, late, cancelled, malformed, HTTP-error, or low-confidence result uses the rule policy for that bar. With the default four-bar intro, the bar-5 decision is prefetched after bar 3, leaving bar 4 as the network budget.

Each completed request writes one `jev-trace` JSON object to standard error. It contains the full request and response, latency, deadline, resolved model, candidate decision, and outcome, but no API key or authorization header. Normal bass lines include `brain=jev`, `brain=rules`, or `brain=fallback`, so the audible decision source remains visible.

The TypeSafe request and response shapes are documented in the [official API reference](https://docs.typesafe.ai/api).

## Monitor MIDI input only

To inspect incoming events without generating bass:

```bash
swift run jev-bassist monitor --source "Steinberg UR22mkII"
```

To listen to every available MIDI source:

```bash
swift run jev-bassist monitor
```

Play a few notes. Expected output resembles:

```text
2026-09-19T18:42:31.123+09:00 host=83492211002 noteOn  note=60(C4) velocity=83 channel=1
2026-09-19T18:42:31.447+09:00 host=83492534190 noteOff note=60(C4) velocity=0  channel=1
```

Stop the monitor with `Control-C`.

If the interface is not listed, close other DAWs temporarily, reconnect it, and check Audio MIDI Setup before debugging this application.

## Capture a session fixture

Choose a new output path and start recording:

```bash
swift run jev-bassist capture session.json --source "Steinberg UR22mkII"
```

Play the keyboard, then press `Return`. The command drains events already handed off by CoreMIDI and writes the fixture. It refuses to overwrite an existing file.

Each fixture stores:

- schema version and UTC session start time;
- session duration and CoreMIDI source names;
- relative microsecond offset and original host time for every event;
- event kind, note, velocity, and MIDI channel.

## Replay and inspect musical state

Replay requires no connected MIDI device:

```bash
swift run jev-bassist replay session.json --bpm 120 --beats-per-bar 4
```

Here, replay means feeding the recorded events back through the deterministic analyzer. It does not wait in real time or send MIDI to a synthesizer, so it produces no sound. Use `soundcheck` or `jam` for audible output.

`--bpm` defaults to `120` and `--beats-per-bar` defaults to `4`. They define the deterministic analysis grid; the separately reported pulse value is estimated from recent onset intervals. Events exactly on a boundary belong to the following beat, while held notes are sampled at the end of each completed window.

Snapshot output resembles:

```text
beat beat=1 bar=1.1 notes=3 density=3.00 velocity=90.0 register=63.7 held=E4@1,G4@1 pulse=120.0(0.75) chords=C major:1.00
bar bar=1 notes=8 density=2.00 velocity=84.5 register=61.8 held=- pulse=120.0(1.00) chords=C major:0.82
```

## Evaluate the complete local ensemble

`replay` prints analyzer state only. Use `evaluate` when a change to the local decision or phrase engine must be compared without sending any MIDI:

```bash
swift run jev-bassist evaluate \
  session.json \
  evaluation.json \
  --bpm 120 \
  --beats-per-bar 4 \
  --intro-bars 0 \
  --output-channel 3 \
  --style fugue \
  --mode dorian
```

The output is a versioned, secret-free JSON trace containing the original input fixture, exact configuration, local rule policy, completed performed notes, phrase observations, remembered motifs, every beat/bar snapshot, every bar plan, and every scheduled Note On/Off message. It does not contact Jev, wait in real time, or open a CoreMIDI output. The command refuses to overwrite an existing trace so two implementations can be evaluated into separate files and compared directly. Trace v2 adds duration-aware performance and motif data; the decoder continues to accept v1 traces.

The duration-aware memory pairs Note On/Off events, distinguishes observed releases from releases inferred at session end, groups simultaneous attacks, and uses adaptive silence to finalize phrases without splitting them at bar lines. A bounded immutable motif keeps relative onset, duration, rest, accent, and characteristic intervals. Low-confidence chord extraction is not promoted to a melody subject.

This evaluation command records the current engine faithfully; it does not make the current eight-stage fugue conversational. The next milestones add interruptible short-horizon scheduling, then replace the fixed development path with context-driven responses.

## Build and test

```bash
swift build
swift test
```

Pure MIDI decoding, fixture validation, replay, deterministic ensemble evaluation, musical-state analysis, bounded decisions, and phrase generation live in `JevBassistCore`. The typed HTTP client and pipelined provider live in `JevBassistJev`. Apple-specific input, output, host-time conversion, and scheduling live behind `JevBassistMIDI`. Codec, confidence fallback, deadline, cancellation, and prefetch behavior are covered by tests. GitHub Actions runs both commands on macOS for every pull request.

## Planned path

1. Replace whole-bar output submission with a safe short-horizon scheduler that can reconsider unsent notes when the player re-enters.
2. Replace the fixed fugue development with a one-voice modal response whose connection to the human motif is audible before adding further development.
3. Add context-driven development and original-subject return only after the short response passes live listening evaluation.
4. Compare local and Jev candidate selection using identical traces and live sessions, then report timing distributions separately from intentional musical delay.

See [SPEC.md](SPEC.md) for acceptance criteria and architecture constraints.
