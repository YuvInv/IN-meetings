# IMPLEMENTATION_PLAN — IN-Meetings

**Phase-3 deliverable.** Proposed repo structure, a phased delivery plan (MVP first), and the riskiest
unknowns to prototype before committing to the full build. Backed by [`DESIGN.md`](DESIGN.md),
[`adr/`](adr/), and [`RESEARCH.md`](RESEARCH.md).

> **Gate:** This plan is for review. **No application code until Yuval approves the design.** Phase 0
> (prototypes) is the first thing to build *after* approval — it de-risks the three make-or-break unknowns
> before we invest in the full app.

---

## 1. Proposed repo structure

A monorepo: native app, Python pipeline, and the shared schema in one place.

```
IN-meetings/
├── DESIGN.md  RESEARCH.md  IMPLEMENTATION_PLAN.md  DECISIONS.md  HANDOFF.md  AGENTS.md  CLAUDE.md
├── adr/                              # ADR-001 … 010 (+ README index)
├── docs/
│   └── notes/                        # skill-contracts.md, research-raw/
├── schema/                           # THE CONTRACT — language-neutral, both sides depend on it
│   ├── package.schema.json           # context package (transcript.json, metadata.json) — ADR-005
│   ├── job.schema.json               # Swift→Python job + Python→Swift status — ADR-009
│   └── fixtures/golden-package/      # a complete sample package for contract tests (both sides)
├── app/                              # Swift/SwiftUI menu-bar app — ADR-001,002,007,009
│   ├── Project.swift / project.yml   # XcodeGen (matches the user's other Swift projects)
│   ├── Sources/
│   │   ├── App/                      # LSUIElement lifecycle, menu bar, launch-at-login, onboarding
│   │   ├── Detection/               # mic-in-use, NSWorkspace, AppleScript tab URL, calendar arm
│   │   ├── Capture/                 # Core Audio tap, AVAudioEngine mic, ring-buffer, (SCK video)
│   │   ├── Banner/                  # non-activating NSPanel over fullscreen
│   │   ├── Dashboard/               # SwiftUI list/detail/search/playback
│   │   ├── Store/                   # SQLite (GRDB) — meetings index, FTS5
│   │   └── JobBridge/              # write job.json, watch status.json, spawn pipeline
│   └── Tests/
├── pipeline/                         # Python pipeline — ADR-003,004,005,006,008
│   ├── pyproject.toml                # uv-managed; ruff; type hints (AGENTS.md standards)
│   ├── in_meetings_pipeline/
│   │   ├── __main__.py               # `run <job>` entrypoint; resumable phases
│   │   ├── context/                  # calendar + Saventa + Dealigence assembler → vocab + context.md
│   │   ├── asr/                      # whisper.cpp/MLX wrapper, biasing prompt builder, language route
│   │   ├── diarize/                  # senko on system track, Me/Them merge, name mapping
│   │   ├── package/                  # write transcript.json/.txt, metadata.json, assemble folder
│   │   ├── drive/                    # per-user OAuth, resumable upload, dedup
│   │   ├── claude/                   # claude -p chain + meeting-type routing
│   │   └── status.py                 # phase/progress JSON writer
│   ├── benchmarks/                   # Prototype-1 ASR harness + eval-set tooling
│   └── tests/
└── scripts/                          # build, sign+notarize, model fetch, dev run
```

**Why a monorepo:** the `schema/` contract is the spine both sides depend on; one place to version it
and keep the golden-package fixture both the Swift and Python sides test against. Matches the user's
dual-agent convention (one repo, AGENTS.md/DECISIONS.md/HANDOFF.md at root).

**Note on the skills:** the `--package` input mode for `saventa-summary`/`generate-mom`/`process-meeting`
(ADR-005) is implemented in **`~/repos/claude-skills`**, not here — coordinated, with the same golden
package fixture mirrored there as the cross-repo contract test.

**Stack choices** (consistent with the user's existing repos): Swift + SwiftUI + **XcodeGen** (like
`remote-camera`), **GRDB** for SQLite; Python managed with **uv**, **ruff** formatting, type hints.

