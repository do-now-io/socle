# Brag Plan: Socle

## What is this app?
An open source GitOps distribution for managed Kubernetes — EKS, GKE, AKS and Scaleway
Kapsule — shipped as one cosign-signed OCI artifact that Flux pulls, so upgrading an
entire platform means bumping one version string in Git.

## The angle
Most platform teams upgrade Kubernetes by touching forty things. Socle's own docs make
a much narrower promise, in the project's own words: `socle_version` is
*"the only line an upgrade touches."* The video is built around that single line —
start on it, widen out to everything it actually controls (four clouds, a whole catalog,
a signed supply chain), and come back to it. No SaaS adjectives, no abstract network
swirls. The product here is a text file and a signature, so the video shows a text file
and a signature.

## Hook (first 2-3 seconds)
Black. A monospace caret. One line types itself:

```
socle_version = "1.4.2"
```

Then the project's own comment arrives beside it, dimmer:
`# the only line an upgrade touches`

That claim is the whole pitch, and it is verbatim from `docs/flux-catalog.md`.

## Key moments (the middle)
- **The file widens.** The one line pulls back to reveal the full `prod.tfvars` —
  `socle_version`, the `aws = { … }` block, the `kube = { … }` block. One file, one
  apply, one cluster. Real HCL from the repository's own documented example.
- **The catalog arrives.** Module chips land in groups — crossplane, cilium,
  gateway-api, cert-manager, external-dns, argocd, grafana, victoria-metrics,
  victoria-logs, victoria-traces, otel-agent, otel-gateway — under the line
  "Pick your cloud. Pick your modules."
- **The chain verifies.** A cosign check turns green on the artifact digest, Flux pulls
  it, four cloud tiles (EKS · GKE · AKS · Kapsule) reconcile to the same state. The
  payoff beat: *100% GitOps. No out-of-band scripts.*

## Outro / punchline
The whole frame collapses back to the one line it opened on, then the wordmark:
**SOCLE** — "Pick your cloud. Pick your modules." — `github.com/do-now-io/socle`.
A small, honest footnote: `pre-0.1.0 · under active construction`.

## User flow worth showing
The product has no GUI; its user flow is text and reconciliation, and that *is* the
demo. Three beats:
1. **Entry** — the client writes one `prod.tfvars` (version, cloud block, `kube` block).
2. **Key action** — one `tofu apply`; OpenTofu provisions and steps away.
3. **Result** — Flux pulls the signed artifact and reconciles the catalog in dependency
   order, identically on all four clouds.

The centerpiece scenes (2, 3, 4) are exactly these three beats.

## Tone
- Preset: `polished`
- Creative direction: a quiet infrastructure product film — terminal-grade restraint,
  nothing oversold, the claim does the work
- Interpretation: five scenes, long holds, soft crossfades, no zoom theatrics. Type is
  mono-first because the product is mono-first. Energy comes from precision — things
  landing exactly on grid — not from speed.

## Format: landscape — 1920x1080
## Duration: 22.4s

## Visual identity (from the project)
No CSS exists in this repository (it is OpenTofu, HCL, YAML and Markdown), so the
palette is derived from the product's actual surface: a dark terminal with HCL syntax
colouring and a verification green.
- Background: `#070B10`
- Surface / panel: `#0E1620`, border `#1C2836`
- Text: `#E8EEF5`
- Muted text / comments: `#5C7085`
- Accent: `#2DD4BF` (teal — strings, highlights, wordmark rule)
- Verified green: `#4ADE80` (cosign check, reconciled state) — used exactly twice
- Warm number: `#F6C177`
- Display font: Inter Tight (fallback Inter)
- Mono font: JetBrains Mono — the hero typeface, used for every code surface
- Strongest visual element: the `prod.tfvars` block itself, syntax-coloured, from
  `docs/flux-catalog.md` §2

## Share copy (draft)
Been building Socle: an open source GitOps distribution for EKS, GKE, AKS and Kapsule.
One signed OCI artifact, pulled by Flux — upgrading the whole platform is one line in Git.

## Audio direction
- Role: sparse professional accents over a low, steady bed
- Music: `happy-beats-business-moves-vol-12-by-ende-dot-app.mp3` (steady and clean —
  the `polished`/`cinematic` pick)
