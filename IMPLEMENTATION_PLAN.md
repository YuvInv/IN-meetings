# IMPLEMENTATION_PLAN — IN-Meetings

**Phase-3 deliverable.** Proposed repo structure, a phased delivery plan (MVP first), and the riskiest
unknowns to prototype before committing to the full build. Backed by [`DESIGN.md`](DESIGN.md),
[`adr/`](adr/), and [`RESEARCH.md`](RESEARCH.md).

> **Status (2026-06-15):** Phase-0 prototypes + the MVP spine are **built and merged to `main`**
> (detect → dual-track capture → on-device Hebrew transcription → diarization → context package →
> Drive backup → dashboard). The live, ordered priorities are in **"Road to a team-ready v1"**
> directly below; the original phased plan (§3) is kept as design background, but the new section
> **supersedes its sequencing**.

## Road to a team-ready v1 — current priorities (2026-06-15)

**Goal:** close the gap between "the spine works" and "a basic, reliable on-device recorder the IN
Venture team can install and rely on." The four founding goals (Yuval): (1) reliable on-device
record + transcribe, (2) reliable Hebrew–English transcription, (3) backup recordings, (4) automate
**meeting → transcription → Claude skill → Saventa CRM**. **Out of scope for v1:** the in-app "AI
overview" panel — the skill *trigger* into the CRM is in (goal 4); a rich summary surface in the
dashboard is deferred.

Ordered. Sequencing call (Yuval, 2026-06-15): **video is pulled up into P1** (flagged "BIG"); the
retention/size cap rides with it. Full rationale in `DECISIONS.md` (2026-06-15).

### P0 — Installable, real, and trustworthy (the adoption gate)
1. **Hybrid app shell — Dock app + menu-bar tray.** ✅ **DONE** (committed `60b3546`, verified live). The app is BOTH a real Mac app (persistent
   **Dock icon**, opens the **dashboard**) AND a menu-bar **tray** for quick *Record-now* — today it's
   `LSUIElement=true` (menu-bar only, no Dock icon). → `LSUIElement=false` + keep `MenuBarExtra`; keep
   the recorder alive when the dashboard window closes (`terminateAfterLastWindowClosed=false`);
   Dock-click (re)opens the dashboard; launch-at-login comes up **quietly** (background, no window pop).
   **Amends ADR-001/ADR-009.** (Plumbing mostly exists — "Open Dashboard" window + fronting.)
2. **Distribution / packaging → moved to the final _Ship_ phase (done LAST, per Yuval 2026-06-15).**
   Developer-ID sign + notarize + `.dmg` + launch-at-login + Sparkle are best set up once the app is
   feature-complete, and are gated on Apple Developer enrollment. See the **Ship** phase below + the
   runbook [`docs/distribution-setup.md`](docs/distribution-setup.md).
3. **Onboarding / TCC permission wizard.** 🟢 **BUILT (pending live-verify), branch
   `feat/onboarding-tcc-wizard`.** First-run stepped Liquid Glass wizard: **Microphone → System Audio →
   Screen Recording → Google sign-in**, every step skippable (nothing blocks the dashboard), with a
   **restart at the end** for Screen Recording (grant takes effect on relaunch). Pure Core
   `OnboardingChecklist` (tested) + `Permissions.provokeSystemAudioPrompt()` + app `OnboardingModel` +
   `OnboardingWindow`; auto-opens first run, re-runnable from the menu ("Set up IN Meetings…"). (ADR-009;
   DECISIONS 2026-06-22.) Core +6 tests + build green. ⏳ live-verify the UI + the four real prompts +
   relaunch (`docs/manual-tests-onboarding.md`).
