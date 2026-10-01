# Hyperframes Composition Brief: Socle

## Objective
Create a short launch-style brag video for Socle — an open source GitOps distribution
for managed Kubernetes.

## Output
- Composition directory: `brag-output/composition/`
- Rendered video: `brag-output/brag.mp4`
- Format: landscape — 1920x1080
- Duration: 22.4 seconds

## Source Material
- Project root: `C:/Users/ulyss/OneDrive/Documents/VSCode Projects/socle`
- Primary files read: `README.md`, `docs/flux-catalog.md`, `docs/distribution.md`,
  `opentofu/clusters/aws/main.tf`, `docs/catalog/*` (module list), `VERSION`
- Product name: **Socle**
- Tagline / strongest claim: "Pick your cloud, pick your modules." /
  "upgrading your whole platform means bumping one version in Git"
- Key UI or visual moment to recreate: the client's `prod.tfvars` — a syntax-coloured
  HCL block in a dark terminal panel. This is the product's entire user surface and it
  must be on screen, legible, for most of scenes 2 and 3.
- Copy that must appear verbatim:
  - `socle_version = "1.4.2"`
  - `# the only line an upgrade touches`
  - `Pick your cloud. Pick your modules.`
  - `100% GitOps. No out-of-band scripts.`
  - `github.com/do-now-io/socle`
  - `pre-0.1.0 · under active construction`
  - The `aws = { … }` and `kube = { … }` blocks from `docs/flux-catalog.md` §2:
    ```hcl
    socle_version = "1.4.2"

    aws = {
      region             = "eu-west-3"
      cluster_name       = "acme-prod"
      environment        = "prod"
      kubernetes_version = "1.34"
    }

    kube = {
      cert_manager = { acme_email = "ops@acme.example" }
      external_dns = { domain_filters = ["acme.example"] }
      monitoring   = { enabled = true }
    }
    ```
  - The catalog chip labels, exactly: `crossplane`, `cilium`, `gateway-api`,
    `cert-manager`, `external-dns`, `argocd`, `grafana`, `victoria-metrics`,
    `victoria-logs`, `victoria-traces`, `otel-agent`, `otel-gateway`
  - The four clouds: `EKS`, `GKE`, `AKS`, `Kapsule`

## Creative Direction
- Tone preset: `polished`
- Creative direction: a quiet infrastructure product film — terminal-grade restraint,
  nothing oversold, the claim does the work
- Interpretation: five scenes, long holds, soft crossfades, no zoom theatrics. Mono-first
  typography because the product is mono-first. Energy comes from precision — elements
  landing exactly on the grid — not from speed. Colour change is rationed: the cosign
  green appears exactly twice in the whole video and nowhere else.
- Angle: the project's own docs promise that `socle_version` is "the only line an upgrade
  touches." The video is built around that single line: open on it, widen out to
  everything it controls (one file, a twelve-module catalog, a signed artifact, four
  clouds), and return to it for the outro. The product is a text file and a signature, so
  the video shows a text file and a signature.
- Hook: a single mono line types itself on near-black — `socle_version = "1.4.2"` —
  then the project's own comment arrives beside it: `# the only line an upgrade touches`
- Outro / punchline: the opening line returns, goes small, and the **SOCLE** wordmark
  sets beneath it with the repository URL and an honest `pre-0.1.0` footnote.
- Avoid:
  - Generic SaaS language ("streamline", "effortless", "supercharge")
  - Abstract filler visuals — no network swirls, particle fields, globes, or glowing
    hexagon meshes. Kubernetes videos are full of these; this one must not be.
  - Cloud-provider logos or the Kubernetes wheel (trademark risk) — use the plain text
    labels `EKS` / `GKE` / `AKS` / `Kapsule` instead
  - Unrelated visual redesign

## Visual Identity
- Background: `#070B10`
- Surface / panel: `#0E1620`; panel border `#1C2836`
- Text: `#E8EEF5`
- Muted text / comments: `#5C7085`
- Accent: `#2DD4BF` (teal — HCL strings, underline, wordmark rule)
- Verified green: `#4ADE80` (cosign check + reconciled borders only)
- Warm number: `#F6C177`
- Display font: Inter Tight (fallback Inter, then system sans)
- Body/code font: JetBrains Mono (fallback ui-monospace) — the hero typeface
- Visual references from the project: the `prod.tfvars` example in
  `docs/flux-catalog.md` §2; the two-artifact table in `docs/distribution.md`
  (artifact → cosign → Flux → cluster); the catalog directory listing in `oci/catalog/`

## Storyboard
Use the storyboard in `brag-output/brag-plan.md` as the creative contract.

Scene summary:
1. **The one line** — 0.00 → 4.40s — `socle_version = "1.4.2"` types out on near-black;
   `# the only line an upgrade touches` fades in beside it at 2.0s. Both must be
   fully legible and settled for ≥2.0s.
2. **One file, one apply** — 4.40 → 8.74s — the frame widens around that line into the
   full `prod.tfvars` panel (aws block, then kube block). Headline **One file. One
   apply.** Ends on a silent 1.6s hold of the complete file.
3. **Pick your modules** — 8.74 → 13.11s — panel shrinks left with `kube = {`
   highlighted; twelve catalog chips arrive in three groups of four. Headline
   **Pick your cloud. Pick your modules.** Full set holds 1.3s.