- Music treatment: starts at 0.00 at volume 0.30, no fade-in (the typing needs a floor
  under it), gentle 1.2s fade-out under the outro wordmark ending at the last frame.
  Never above 0.32.
- Music cue guidance: bundled preset read —
  `<skill-dir>/assets/music/cues/happy-beats-business-moves-vol-12-by-ende-dot-app.music-cues.json`,
  tempo 109.96 BPM, beat ≈ 0.545s. Lock three major moments to strong cues:
  **8.74s** (1.00 → catalog scene opens), **13.11s** (0.98 → verification scene opens),
  **18.56s** (0.99 → wordmark lands). Beat-grid windows for sequential reveals:
  catalog chip groups at 9.29 / 10.37 / 11.46 (every other beat); verification chain
  steps at 13.64 / 14.73 / 15.84 / 16.93.
- Audio-reactive treatment: subtle; use music RMS to let the terminal panel's edge glow
  and the background vignette breathe, and bass to give the wordmark a touch of presence
  on landing. No waveform, no equalizer bars, no particles.
- SFX posture: sparse — target 6-8 cues total, all at 0.50-0.70. Keystrokes are the
  exception and sit lower (0.30-0.40) because there are many of them.
- Audio-coupled moments: the typed hook (per-character keypresses), each catalog chip
  group landing, the cosign check turning green, the wordmark landing.
- Restraint rule: nothing percussive over readable body copy; no sound at all during the
  hold on the full tfvars block — the silence is what makes the file feel calm. One bell
  maximum in the entire video, saved for the wordmark.

## Storyboard

### Scene 1 — The one line — 0.00 → 4.40s (4.40s)
Near-black frame. Centred, a single mono line types out character by character over
~1.1s starting at 0.40s: `socle_version = "1.4.2"` — key in `#E8EEF5`, the string in
`#2DD4BF`, a soft block caret. At 2.00s the comment fades up to its right in `#5C7085`:
`# the only line an upgrade touches`. Both hold, fully settled, until 4.10s. A faint
teal underline sweeps under the line at 2.0s and stays.
Sequential/interaction: yes — per-character typing of the 23-character line, then one
fade-in for the comment. The comment holds 2.1s settled and remains legible through the
0.4s crossfade into Scene 2.
Audio intent: intimate and dry. A room, a keyboard, nothing else. Music is present but
sits far back.
Audio-coupled idea: randomized `keyboard/keypress-*` per character at low volume; one
very soft accent when the comment appears.
Music: low steady bed from 0.00.
Transition mood: soft → Scene 2

### Scene 2 — One file, one apply — 4.40 → 8.74s (4.34s)
The single line stays fixed in place and the frame **widens around it**: a terminal
panel draws itself out from that line and the rest of `prod.tfvars` fills in above and
below over 0.8s — the `aws = { region, cluster_name, environment, kubernetes_version }`
block, then the `kube = { cert_manager, external_dns, monitoring }` block. The opening
line keeps its teal underline so the eye never loses it. A filename tab reads
`clusters/prod.tfvars`. At 6.20s a quiet line sets above the panel in Inter Tight:
**One file. One apply.** Hold the complete frame, silent, 7.0 → 8.60s.
Sequential/interaction: yes — two config blocks arrive one after the other (aws, then
kube), each as a soft 0.25s fade-and-rise, 0.5s apart. Not a per-line reveal; the block
lands whole so it reads as a file, not a list.
Audio intent: the sound of something settling into place, then deliberate quiet.
Audio-coupled idea: one soft `interface/drop_*` per config block; nothing during the
1.6s hold.
Music: bed continues, unchanged.
Transition mood: soft crossfade → Scene 3

### Scene 3 — Pick your modules — 8.74 → 13.11s (4.37s)   // beat-locked: 8.74s
The tfvars panel slides left and shrinks to a third of frame, still legible, with the
`kube = {` block highlighted. To its right, the catalog arrives as mono chips on a loose
grid, in three groups of four, each group on every other beat:
- 9.29s — `crossplane` `cilium` `gateway-api` `cert-manager`
- 10.37s — `external-dns` `argocd` `grafana` `victoria-metrics`
- 11.46s — `victoria-logs` `victoria-traces` `otel-agent` `otel-gateway`

