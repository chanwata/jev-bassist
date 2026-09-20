# Jev Bassist

Jev Bassist is an experimental macOS session partner that listens to a human MIDI performance and answers as a bassist.

The project deliberately separates two jobs:

- a local, deterministic engine schedules and generates MIDI notes;
- Jev can choose bounded musical behavior such as `follow`, `contrast`, `rest`, or `fill`.

Network latency must never sit in the note-timing path.

## Current milestone: Jev decision provider

The CLI completes its audible loop with either local rules or a pipelined Jev decision provider. It can:

- list CoreMIDI input sources;
- list CoreMIDI output destinations;
- connect to all sources or one source selected by name;
- decode MIDI 1.0 Note On and Note Off messages, including running status;
- print receipt time, CoreMIDI host time, MIDI note number, note name, velocity, and channel;
- capture a performance as a versioned, timestamped JSON fixture;
- replay a fixture without MIDI hardware;
- derive beat and bar snapshots containing note density, velocity, register, held notes, a pulse estimate, and ranked chord candidates;
- make a bounded rule-based bass decision once per completed bar;
- ask Jev for `activity`, `relationship`, `motion`, and `fill` in one typed request;
- prefetch Jev decisions one bar ahead and fall back to the deterministic rule policy without delaying a note;
- log the complete secret-free Jev request, response, resolved model, outcome, and latency;
- generate voice-led, dynamically restrained bass pockets and schedule them with CoreMIDI host timestamps;
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
  --brain jev \
  --ui
```

The command starts a loopback-only server and opens `http://127.0.0.1:8765`. Click **Start** on the downbeat. That single action starts the Swift/CoreMIDI bar clock and the browser display together; the browser does not open MIDI itself and does not run a second independent clock. **Stop** ends the live process safely. You can also press `Return` in Terminal.

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

## Build and test

```bash
swift build
swift test
```

Pure MIDI decoding, fixture validation, replay, musical-state analysis, bounded decisions, and phrase generation live in `JevBassistCore`. The typed HTTP client and pipelined provider live in `JevBassistJev`. Apple-specific input, output, host-time conversion, and scheduling live behind `JevBassistMIDI`. Codec, confidence fallback, deadline, cancellation, and prefetch behavior are covered by tests. GitHub Actions runs both commands on macOS for every pull request.

## Planned path

1. Verify the revised pocket generator and `--brain jev` on the JD-Xi using the same captured performance.
2. Add explicit key or chord-progression input for melody-only sessions; guessing harmony from a monophonic line remains intentionally unsupported.
3. Compare `rules` and `jev` modes using identical replays and live sessions.
4. Report p50, p95, and p99 decision latency and stability statistics for evaluation.

See [SPEC.md](SPEC.md) for acceptance criteria and architecture constraints.