4. **Signed, pulled, reconciled** — 13.11 → 18.56s — a four-step chain: artifact tile →
   cosign badge turns green (**verified**) → Flux pulls → four cloud tiles go green
   (**reconciled**). Bottom line: **100% GitOps. No out-of-band scripts.**
5. **The wordmark** — 18.56 → 22.40s — opening line returns and goes small; **SOCLE**
   wordmark, tagline, repo URL, `pre-0.1.0` footnote. One long hold, fade out.

## Audio
- Audio role: sparse professional accents over a low, steady bed
- Audio arc: keystrokes in near-silence → two soft settles → deliberate silence on the
  file hold → three light arrivals → four dry chain hits with one bright green accent →
  one bell on the wordmark → fade. The layer never gets louder than the text.
- Music: `assets/music/happy-beats-business-moves-vol-12-by-ende-dot-app.mp3`
- Music treatment: starts at 0.00, volume 0.30, no fade-in. Gentle 1.2s fade-out from
  21.20s to silence at 22.40s. Never above 0.32.
- Music cue guidance: bundled preset, copied to
  `brag-output/composition/assets/music/cues/happy-beats-business-moves-vol-12-by-ende-dot-app.music-cues.json`.
  Tempo 109.96 BPM, beat ≈ 0.545s. Three strong-cue locks:
  **8.74s** (intensity 1.00 → scene 3 opens), **13.11s** (0.98 → scene 4 opens),
  **18.56s** (0.99 → wordmark lands). Beat-grid windows: catalog chip groups at
  9.29 / 10.37 / 11.46; chain steps at 13.64 / 14.73 / 15.84 / 16.93.
- Audio-reactive treatment: subtle — use music RMS to let the terminal panel's edge glow
  and the background vignette breathe, and bass to give the wordmark presence as it
  lands. No waveform, no equalizer bars, no particles, no strobing, no text scaling.
- Audio-coupled moments:
  - Scene 1, 0.40 → 1.50s — per-character typing of the hook line
  - Scene 1, 2.00s — comment fades in (one very soft accent)
  - Scene 2, two config blocks landing — one soft cue each; **silence** 7.0 → 8.60s
  - Scene 3, three chip groups at 9.29 / 10.37 / 11.46 — one cue per group, not per chip
  - Scene 4, four chain steps — one light cue each; brighter accent on the cosign green
  - Scene 5, 18.52s — the single bell under the wordmark, allowed to ring over the fade
- SFX selection guidance: sound follows motion. Keypresses for typing (randomize across
  the `keyboard/` set, volume 0.30-0.40). Soft `interface/drop_*` for blocks and chip
  groups. A single dry family for the four chain steps so they read as one mechanism.
  One `impact/impactGlass_light_*`-class accent on the verification. One
  `impact/impactBell_heavy_000` on the wordmark — the only bell in the video.
  Total 6-8 non-keystroke cues, all at 0.50-0.70.
- SFX analysis guidance:
  `C:/Users/ulyss/.claude/plugins/cache/brag/brag/0.3.0/skills/brag/assets/sfx/sfx-analysis.md`
  — prefer low high-frequency-risk files; this is a polished tone with repeated cues.
- Exact SFX choice: Hyperframes chooses filenames, timestamps, density and volume once
  the animation exists.
- Audio files: copy the chosen music and SFX into `brag-output/composition/assets/`.

## Hyperframes Instructions
Load the composition-building Hyperframes domain skills — `hyperframes-core`
(composition contract + `data-*` timing), `hyperframes-animation` (motion),
`hyperframes-creative` (design spec, beats, audio-reactive), `hyperframes-keyframes`
(seek-safe keyframes), and `hyperframes-cli` (lint/check/render). /brag is its own
workflow: do not enter the `hyperframes` entry-point intent interview and do not route
into its generic promo / launch-video workflow. Prefer native Hyperframes conventions
over anything in `/brag`.

Requirements:
- Show real project material: the `prod.tfvars` HCL block and the real catalog module
  names are mandatory on-screen content.
- Keep all text readable in the final render — short labels ≥0.8s settled, sentences
  ≥0.3s/word. The hook line and its comment get the longest holds.
- Keep the video at 22.4s (within the 15-25s band).
- Include the planned music and SFX layer.
- Treat `/brag` audio notes as guidance, not a fixed cue sheet. Choose SFX after the
  visual animation exists.
- Treat cue metadata as optional timing hints; ignore cues that hurt readability or
  pacing. Three strong-cue locks are planned (8.74 / 13.11 / 18.56) — mark them
  `// beat-locked`. Sequential reveals snap to the listed beats within ±0.10s — mark
  them `// beat-grid`.
- Honor the music fade-out and the scene-2 silence.
- Wire at least one visual element to extracted per-frame audio data (panel edge glow,
  background vignette, wordmark presence). If extraction is unavailable, document it and
  continue — do not block the render.
- Use local assets only; no absolute paths in the composition HTML.
- Run `npx hyperframes check` before render — it is brag's single gate.

## Security constraint (non-negotiable)
`live/scaleway-dev/terraform.tfvars` and `live/scaleway-dev-bootstrap/terraform.tfvars`
contain a real Scaleway project ID and a real public IP address. **Nothing from `live/`
may appear in the composition.** Every on-screen value comes from the published example
in `docs/flux-catalog.md` §2 (`acme-prod`, `eu-west-3`, `acme.example`) or is an obvious
fictional stand-in (`sha256:4f1c…`).
