# Hyperframes Composition Brief: Socle — Part 2

## Objective
Part 2 of the Socle brag video: the same promise as part 1, shown on a real cluster with
cropped excerpts of real screen recordings.

## Output
- Composition directory: `brag-output-2026-10-01-162929/composition/`
- Rendered video: `brag-output-2026-10-01-162929/brag.mp4`
- Format: landscape — 1920x1080
- Duration: 24.5 seconds

## Source Material
- Part 1: `brag-output/brag-plan.md`, `brag-output/composition/index.html` (branch `brag`)
- Footage: `brag-assets/01…07*.mp4` (muted, H.264 30 fps, redacted) + `brag-assets/NOTES.md`
- Copy that must appear verbatim:
  - `Same line. A real cluster.` / `One apply.` / `Flux reconciles the rest.`
  - `ArgoCD, ready to deploy.` / `Metrics from day one.` / `Live, on day one.`
  - `socle_version = "0.1.0-alpha.9"`, `SOCLE`, `Pick your cloud. Pick your modules.`,
    `github.com/do-now-io/socle`, `pre-0.1.0 · under active construction`

## Creative Direction
- Tone preset: `polished`, identical to part 1
- One constant window (part 1's `.panel`), footage cropped inside it, slow push-ins,
  soft crossfades, one held caption per scene
- Avoid: generic SaaS language, filler visuals, fake browser chrome with a URL, zooming
  into any blurred region, showing any clip in full

## Visual Identity
Exactly part 1's tokens (`--bg #070b10`, `--panel #0e1620`, `--panel-bar #121c28`,
`--line #1c2836`, `--text #e8eef5`, `--muted #93a6bd`, `--comment #7d90a8`,
`--accent #2dd4bf`, `--green #4ade80`), Inter Tight / JetBrains Mono, the same SOCLE
wordmark block.

## Storyboard
See `brag-plan.md`. Scenes: 1 file (0–4.93) · 2 apply (4.93–10.37) · 3 Flux
(10.37–14.74) · 4 ArgoCD (14.74–16.92) · 5 Grafana (16.92–19.63) · 6 stats
(19.63–21.28) · 7 wordmark (21.28–24.5).

## Audio
- Music: `assets/music/happy-beats-business-moves-vol-12-by-ende-dot-app.mp3`, media
  offset 22.37s (continues part 1), 0.30, short fade-in, 1.2s fade-out
- Cue source: bundled preset `assets/music/cues/…music-cues.json`; local = source − 22.37
- Audio-reactive: `assets/music/audio-data.js`, extracted for the 22.37 → 46.87 window
- SFX: keypress, impactSoft ×4, bong, card-slide, bell — copied under `assets/sfx/`
- Footage is muted; no audio is taken from the clips
