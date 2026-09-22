# Shared surface validation

The shared engraved surface is evaluated separately for rendering correctness, synchronization, and aesthetic/musical fit. Automated checks cannot establish that a visual is compelling.

## Deterministic browser review

Start any `jam ... --ui` session, then open:

```text
http://127.0.0.1:8765/?visual-demo=1
```

The route loops one fixed sequence at 120 BPM: rhythm box, a four-note human phrase, two keyboard punctuations, and an indexed four-note companion sequence. It sends no MIDI. Refreshing the route resets the same event and clock state.

CI executes `Tests/visual_demo_smoke.js` with a mocked canvas, deterministic clock, and this same route. The smoke test must complete the full loop, draw the shared surface, and keep the live Start action disabled.

## Live scenarios

Keep the JD-Xi program, tempo, mode, volumes, audio-input choice, room, browser size, and `Visual sync` value fixed when comparing revisions.

| Scenario | Expected visual evidence |
| --- | --- |
| Rhythm box only | Kick compresses the whole surface briefly; rim shears; hi-hat makes a small incision. No melodic contour is invented. |
| Short phrase and imitation | The human contour remains recognizable and the sounded companion prefix grows in the same coordinate system. |
| Sequence or inversion | The difference comes from actual response pitches and timing. The relationship label changes presentation only. |
| Human re-entry | Unsent response notes never appear. Already sounded response geometry remains and fades. |
| Dense playing | The surface remains legible and bounded instead of whitening through additive effects. |
| Silence | Percussion transients stop quickly; phrase memory fades over tempo-relative beats; the field settles. |
| Browser reconnect | Retained phrase geometry returns without replaying historical attacks. |
| Reduced motion | Phrase identity remains visible with fewer layers and smaller deformations. |

## Rating

After a three-minute session, rate each item from 1 to 5:

1. The image looks good without knowing how it works.
2. Movement feels synchronized with the audible session.
3. I can recognize when Jev inherits or transforms my phrase.
4. Rhythm supports the image without becoming its subject.
5. The visual makes me want to continue playing.

Record one free-text answer: “Which exact musical moment produced the strongest visual connection, and which produced the weakest?”

## Performance and endurance

Run one 30-minute live session on the target Mac. Confirm that controls remain accessible, the event and phrase collections remain bounded, Stop silences all configured channels, and animation stays responsive. The renderer reduces device-pixel ratio to at most 2, retains at most 256 server events and eight phrase forms, and expires transients independently of phrase memory.

Automated CI and the deterministic demo cover implementation regressions. JD-Xi timing, monitoring latency, 30-minute endurance, and aesthetic ratings remain hardware and human checks and must be reported as such.