---

## 2. Phase 0 — De-risk prototypes (build FIRST, after approval)

Three unknowns can each invalidate the architecture. Prototype them before the full app. Each is small,
throwaway-ok, and has a clear pass/fail. **Order: P1 ∥ P2 first (independent), then P3.**

### P1 — Hebrew + code-switching ASR quality (the make-or-break)
- **Build:** an internal **~2-hour code-switched eval set** from real past meetings (pull audio via the
  `timeless` skill / recordings endpoint; hand-correct reference transcripts for a subset).
- **Measure:** `ivrit-ai/whisper-large-v3-turbo` GGML (whisper.cpp Metal) vs MLX 8-bit vs full
  large-v3 — **with and without** the calendar/CRM `initial_prompt` biasing (incl. mixed-script names) —
  WER overall + a **code-switching-specific** error count (English terms mangled/transliterated), plus
  **M3 real-time factor**. Test senko diarization DER on Hebrew on the system track.
- **Pass:** biased turbo-GGML beats unbiased meaningfully on proper nouns/English terms; WER on
  conversational Hebrew is in the leaderboard ballpark post-quantization; RTF ≤ ~1/4 (≤15 min/hour) on M3.
- **If it fails:** escalate biasing (post-correction against the vocabulary; TCPGen-style); consider the
  Soniox fallback's weight; reconsider on-device-default for the hardest audio. This is why P1 is first.

### P2 — Capture: dual-track taps + permissions on Tahoe
- **Build:** a minimal Core Audio process tap (per-process + system-exclusive) + AVAudioEngine mic →
  two WAV files; offline AEC pass; a non-activating `NSPanel`.
- **Measure on real macOS 26:** (a) does audio-tap capture work with **only "System Audio Recording
  Only"** (no Screen Recording)? (b) **does the monthly re-approval nag fire for tap-only apps?** (the
  community-evidenced claim — verify); (c) banner stays visible + focus-free over **fullscreen Zoom and
  fullscreen Meet**; (d) AirPods-as-mic + built-in-speaker aggregate edge cases; (e) offline AEC removes
  echo when on speakers.
- **Pass:** clean two-track capture, no Screen Recording prompt, no nag, banner works over fullscreen.
- **If it fails (e.g., nag does fire / per-process tap unreliable):** fall back to system-exclusive tap;
  document the nag in onboarding; reconsider SCK only as a last resort for the audio path.

### P3 — Reliable call detection — ✅ DONE (verified live)
- **Built & verified:** Core Audio per-process audio I/O — a process with **both input+output running**
  = a live call, named by bundle ID (`prototypes/p3-detect`). App-agnostic, no Automation/Accessibility/
  Screen-Recording permission, frontmost-independent, rejects one-way playback. (The original app+tab
  approach was prototyped, failed, and dropped — see ADR-001.)
- **Result:** YouTube → `armed=no`; Google Meet w/ mic → `armed=YES CALL in: Google Chrome`. Edge case
  noted: mic-muted-from-start = output-only (latch + calendar mitigate).

### P4 — In-person multi-speaker diarization (NEW — per-speaker from v1, ADR-011)
- **Why:** in-person meetings put every participant on one mic track; "who said what" needs real
  single-track diarization — a distinct, harder quality axis (like code-switching was for calls).
- **Build:** record a real in-person meeting (manual, mic-only); run **senko** then **pyannote
  community-1** on the mic track; map speakers to calendar attendees; measure Hebrew **DER**, overlap
  handling, and accuracy vs room acoustics.
- **Pass:** usable speaker separation + name mapping on a real Hebrew room meeting, with dashboard
  manual fix as backstop. **If weak:** ship merged transcript + manual labeling, improve diarization.

**Phase-0 status:** **P1 ✅ GO** (ASR), **P3 ✅ GO** (detection). **P2** (capture) compiles, runtime
verification pending. **P4** (in-person diarization) to run. Go/no-go folded into `DECISIONS.md`.

---

## 3. Phased delivery

