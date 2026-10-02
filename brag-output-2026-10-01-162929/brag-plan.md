# Brag Plan: Socle — Part 2 (the real cluster)

## What is this app?
An open source GitOps distribution for managed Kubernetes, shipped as one cosign-signed
OCI artifact that Flux pulls. Part 1 (`brag-output/`) made the promise; part 2 proves it
on a real EKS sandbox in eu-west-3, recorded 2026-10-01.

## The angle
Part 1 was a text file and a signature, drawn. Part 2 is the same story **filmed**: the
real `prod.tfvars`, the real `tofu apply`, Flux reconciling every ResourceSet, ArgoCD
and Grafana actually serving. No recreated UI this time: every panel is a cropped
excerpt of a screen recording. The design system of part 1 (palette, fonts, panel,
wordmark) becomes the frame the footage sits in, so the two parts read as one film.

## Hook (first 2-3 seconds)
The real file, tight: `socle_version = "0.1.0-alpha.9"`, selected in VS Code, inside the
part 1 terminal panel. Above it, in Inter Tight: **Same line. A real cluster.** The
fictional `"1.4.2"` of part 1 is answered by the real version string.

## Key moments (the middle)
- **One apply.** `Plan: 57 to add, 0 to change, 0 to destroy.` highlighted, the
  `Creating...` scroll at ×4, then `Apply complete!` in green with the
  `oci://ghcr.io/do-now-io/socle/flux-modules` artifact output.
- **Flux reconciles the rest.** `kubectl -n flux-system get resourcesets`: 17 rows, all
  `READY True / Reconciliation finished`, selection sweeping across the table.
- **It is all running.** ArgoCD's "Let's get stuff deployed!" login, then Grafana's
  Kubernetes / Nodes and pods dashboard on VictoriaMetrics, per-namespace CPU and memory.

## Outro / punchline
Grafana's Kubernetes / Workloads stats, green: **2 · 32 · 0 · 3** (nodes ready, pods
running, pods not running, scrape targets up), then the part 1 wordmark: the real
version line, **SOCLE**, teal rule, `Pick your cloud. Pick your modules.`,
`github.com/do-now-io/socle`, `pre-0.1.0 · under active construction`.

## User flow worth showing
The full flow, for real: **Entry** — `prod.tfvars` (01) → **Key action** — `tofu apply`
(01 → 02 → 03) → **Result** — Flux ResourceSets all True (04), ArgoCD (05), Grafana (06, 07).

## Tone
- Preset: `polished` (identical to part 1)
- Creative direction: a quiet infrastructure product film, now with documentary footage
- Interpretation: one constant window, footage inside it, soft crossfades, slow camera
  push-ins only (no whip zooms). One short caption per scene, held. Energy comes from the
  footage being real.

## Format: landscape — 1920x1080
## Duration: 24.5s

