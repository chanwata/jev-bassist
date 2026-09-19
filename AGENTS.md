# Agent instructions

## Goal

Build an interactive AI bassist for live MIDI sessions. Optimize for the felt quality of musical responsiveness, reliable timing, and inspectable decisions—not code volume or autonomous feature expansion.

## Source of truth

- `SPEC.md` defines product intent, architecture constraints, milestones, and success criteria.
- `README.md` documents behavior that currently works.
- Do not describe planned behavior as implemented.
- When implementation and documentation disagree, stop and make the discrepancy explicit.

## Architecture rules

- Jev makes bounded musical decisions, never individual MIDI notes.
- MIDI note generation and scheduling remain local and deterministic.
- No network, disk I/O, logging, printing, UI work, or musical analysis inside a CoreMIDI callback.
- Keep Apple-framework code in `JevBassistMIDI`; keep parsing and musical-domain logic in platform-independent targets.
- Put every external decision service behind a protocol with a local implementation.
- Design input state and output decisions to be serializable and replayable.
- Every remote request must eventually support a deadline, cancellation, latency measurement, and local fallback.
- Never log API keys, authorization headers, or unredacted secrets.

## Change discipline

- Work in small milestone-scoped pull requests.
- Avoid unrelated formatting or refactors.
- Do not add a GUI before the CLI session loop and replay harness work.
- Do not add a third-party dependency when the standard library or Apple frameworks are sufficient.
- Do not invent undocumented Jev endpoints or schemas. Record the missing contract and ask for authoritative API material.
- Preserve public interfaces unless the task explicitly authorizes a breaking change.

## Swift and concurrency

- Use Swift 6 language mode and treat concurrency warnings as design feedback.
- Prefer value types and `Sendable` domain models.
- Isolate mutable callback state and document any `@unchecked Sendable` conformance.
- Do not block CoreMIDI or audio-related callback threads.
- Normalize MIDI Note On with velocity zero to Note Off at the decoding boundary.

## Validation

Before declaring a code change complete, run:

```bash
swift build
swift test
```

For MIDI parsing, add deterministic tests that include fragmented packets, running status, interleaved real-time bytes, and relevant boundary values.

For timing-sensitive features, add replayable fixtures and report p50, p95, and p99 where applicable. Hardware checks are documented separately and must not be represented as automated tests.

## Definition of done

- behavior matches the current milestone in `SPEC.md`;
- build and unit tests pass on macOS CI;
- error paths fail clearly and do not hang the event loop;
- README usage reflects the implemented CLI exactly;
- no secret or machine-specific path is committed;
- the pull request states what was tested automatically and what still requires a JD-Xi or other MIDI device.