Each chip: 0.2s rise + fade, 40ms stagger within its group. The headline sits above in
Inter Tight: **Pick your cloud. Pick your modules.** (on at 8.95s, holds the whole
scene). All twelve chips hold together, settled, from 11.70 → 13.00s.
Sequential/interaction: yes — twelve chips in three beat-aligned groups; chips are
one-to-two-word labels, so grouping keeps every label above the 0.8s settled floor and
the full set holds 1.3s afterwards.
Audio intent: three light arrivals, then presence. Rhythmic but not busy.
Audio-coupled idea: one `casino/card-place-*` or `interface/drop_*` per **group** (three
cues total, not twelve).
Music: bed continues; the scene opens on the 8.74s strong cue.
Transition mood: soft crossfade → Scene 4

### Scene 4 — Signed, pulled, reconciled — 13.11 → 18.56s (5.45s)   // beat-locked: 13.11s
Everything clears to a single horizontal chain, built left to right on the beat grid,
each node a small mono-labelled tile:
- 13.64s — `ghcr.io/do-now-io/socle` — the artifact tile, with a truncated digest
  `sha256:4f1c…` beneath it
- 14.73s — a `cosign` badge snaps onto the artifact and turns `#4ADE80` with a check.
  Label: **verified**
- 15.84s — `flux` pulls: a thin teal line draws from the artifact rightwards
- 16.93s — it lands on four cloud tiles in a 2×2: `EKS` `GKE` `AKS` `Kapsule`. Each
  tile's border goes green in a 0.1s cascade. Label beneath: **reconciled**

At 17.47s the closing claim fades up along the bottom in Inter Tight:
**100% GitOps. No out-of-band scripts.** It holds through the transition.
Sequential/interaction: yes — four chain steps at 13.64 / 14.73 / 15.84 / 16.93, each
~1.09s apart, which clears the short-label floor comfortably. The cosign verification is
the one moment of colour change in the video.
Audio intent: mechanical certainty. Four small, dry, same-family hits, then one positive
accent on the green.
Audio-coupled idea: a light `impact/impactGeneric_light_*` or `interface/click_*` per
chain step; a single brighter `impact/impactGlass_light_*` on the cosign green.
Music: bed continues, slightly more present (the track's strongest window).
Transition mood: soft crossfade → Scene 5

### Scene 5 — The wordmark — 18.56 → 22.40s (3.84s)   // beat-locked: 18.56s
The chain dissolves. The opening line returns alone for a beat — `socle_version = "1.4.2"`
— then slides up and goes small as the wordmark sets beneath it:

**SOCLE** in Inter Tight, wide letter-spacing, a 1px teal rule under it.
Below, in mono `#5C7085`: `Pick your cloud. Pick your modules.`
Below that: `github.com/do-now-io/socle`
Bottom-right, very small: `pre-0.1.0 · under active construction`

Wordmark lands at 18.56s. Everything is settled and holding by 19.80s and stays to
22.10s. Final 0.3s: a slow fade to the background colour.
Sequential/interaction: none — one reveal, one long hold. The restraint is the point.
Audio intent: arrival and rest. The one bell of the video, then the bed recedes.
Audio-coupled idea: a single `impact/impactBell_heavy_000` at 18.52s under the wordmark,
allowed to ring over the music fade.
Music: 1.2s fade-out from 21.20s to silence at 22.40s.
Transition mood: fade to black — end

**Music mood for this video:** steady, clean, low — present enough to carry 22 seconds,
quiet enough that the tfvars block reads as calm rather than scored.
**Audio summary:** keystrokes in near-silence, two soft settles, three light arrivals,
four dry chain hits with one green accent, one bell on the wordmark, then a fade — the
sound follows the product from a single line to a reconciled estate without ever getting
louder than the text.

## Safety note
Nothing from `live/` was used. The repository's live roots contain a real Scaleway
project ID and a real public IP in `terraform.tfvars`; those were read during inspection
and **deliberately excluded**. Every value on screen comes from the published example in
`docs/flux-catalog.md` §2 (`acme-prod`, `eu-west-3`) or is a fictional stand-in (the
`sha256:4f1c…` digest). No secrets, tokens, real hostnames or personal data appear in
the video or the share copy.
