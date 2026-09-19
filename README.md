# Jev Bassist

Jev Bassist is an experimental macOS session partner that listens to a human MIDI performance and answers as a bassist.

The project deliberately separates two jobs:

- a local, deterministic engine schedules and generates MIDI notes;
- Jev will later choose musical behavior such as `follow`, `contrast`, `rest`, or `fill`.

Network latency must never sit in the note-timing path.

## Current milestone: MIDI monitor

The first milestone establishes the real-time input boundary. The CLI can:

- list CoreMIDI input sources;
- connect to all sources or one source selected by name;
- decode MIDI 1.0 Note On and Note Off messages, including running status;
- print receipt time, CoreMIDI host time, MIDI note number, note name, velocity, and channel.

No network call, GUI, chord recognition, or generated bass output is included yet.

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

4. Start the monitor. The source match is case-insensitive and may be a substring:

```bash
swift run jev-bassist monitor --source "JD-Xi"
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

## Build and test

```bash
swift build
swift test
```

Pure MIDI decoding lives in `JevBassistCore` and is covered by deterministic unit tests. Apple-specific I/O lives behind `JevBassistMIDI`. GitHub Actions runs both commands on macOS for every pull request.

## Planned path

1. Capture and replay timestamped MIDI fixtures.
2. Derive `MusicalState` over beat and bar windows.
3. Add a local rule-based bassist and MIDI output scheduling.
4. Introduce `BassDecisionProvider` with rule-based and Jev implementations.
5. Compare `rules` and `jev` modes using identical replays and live sessions.

See [SPEC.md](SPEC.md) for acceptance criteria and architecture constraints.