4. **Reliability pass (goal 1).** ✅ **DONE (PR #10):** Silero VAD bundled in the app + provisioned-from-
   bundle on launch; **pipeline failures surfaced** in the dashboard (`status:"failed"` + error + Reveal-log).
   ⏳ still live-verify the partial-silence fix + multi-party (3+) diarization on a real call.

### P1 — Close the value loop + video (video pulled up)
5. **Company naming (gap #2).** ✅ **DONE (PR #9):** title/transcript fallbacks + an edit/rename UI
   (`MeetingStore.updateCompany`) wired to the "Needs linking" bucket so "Unknown company" is fixable.
6. **Claude auto-trigger → summary (gap #4 / goal 4).** ✅ **DONE (PR #12):** a finished **call** → headless
   `claude -p` over the package, fed an **app-bundled `saventa-summary` recipe + house style** (NOT a
   globally-installed skill) → writes `summary.md` → dashboard "Summary" panel (running/done/failed +
   Copy/Retry/Summarize) + Drive sync. Auto-on-finish (file-only, safe) + a manual Summarize button.
   **Sevanta/CRM posting stays ON HOLD.** (ADR-008, amended.) ⏳ live-verify the panel + full flow on a real
   call (`docs/manual-tests-saventa-summary.md`).
7. **Video (gap #5, BIG).** ✅ **DONE (PR #10 + the A/V rewrite in PR #11):** SCK capture → `meeting.mp4` →
   Drive → dashboard playback. The **A/V rewrite captures screen+system+mic via one SCK stream (one clock)**
   so the merge is synced by construction; **~6× smaller** (720p + passthrough mux). Added the Screen-Recording
   grant. (Amends ADR-002.)
8. **Retention / storage cap.** ✅ **DONE (PR #10/#11):** prune raw tracks after Drive backup (on by default).
   ⏳ a **global cache-size cap** (delete oldest synced meetings beyond N GB) is still TODO.
9. **Drive folder picker (gap #1).** ✅ **DONE (PR #10):** the real **Google Picker** web view (WKWebView) —
   pick any My-Drive / Shared-Drive folder; needs a browser API key (committed).
10. **Auto-stop when a meeting ends (MUST-HAVE — promoted from P2, 2026-06-16).** 🟢 **BUILT (pending
    live-verify), branch `feat/auto-stop-meeting-end`.** Debounced **visible countdown** on the detector's
    armed→idle edge — "Meeting ended — stopping in {n}s…" — that rides out ~12 s of network blips and
    auto-stops at 0 unless cancelled (**Keep recording** / **Stop now**); never silent. Trigger = call-app
    audio-process exit (the existing `CallDetector` signal — that answers the "research meeting-end" ask).
    Pure Core `AutoStopArbiter` (tick-driven, unit-tested) + app `MeetingEndCoordinator` + `MeetingEndOverlay`
    card; `autoStopEnabled` (default on). **Amends ADR-002**; **supersedes** the 2026-06-14 keep-if-ignored
    choice (DECISIONS 2026-06-22). Core 100/100 + build green. ⏳ live-verify on a real call
    (`docs/manual-tests-auto-stop.md`).
11. **Upload an audio file for transcription (MUST-HAVE, NOT P0 — 2026-06-16).** Import an existing audio
    file (e.g. a phone recording) → run the normal pipeline (ASR → post-correct → diarize → package) →
    dashboard + Drive, with **no live capture**. Reuses everything downstream of capture (an import affordance
    + a synthetic `job.json`; mic-only / single-track by default). Design later.

### P2 — Polish & robustness extras
Speaker naming ✅ (PR #11, manual one-tap assign). _(Auto-stop moved up to a P1 must-have, 2026-06-16.)_
Remaining: ring-buffer pre-roll; trash/delete + export-SRT + open-in-Drive; mic-device picker + hotkey rebind
+ storage/consent settings; fuzzy/edit-distance post-correction; tighten Drive scope to `drive.file`; a global
cache-size cap; the onboarding/TCC wizard (P0).

### Future / post-v1 (captured, NOT designed yet)
- **User-defined post-meeting skills.** A Settings surface where each user describes to Claude what to do with
  a transcription — multiple summary types / workflows / schedules. **Generalizes** the saventa-summary
  auto-trigger (the first, **hardcoded** instance). Complex (prompt-management UI, multiple/scheduled workflows,
  safety) — recorded as a direction; **do not design or build it now** (Yuval, 2026-06-16). Revisits ADR-008.

Verification discipline (§4) is unchanged — each item verified on a real meeting before the next.

### Ship — packaging & distribution (done LAST, per Yuval 2026-06-15)
The "make it installable" packaging is deliberately the **final** step — set up the signing/notarization
pipeline once, when the app is feature-complete, rather than re-fighting it as the app changes. **Gated on
an Apple Developer Program membership** (only an `Apple Development` cert exists today — no Developer ID).
Enrollment + technical runbook: [`docs/distribution-setup.md`](docs/distribution-setup.md).
- **Developer-ID signing** (replaces the dev cert) + **hardened runtime**.
- **Notarize + staple** (`notarytool`) → a **drag-to-`/Applications` `.dmg`**.
- **Launch-at-login** (`SMAppService`) against the *installed* app + quiet-login (no dashboard pop).
- **Sparkle** auto-update (needs Developer-ID + notarization + EdDSA keys).
- Install-test on a second Mac (clean Gatekeeper + audio-TCC).

Development continues on the current **Apple Development** signing until then — only *distribution to other
Macs* needs Developer ID.

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

### Phase 2 — The differentiator: context injection (calendar-first)
1. **Context assembler — calendar** (Google Calendar → deterministic post-correction vocab + `context.md`
   + `metadata` enrichment — ADR-004, amended): match meeting→event, internal/external split, company from
   external domains. **✅ Done + live-verified 2026-06-14 (PR #6).** Post-correction (NOT `initial_prompt`
   — P1 disproved prompt biasing) with a curated core lexicon (the fund name) applied on every meeting.
2. **ASR robustness**: silence-gating (`asr.is_silent`, done) + **VAD** to stop hallucination on
   within-track silence (in progress), evaluated against the P1 eval set so WER doesn't regress.
- **Saventa + Dealigence enrichment is OUT of the MVP → Phase 6** (deferred per Yuval 2026-06-14). Calendar
  alone is the MVP's context layer.
- **Done when:** transcripts measurably improve on company/fund names vs Phase-1 unbiased — ✅ on the P1
  eval set + a live meeting.

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

### Phase 6 — Post-MVP: CRM + Dealigence context enrichment (deferred 2026-06-14)
Extend the context assembler with **Saventa** (`sevanta_search_deals` → deal id, stage, prior notes) and
**Dealigence** (`search-company`/`search-person` → founder backgrounds, investors) — same Swift-fetch /
Python-transform shape as the calendar slice, with Swift-owned API keys in Keychain. Sets
`company.matched:true` + `sevanta_deal_id`/`dealigence_id`, adds founder priors to `context.md`, and supplies
authoritative entity names to the post-correction vocab. **Pushed to the end of development** so the MVP
ships on the calendar context layer alone.

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