### Phase 1 — MVP (the brief's MVP: detect → banner → dual-track → local Hebrew → package on disk + Drive)
Promote P2+P3 prototypes into the app; wire P1's pipeline.
1. Menu-bar app shell (`LSUIElement`, launch-at-login), onboarding wizard for the 4 TCC grants.
2. **Start paths (ADR-001/011):** auto-detect prompt + **manual Start (menu bar + hotkey)** with
   **profile auto-pick**; banner + **ring-buffer**; **dual-track** capture for calls, **mic-only** for
   in-person (ADR-002).
3. Pipeline job bridge (file queue + status — ADR-009); resumable phases.
4. Local Hebrew transcription (ivrit turbo, **biasing deferred to Phase 2** — MVP can ship unbiased) +
   senko diarization + Me/Them merge → `transcript.json`/`.txt`.
5. Write the **context package** to disk (ADR-005 schema) + SQLite index.
6. **Drive sync** (per-user OAuth, company-first layout — ADR-006).
- **Done when:** a real meeting is detected, recorded two-track, transcribed in Hebrew on-device,
  packaged, and synced to the team Drive — verified on an actual call (not just a build).

### Phase 2 — The differentiator: context injection
1. Context assembler (Calendar + Saventa + Dealigence → ranked vocabulary + `context.md` — ADR-004),
   running parallel with capture; graceful degradation.
2. Turn on **`initial_prompt` biasing** in the ASR (ADR-003) using the assembler's vocabulary; pin model
   revision + add the prompt-following regression test.
3. `metadata.json` enrichment (attendees with side, company + sevanta_deal_id, consent stub).
- **Done when:** transcripts measurably improve on founder/company names vs Phase-1 unbiased, on the P1
  eval set and on a live meeting.

### Phase 3 — Claude handoff + skill `--package` mode
1. Implement the **`--package`** input mode + shared adapter in `~/repos/claude-skills`
   (`saventa-summary`, `generate-mom`, `process-meeting`); mirror the golden-package fixture for
   contract tests on both sides (ADR-005).
2. **`claude -p` chain** + meeting-type routing (ADR-008); results written back + re-synced; one-click
   default, auto opt-in.
- **Done when:** finishing a meeting yields a Saventa summary (and optional MoM/enrich) with one click,
  written into the package and Drive.

### Phase 4 — Dashboard + polish
1. SwiftUI dashboard (ADR-007): list/search (FTS5)/detail/playback/open-in-Drive/re-run-skill/edit
   company mapping/purge.
2. Slide OCR (Vision, opt-in — ADR-003); optional HEVC video toggle (ADR-002).
3. Retention controls + consent features + do-not-record defaults (ADR-010).
4. Optional cloud fallback (Soniox) wiring, opt-in + logged.

### Phase 5 — Rollout to the team
Signing + notarization; install on Eitan/Gil/Eyal's Macs; onboarding walk-through; **counsel review of
ADR-010 items before broad use**; collect real-meeting feedback; tune the eval set.

---

## 4. Verification discipline (per the user's standards)

- **Each phase verified on a real meeting before the next** — "BUILD SUCCEEDED" is not verification for
  capture/UI. Capture correctness = listen to both tracks; transcription = eyeball Hebrew output;
  package = run a skill against it.
- **Contract tests** both sides of the golden package fixture (Swift reads it; skills consume it).
- **Regression tests:** capture pipeline per macOS 26.x point release (audio regressions reported);
  ASR prompt-following per model revision bump.
- **Manual test checklist** at the end of each phase (golden path + main regression risk + one edge case).

## 5. Riskiest unknowns (summary)

1. **Hebrew code-switching ASR quality + biasing effectiveness** (P1) — the whole edge.
2. **Tap permissions / no-monthly-nag on Tahoe + fullscreen banner** (P2) — the capture architecture.
3. **Meet/browser detection + AirPods blind spot** (P3) — reliable triggering.
Secondary: GGML/MLX quantized WER vs leaderboard CT2 numbers; senko Hebrew DER; mixed-script prompt
biasing; bundling a signed Python env; Drive resumable upload of large media.
