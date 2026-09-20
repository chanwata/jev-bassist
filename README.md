# Jev Bassist

Jev Bassist is an experimental macOS session partner that listens to a human MIDI performance and answers as a bassist.

The project deliberately separates two jobs:

- a local, deterministic engine schedules and generates MIDI notes;
- Jev will later choose musical behavior such as `follow`, `contrast`, `rest`, or `fill`.

Network latency must never sit in the note-timing path.

## Current milestone: capture and musical state

The CLI now supports both the real-time input boundary and deterministic offline analysis. It can:

- list CoreMIDI input sources;
- connect to all sources or one source selected by name;
- decode MIDI 1.0 Note On and Note Off messages, including running status;
- print receipt time, CoreMIDI host time, MIDI note number, note name, velocity, and channel.
- capture a performance as a versioned, timestamped JSON fixture;
- replay a fixture without MIDI hardware;
- derive beat and bar snapshots containing note density, velocity, register, held notes, a pulse estimate, and ranked chord candidates.

The snapshot grid is explicitly configured with tempo and meter so the same fixture always produces the same state sequence. Pulse and chord values are deliberately small, inspectable heuristics at this stage. No network call, GUI, generated bass output, or MIDI output scheduling is included yet.

## Requirements

- macOS 14 or later
- Xcode Command Line Tools with Swift 6
- a USB or Bluetooth MIDI device

Check the toolchain:

```bash
xcode-select --install
swift --version
```

## Run it with a JD-Xi

1. Connect and power on the JD-Xi.
2. Open **Audio MIDI Setup** on the Mac and confirm that the JD-Xi appears in MIDI Studio.
3. From the repository root, list visible sources:

```bash
swift run jev-bassist devices
```

4. Start the monitor. The source match is case-insensitive and may be a substring. Always use a name reported by `devices`; a JD-Xi connected through a MIDI interface appears under the interface name:

```bash
swift run jev-bassist monitor --source "Steinberg UR22mkII"
```

To listen to every available MIDI source:

```bash
swift run jev-bassist monitor
```

5. Play a few notes. Expected output resembles:

```text
2026-09-19T18:42:31.123+09:00 host=83492211002 noteOn  note=60(C4) velocity=83 channel=1
2026-09-19T18:42:31.447+09:00 host=83492534190 noteOff note=60(C4) velocity=0  channel=1
```

Stop the monitor with `Control-C`.

If the JD-Xi is not listed, close other DAWs temporarily, reconnect USB, and check Audio MIDI Setup before debugging this application.

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

Pure MIDI decoding, fixture validation, replay, and musical-state analysis live in `JevBassistCore` and are covered by deterministic unit tests. Apple-specific I/O lives behind `JevBassistMIDI`. GitHub Actions runs both commands on macOS for every pull request.

## Planned path

1. Add a local rule-based bassist and MIDI output scheduling.
2. Introduce `BassDecisionProvider` with rule-based and Jev implementations.
3. Compare `rules` and `jev` modes using identical replays and live sessions.

See [SPEC.md](SPEC.md) for acceptance criteria and architecture constraints.