## Visual identity (from part 1, unchanged)
- Background `#070B10`; panel `#0E1620`, bar `#121C28`, border `#1C2836`
- Text `#E8EEF5`; muted `#93A6BD`; comment `#7D90A8` (part 1's contrast-corrected values)
- Accent teal `#2DD4BF`; verified green `#4ADE80`; warm number `#F6C177`
- Display: Inter Tight (fallback Inter); mono: JetBrains Mono
- Wordmark: SOCLE, 152px, weight 600, 0.16em tracking, 1px teal rule beneath
- Strongest visual element: the cropped footage itself, inside the part 1 terminal panel

## Footage rules (from `brag-assets/NOTES.md`)
- Excerpts only, via media offsets; never a whole clip. The apply scroll runs at ×4.
- `01`: never frame line 11 (blurred CIDR). Shots stay on lines 1–9 and 16–26 + terminal.
- `02`: crop to x 360–1040 (the right half is blurred: AWS account ID).
- `03`: crop on `Apply complete!` + `artifact`, stop above the blurred `cluster_endpoint`.
- `05`–`07` (1920×960, browser chrome removed): framed in the panel, label only, no URL bar.
- `sandbox.kubemulus.com` stays visible in 01 (public sandbox domain), never zoomed on.

## Share copy (draft)
Part 2 of Socle: the same one-line promise, on a real EKS cluster. One `tofu apply`,
then Flux reconciles 17 ResourceSets, and ArgoCD and Grafana are up on day one.

## Audio direction
- Role: sparse professional accents over a low, steady bed — same as part 1
- Music: `happy-beats-business-moves-vol-12-by-ende-dot-app.mp3`, **continued from where
  part 1 ended**: source offset 22.37s (a strong cue), so back-to-back the two parts
  share one musical line
- Music treatment: 0.30, 0.25s fade-in from silence, 1.2s fade-out ending on the last frame
- Music cue guidance: bundled preset (109.96 BPM). Part 2 local time = source − 22.37.
  Strong cues used: **4.93** (one apply), **10.37** (Flux), **14.74** (ArgoCD),
  **16.92** (Grafana), **21.28** (wordmark). Captions land on the following beat.
- Audio-reactive treatment: subtle; RMS breathes the panel edge glow and ambient wash,
  bass gives the wordmark presence. Same two CSS properties as part 1.
- SFX posture: sparse — 9 cues, 0.40–0.60; one keypress for the Enter on `tofu apply`,
  a soft settle per scene, `bong` on `Apply complete!`, the single bell on the wordmark.
- Restraint rule: no SFX over the scroll, no per-row sounds on the ResourceSets table.

## Storyboard

### Scene 1 — Same line, a real cluster — 0.00 → 4.93s
Panel `opentofu/clusters/aws/prod.tfvars`. Shot A (01 @ 2.6s): tight on lines 1–9,
`socle_version` selected, slow push-in. Shot B (01 @ 10.3s): the `kube = { … }` block,
`argocd` line selected. Shot C (01 @ 15.75s): same framing, `tofu apply
-var-file="prod.tfvars"` is entered in the terminal. Eyebrow `part 2 · aws · eks ·
eu-west-3`; headline **Same line. A real cluster.** from 0.56s, held to the cut.
Audio: keypress on Enter. Transition: soft crossfade.

### Scene 2 — One apply — 4.93 → 10.37s   // beat-locked 4.93
Panel `tofu apply`. Shot P (02 @ 1.2s): `Plan: 57 to add…` highlighted. Shot Q (02 @ 10s,
×4): the `Creating...` scroll. Shot R (03 @ 0.2s): `Apply complete!` + artifact output.
Headline **One apply.** Eyebrow `opentofu · foundations + flux bootstrap`.
Audio: soft settle at the cut, `bong` on Apply complete. Transition: soft crossfade.

### Scene 3 — Flux reconciles the rest — 10.37 → 14.74s   // beat-locked 10.37
Panel `kubectl -n flux-system get resourcesets`, 04 @ 6.8s: the 17-row table, all True,
selection sweeping. Headline **Flux reconciles the rest.** Eyebrow, green:
`17 ResourceSets · READY True`. Transition: soft crossfade.

### Scene 4 — ArgoCD — 14.74 → 16.92s   // beat-locked 14.74
Panel `argocd`, 05 @ 0.5s: "Let's get stuff deployed!" login. Headline
**ArgoCD, ready to deploy.** Eyebrow `argocd v3.3 · behind the shared Gateway`.

### Scene 5 — Grafana — 16.92 → 19.63s   // beat-locked 16.92
Panel `grafana`, 06 @ 21s: Kubernetes / Nodes and pods, per-namespace CPU and memory,
slow push-in. Headline **Metrics from day one.** Eyebrow
`opentelemetry → victoriametrics → grafana`.

### Scene 6 — 2 · 32 · 0 · 3 — 19.63 → 21.28s
Panel `grafana`, 07 @ 2.0s at ×0.6: the four green stats. Headline **Live, on day one.**

### Scene 7 — The wordmark — 21.28 → 24.50s   // beat-locked 21.28
Part 1's outro, verbatim, with the real line above the mark:
`socle_version = "0.1.0-alpha.9"`. Bell at 21.24. Fade to background at the end.

**Music mood:** steady, clean, low — the same bed, one phrase later.
**Audio summary:** the bed picks up where part 1 left it, one Enter key, a soft settle per
scene, one bong when the apply completes, one bell on the wordmark, then a fade.

## Safety note
All footage comes from `brag-assets/`, already redacted (blur baked in). Crops avoid every
blurred region instead of zooming into it. No secrets, account IDs, CIDRs or endpoints
are visible; node names are private VPC IPs (not sensitive per NOTES.md).
