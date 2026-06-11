# RESEARCH — Native macOS Meeting Recorder + Hebrew Transcription (IN Venture)

**Phase 1 deliverable.** Landscape findings, ranked Hebrew ASR recommendation with leaderboard
evidence, and a list of features/risks not in the design brief. Compiled 2026-06-10/11.

Method: six parallel research agents (no-bot recorders, bot incumbents, local Hebrew ASR, cloud
Hebrew ASR + Apple, macOS capture APIs, consent/legal), each citing primary sources, followed by
adversarial verification of the load-bearing claims. Verification that the architecture rests on
was re-confirmed in-thread against primary sources (Apple developer docs, the ivrit.ai leaderboard
`benchmark.csv`, Hugging Face model cards). The earlier automated verification pass for the
**legal** and **incumbents** topics completed (all confirmed); see Verification Status.

---

## 0. Executive summary

The strategic bet is sound and the territory is genuinely unoccupied: **no shipping competitor
combines local (on-device) processing + Hebrew + vocabulary biasing.** Granola (category leader)
has no Hebrew and *disables* custom vocabulary in multi-language mode; Krisp's on-device ASR is
English-only. That is the moat — not the "meeting output → Claude" concept, which all three major
incumbents (Granola, Otter, Fireflies) shipped MCP/API layers for in 2025–2026.

Four findings shape the whole design:

1. **Capture: use Core Audio process taps, not ScreenCaptureKit.** Taps capture system/remote audio
   (optionally per-process — Zoom/Meet/Teams only) with **only the "System Audio Recording Only"
   TCC grant** — no Screen Recording permission, no admin password, and **no Sequoia/Tahoe monthly
   re-approval nag** (the nag is keyed to screen capture). This is the single biggest reliability +
   permission-UX win. Confirmed against Apple's own Core Audio docs and the AudioCap reference.

2. **ASR: local ivrit.ai Whisper fine-tunes are at parity with the best cloud API on Hebrew.** On
   the live ivrit.ai leaderboard, `ivrit-ai/whisper-large-v3-(turbo-)ct2-20250513` matches Soniox
   and beats Amazon, Deepgram, gpt-4o-transcribe, ElevenLabs and Google on conversational Hebrew —
   while being **Apache-2.0** (commercial use clear). On-device default carries no quality penalty.
   The turbo fine-tune gives up almost nothing vs full large-v3 at half the compute → it's the default.

3. **The make-or-break axis (Hebrew↔English code-switching) is unmeasured everywhere.** No public
   code-switching Hebrew benchmark exists; ivrit.ai models deliberately degrade language detection
   (forced-Hebrew). We must build an internal code-switched VC-meeting eval set in week one — it is
   the only way to settle engine choice and to validate the `initial_prompt` context-injection bet.

4. **Detection cannot rely on mic-in-use alone.** `kAudioDevicePropertyDeviceIsRunningSomewhere`
   **always returns false for Bluetooth mics (AirPods)** — an Apple-acknowledged, still-open bug.
   Detection must fuse running-app, calendar, and browser-tab signals.

**Recommended ASR stack:** primary = `ivrit-ai/whisper-large-v3-turbo` self-converted to MLX
(≈5–8 min per 1-hour meeting on M3) or the official GGML build on whisper.cpp Metal (≈10–15 min,
zero conversion risk) as the safe runtime; biasing via `initial_prompt` (terms last, ≤224 tokens);
diarization on the system-audio track only (mic track = the known IN partner). **Cloud fallback for
hard audio (opt-in, documented): Soniox** — tops the cloud field on Hebrew, has free-form context
biasing, included diarization, ~$0.10–0.12/hr, and zero-retention + EU residency defaults. Deepgram
Nova-3 Hebrew is the better-known-vendor alternative.

---

## Verification Status

Load-bearing claims and their verification outcome. "Primary (in-thread)" = re-confirmed here
against the cited primary source. "Workflow pass" = confirmed by the adversarial verification agent
before the run hit a session limit.

| # | Claim | Status | Source |
|---|-------|--------|--------|
| 1 | Core Audio process taps capture system/per-process audio with only "System Audio Recording Only" TCC — **no Screen Recording permission** | **Confirmed (primary, in-thread)** | [Apple: Capturing system audio with Core Audio taps](https://developer.apple.com/documentation/CoreAudio/capturing-system-audio-with-core-audio-taps); [AudioCap](https://github.com/insidegui/AudioCap) |
| 2 | `ivrit-ai/whisper-large-v3-turbo` is **Apache-2.0** (commercial use clear) | **Confirmed (primary, in-thread)** | [turbo-ct2 model card](https://huggingface.co/ivrit-ai/whisper-large-v3-turbo-ct2) |
| 3 | ivrit.ai fine-tunes lead/parity vs all cloud APIs on conversational Hebrew (~0.048–0.053 WER eval-d1) | **Confirmed (primary, in-thread)** | [leaderboard benchmark.csv](https://huggingface.co/spaces/ivrit-ai/hebrew-transcription-leaderboard) |
| 4 | Apple `SpeechTranscriber` (macOS 26) **supports he_IL** but exposes **no custom-vocabulary/biasing API** | **Confirmed (secondary, in-thread)** | locale list incl. `he_IL` ([Gubarenko guide](https://antongubarenko.substack.com/p/ios-26-speechanalyzer-guide)); no biasing API |
| 5 | Soniox: top cloud Hebrew, context biasing + diarization + zero-retention/EU residency, ~$0.10–0.12/hr | **Confirmed (primary, in-thread)** | [Soniox Hebrew](https://soniox.com/speech-to-text/hebrew), [pricing](https://soniox.com/pricing), [security](https://soniox.com/docs/security-and-privacy) |
| 6 | Israel one-party consent (unchanged 2024–26); Amendment 13 PPL effective 2025-08-14 | **Confirmed (workflow pass)** | Nevo statutory text; [IAPP](https://iapp.org/news/a/israel-marks-a-new-era-in-privacy-law-amendment-13-ushers-in-sweeping-reform); LoC |
| 7 | ~11–12 US all-party states incl. CA/WA/FL; CIPA $5,000/violation; strictest-rule norm | **Confirmed (workflow pass)** | [Justia 50-state](https://www.justia.com/50-state-surveys/recording-phone-calls-and-conversations/); CA Penal Code §637.2 |
| 8 | Otter is defendant in *In re Otter.AI Privacy Litigation* (5:25-cv-06911 N.D. Cal., MTD through Apr 2026) | **Confirmed (workflow pass)** | [NPR](https://www.npr.org/2025/08/15/g-s1-83087/otter-ai-transcription-class-action-lawsuit); CourtListener docket |
| 9 | Per-speaker talk-time needs capture-time diarization | **Refined (workflow pass)** | Talk-time *can* be reconstructed post-hoc from retained audio; only **audio retention + mic/system channel separation** are true capture-time obligations. Voice→name mapping still needs calendar metadata (also post-hoc). |
| 10 | No monthly re-approval nag for audio-tap-only apps on macOS 26 | **Carried with caveat** | Community-evidenced (keyed to screen capture in `replayd`), **not Apple-documented** — verify empirically on Tahoe in prototype 1 |
| 11 | CTranslate2/faster-whisper is CPU-only on macOS (no Metal) → leaderboard's CT2 artifacts are the wrong Mac runtime | **Carried (known limitation)** | Use GGML/MLX; re-benchmark WER post-quantization |

Two numbers to settle empirically (no public data exists): **(a)** Apple-Silicon real-time factor
for ivrit CT2/GGML/MLX on M3/16GB (leaderboard timing is NVIDIA-only); **(b)** Hebrew↔English
code-switching WER for every candidate engine.

---

## 1. No-bot native macOS recorders — competitive teardown

The category splits three ways: **cloud-ASR no-bot** (Granola, Notion AI Meeting Notes, ChatGPT
Record Mode, Circleback/Notta desktop, Jamie); **local-ASR no-bot** (MacWhisper, Superwhisper,
Hyprnote/Char, Meetily); **driver/overlay outliers** (Krisp = virtual audio devices — excluded by
our constraints; Cluely = GPU-hook overlay). Named-but-not-in-category: **Spoke** is now a meeting-bot
API platform; **Aiko** is file/mic-only Whisper (no system audio); **Fathom**'s "bot-free" Zoom mode
uses Zoom's Live Stream API, requires linking the account, and **posts a recording notice into chat**
— not invisible ([Fathom help](https://help.fathom.video/en/articles/295552)).

**Granola** (leader). Detection: calendar event opens a notepad at meeting time + mic-in-use for
unscheduled calls; a call within 15 min of a calendar event auto-matches; notification copy adapts
per app ("Huddle detected" for Slack) ([notifications doc](https://docs.granola.ai/help-center/taking-notes/notifications)).
UI: menu-bar/notepad hybrid, **prompt-to-record, not silent auto-record**. Capture: mic + system via
the "Screen & System Audio Recording" pane; captures the **combined system mix and "cannot isolate
individual applications"** ([transcription doc](https://docs.granola.ai/help-center/taking-notes/transcription)).
Tracks: two channels rendered as "Them" (system) / "Me" (mic); **no live diarization of individual
remote speakers**. Transcription: **cloud** (Deepgram + AssemblyAI), audio deleted after real-time
transcription ([security](https://www.granola.ai/security)). Languages: ~10 desktop — **no Hebrew**;
multi-language mode **disables custom vocabulary** ([multi-language doc](https://docs.granola.ai/help-center/customising-granola/multi-language)).
Pain: Bluetooth/USB dropouts, default-device mismatch, garbled numbers, no per-speaker names.

**MacWhisper** (closest to our architecture). Detection: monitors a configurable app list
(Zoom/Teams/Slack/Webex/Discord/browsers/WhatsApp…) and prompts to record; **FaceTime excluded by
macOS**. Permissions: Screen Recording + Microphone. **Auto meeting recording is beta with explicit
data-loss warnings** ("for critical meetings we recommend manual") and is absent from the App Store
build ([support doc](https://macwhisper.helpscoutdocs.com/article/30-record-meetings)). Local Whisper;
speaker labels assigned post-hoc.

**Superwhisper**: dictation-first; Meeting Mode records app audio, transcribes **locally**, speaker
separation off by default ([docs](https://superwhisper.com/docs/modes/meeting)). Manual start.

**Hyprnote/Char & Meetily** (open-source references to mine): both Tauri, mic + system audio,
on-device Whisper + local LLM. Meetily is MIT (whisper.cpp + Parakeet + Ollama)
([github.com/Zackriya-Solutions/meetily](https://github.com/Zackriya-Solutions/meetily)).

**Platform squeeze**: Notion AI Meeting Notes and ChatGPT Record Mode (macOS, 120-min cap) now ship
no-bot system-audio recording — both cloud-processed, neither handles Hebrew locally.

### Capture mechanism — the decisive finding
Three routes ([Recall.ai engineering](https://www.recall.ai/blog/how-to-access-to-system-audio)):
virtual drivers (excluded), **ScreenCaptureKit** (audio tied to a screen session; needs Screen
Recording TCC; whole-mix), **Core Audio process taps** (`CATapDescription`, macOS 14.2+, practical
from 14.4). Taps need only "System Audio Recording Only" TCC, no admin password, **no monthly nag**,
and allow **per-process capture** (exclude Slack pings/music/notifications — a quality *and*
confidentiality win). Audio Hijack 4.x is the production proof. A local purple mic indicator appears
on the recordist's own Mac only.

### Detection patterns & failure modes to design against
Best-in-class = Granola's calendar + mic-in-use + app-aware stack — but with the **AirPods blind
spot** (Bluetooth mics don't report `…IsRunningSomewhere`), so fuse signals. Design against: (1)
silent missed recordings after the SCK monthly re-approval lapses (avoided by taps); (2) Bluetooth/USB
mid-meeting dropouts; (3) echo/double-transcription without headphones (needs AEC fed by both
streams); (4) auto-record unreliability (offer manual start + **ring-buffer** so the first minutes
aren't lost — would leapfrog the category); (5) FaceTime uncapturable; (6) number/entity errors
(biasing addresses this); (7) notification prompts invisible over fullscreen — prefer a floating
panel over Notification Center.

---

## 2. Bot incumbents — post-meeting features worth stealing

Capture architecture is irrelevant (they use bots); their **post-meeting feature set** is the target.

**Consistently valued** (G2, 1,000+ reviews): clean summaries + transcripts, **action items with
owners/deadlines**, cross-meeting search/ask-AI, CRM auto-logging. **Shelfware/gimmick:**
sentiment/engagement scoring (Read.ai's core — "directional data, not gospel"), speaker coaching,
playbook adherence. Basic AI summaries are now commodity ("the summary is free now").

**VC-specific signal:** (a) **bot-free candor** ranks #1 for investor meetings — Granola ranked first
by Value Add VC precisely because no bot preserves founder candor; (b) **CRM push to deal records** is
the highest-ROI feature — Affinity's native Notetaker reports **1–2.5 hrs saved/person/week and ~60%
fewer missing CRM fields** at TELUS Global Ventures ([affinity.co](https://www.affinity.co/guides/vc-ai-tools));
(c) searchable transcript database across deal flow. **Bot backlash validates the no-bot premise:**
Gartner predicted 40% of enterprises restricting third-party bots; Oxford blocked Read.ai/Fireflies/
Sembly (Aug 2025); 84% of professionals alter speech when a visible notetaker is present.

**Ranked "steal this" list** (LLM post-processing is ~free for us; the question is what data we must
capture *at record time*):

1. **Action items w/ owner + deadline** (Circleback-grade) — trivial Claude skill; needs reliable
   speaker→identity attribution (diarization + calendar attendees).
2. **CRM auto-push w/ deal/contact matching** (Affinity-parity → Sevanta) — mostly exists via
   `process-meeting`; the gap is **Circleback-style routing rules** (meeting type / attendee domain /
   invitee count → which skill runs). Needs calendar metadata bundled in the package.
3. **Cross-meeting search / ask-AI** — a Claude skill over an indexed folder of packages. Needs a
   stable package schema + meeting IDs + per-utterance timestamps for citation.
4. **Sparse human notes merged with transcript (Granola's most-loved pattern)** — partner jots 5
   bullets, AI expands against the transcript. Needs a lightweight **timestamped in-meeting note field**
   — the brief has no such surface; adding it steals the single most VC-praised interaction.
5. **Multi-meeting digests** (weekly deal-flow digest; "what changed since last call") — trivial with
   a scheduled Claude skill over packages.
6. **Topic trackers** — auto-flag valuation/competitor/round-term mentions across the corpus.
7. **Follow-up email draft** — trivial; needs attendee emails.
8. **Talk-time / monologue analytics** — genuine pitch-quality signal (founder vs investor ratio).
   *Refined finding:* reconstructable post-hoc from retained audio — the real capture-time
   obligations are **audio retention + mic/system channel separation**, not record-time diarization.
9. **Clip/snippet sharing** — low value, a **trust landmine** for an invisible recorder (sharing audio
   reveals the recording existed); keep word-level timestamps anyway (cheap, enables citations later).
10. **Skip entirely:** sentiment/engagement scoring, speaker coaching, playbook adherence.

---

## 3. Hebrew ASR — the crux

### 3.1 Live leaderboard standings (ivrit.ai, `benchmark.csv` updated ~June 2026)
The [ivrit.ai Hebrew Transcription Leaderboard](https://huggingface.co/spaces/ivrit-ai/hebrew-transcription-leaderboard)
is the only neutral multi-dataset Hebrew benchmark covering local models *and* cloud APIs. WER across
five eval sets (lower is better; **eval-d1 / eval-whatsapp are real Israeli conversational speech —
the closest proxy to VC meetings**):

| Engine | eval-d1 | whatsapp | SASpeech | FLEURS | kan |
|---|---|---|---|---|---|
| **Soniox STT** (cloud) | **.048** | .090 | .065 | .177 | .114 |
| **ivrit whisper-large-v3-ct2-20250513** (local) | .051 | .072 | **.064** | **.174** | **.081** |
| **ivrit whisper-large-v3-turbo-ct2-20250513** (local) | .053 | **.071** | .066 | .181 | .082 |
| Amazon Transcribe (batch) | .066 | .104 | .085 | .230 | .090 |
| Deepgram Nova-3 | .067 | .120 | .102 | .233 | .210 |
| OpenAI gpt-4o-transcribe | .073 | .126 | .109 | .210 | **.394** |
| stock whisper large-v3 | .098 | .132 | .094 | .262 | .134 |
| ElevenLabs scribe_v1 | **.200** | **.264** | .068 | .181 | .109 |
| Google STT | .211 | .352 | .189 | .385 | .292 |

Takeaways: (a) **local ivrit.ai fine-tunes match the best cloud (Soniox) and beat every other cloud
API** on conversational Hebrew — gpt-4o/Google are not competitive; (b) fine-tuning ~halves WER vs
stock Whisper; (c) **turbo gives up only ~0.002–0.007 WER vs full large-v3** at half the compute →
turbo is the default; (d) **ElevenLabs Scribe collapses on conversational Hebrew (20–26%)** despite
3.1% FLEURS marketing — a marketing-vs-reality trap to avoid.

### 3.2 Model lineup & licensing (huggingface.co/ivrit-ai)
All current v3 family fine-tunes are **Apache-2.0** (commercial use clear; the custom-license concern
applies only to legacy v2). Builds: HF/transformers (`whisper-large-v3`, `-turbo`), **GGML** for
whisper.cpp, **CT2** for faster-whisper, and a Dec-2025 **ONNX** turbo build (hints at a future
streaming/live path). ivrit.ai also rehosts **ungated MIT mirrors of pyannote 3.1 diarization +
segmentation** — bundleable without an HF token.

### 3.3 Apple-Silicon runtimes (M3/16GB)
- **Gotcha: CTranslate2/faster-whisper has no Metal backend — CPU-only on macOS.** The exact CT2
  artifacts the leaderboard scores are the *wrong runtime* for Mac. Use **GGML (whisper.cpp Metal)**
  or a **self-converted MLX** build.
- **mlx-whisper ≈2× faster than whisper.cpp** for large-v3-turbo, but no prebuilt ivrit MLX model
  exists — convert ivrit weights via `mlx_whisper.convert` (4/8-bit).
- **whisper.cpp**: full Metal; optional Core ML ANE encoder (>3× CPU); large-class ~3.9 GB fp16,
  turbo ~half — comfortable on 16 GB.
- **1-hour meeting on M3** (community benchmarks): large-v3 ≈20–30 min; turbo ≈10–15 min (whisper.cpp);
  MLX turbo ≈5–8 min. **No published Apple-Silicon ivrit numbers → benchmark in week one.**

### 3.4 Code-switching + initial_prompt biasing (the strategic bet)
- Hebrew-centric fine-tunes are deliberately mostly-Hebrew (degraded language detection, forced-Hebrew
  token). Documented failure: cross-language terms mangled/transliterated ("makolet→Macaulay"). The
  only public "Hebrish" model is a 500-sentence single-speaker PoC — not production-grade.
- **Prompt-following in fine-tunes is fragile**: ivrit.ai's first turbo run *catastrophically forgot*
  timestamp/previous-text conditioning; they retrained specifically to restore it
  ([ivrit.ai blog, Feb 2025](https://www.ivrit.ai/en/2025/02/13/training-whisper/)). → pin model
  revisions; add a prompt-following regression test.
- **initial_prompt**: only the **last ≤224 tokens** are consumed (put high-value terms last). Plain
  prompting biases proper nouns softly; stronger gains need architecture-level biasing (TCPGen).
  A Feb 2026 paper ("Whisper: Courtside Edition") validates LLM-generated context injected into Whisper
  prompts improving proper-noun recognition — **published precedent for the calendar/CRM-vocabulary
  bet** — with the open caveat that mixed-script prompts (English names in a Hebrew prompt) are untested.

### 3.5 Cloud options & Apple (for the fallback decision)
- **Soniox** (not in the brief — the sleeper): tops the cloud field, free-form **context biasing** for
  Hebrew (participant names/terms — exactly our design), included diarization + translation,
  **~$0.10/hr async / $0.12/hr streaming** (cheapest), **no storage by default + never trains on
  customer data + EU residency**. Risk: small vendor. → **recommended cloud fallback.**
- **Deepgram Nova-3 Hebrew** (added Feb 2026): monolingual RTL, streaming + batch + **keyterm
  prompting**, ~$0.46/hr; best-known-vendor alternative; code-switching untested (monolingual).
- **OpenAI gpt-4o-transcribe**: decent but a **39.4% WER blowup** on one Hebrew set (hallucination
  risk for a "hard audio" role); `/v1/audio/transcriptions` reportedly zero-retention by default.
- **Apple SpeechTranscriber (macOS 26)**: **he_IL IS supported** (locale list expanded to ~42) and it's
  fully on-device with no duration cap — **but there is no custom-vocabulary/contextual-strings API**,
  so the context-injection bet cannot run through Apple's stack. Hebrew quality is unbenchmarked.
  Possible niche use: a fast on-device fallback or a live-captions view, never the biased primary.

### 3.6 Diarization
- **senko** (MIT): **1 hour in 7.7 s on M3** via CoreML/ANE — diarization is essentially free; but
  embeddings are English+Mandarin (Hebrew DER unvalidated). **pyannote community-1** (CC-BY-4.0) as a
  quality fallback. **2-track trick:** mic track = the known IN partner (auto-labeled, no diarization);
  diarize only the system-audio track (fewer speakers, no cross-talk).

### 3.7 Recommendation
- **Primary engine:** `ivrit-ai/whisper-large-v3-turbo` (rev ≥ 20250513). **Runtime:** MLX 8-bit
  (fastest) with the official **GGML/whisper.cpp Metal** build as the zero-risk fallback runtime.
- **Biasing:** calendar/CRM vocabulary in `initial_prompt`, terms last, ≤224 tokens; pin revision +
  regression-test prompt-following.
- **Runner-up model:** full `ivrit-ai/whisper-large-v3` when max accuracy matters and latency doesn't.
- **Cloud fallback (opt-in, documented):** Soniox; Deepgram Nova-3 as the alternative.
- **Diarization:** senko on the system track (validate Hebrew DER first); pyannote community-1 fallback.
- **Mandatory week-one work:** build a ~2-hr internal code-switched VC-meeting eval set; re-benchmark
  WER on GGML/MLX quants (leaderboard scored CT2 fp16) and measure M3 real-time factor.

---

## 4. macOS capture APIs (macOS 26 / Tahoe)

### ScreenCaptureKit
Captures screen, system audio (`capturesAudio`, 13+), and mic (`captureMicrophone`, 15+) — app-audio
and mic arrive as separate sample buffers. **No true audio-only stream**: the `SCContentFilter` must
name a screen target and the stream is gated on **Screen Recording TCC**. `SCRecordingOutput` (15+)
records direct-to-file but is video-oriented. macOS 26 added screenshot APIs but **no relevant audio
deprecations/additions**. (Apple Community reports of muffled audio after 26.0/26.3 → regression-test
each point release.)

### Core Audio process taps — the better fit
`CATapDescription` + `AudioHardwareCreateProcessTap` (14.2+, sample code 14.4+) tap specific processes
(PID→AudioObjectID) or the whole system, via an aggregate device → IOProc → `AVAudioFile`. **Permission:
`NSAudioCaptureUsageDescription`; the grant lands under "Screen & System Audio Recording" with an
audio-only ("System Audio Recording Only") category — Screen Recording is NOT required** (confirmed:
[Apple docs](https://developer.apple.com/documentation/CoreAudio/capturing-system-audio-with-core-audio-taps),
[AudioCap](https://github.com/insidegui/AudioCap)). **Gotcha:** no public API to check/request the
permission — AudioCap uses private TCC SPI; OK for internal distribution, an App Store risk. Tapping
shows a local-only purple indicator. **Verdict:** taps give the remote track clean and isolated,
per-process targeting, and skip Screen Recording TCC entirely.

### Mic + the echo problem
Capture mic via `AVAudioEngine.inputNode`. **Voice-processing IO brings AEC but has documented macOS
side effects** — gain reduction and **ducking of other audio (it can duck the very system track we're
recording)**. macOS 14+ exposes `voiceProcessingOtherAudioDuckingConfiguration` to tame it.
**Recommended:** record the **mic raw by default** and run **software AEC offline** using the tap track
as a perfect far-end reference (the tap captures exactly the remote audio leaking into the mic); only
enable VP (ducking `.min`) for users on built-in speakers. Headphones make echo moot.

### Permissions set & the re-approval nag
Needed: **Microphone**, **System Audio Recording Only**, **Calendar** (EventKit), **Automation/Apple
Events per browser** for tab URLs. **Not needed:** Screen Recording, Accessibility (if AppleScript is
used instead of AX). The macOS 15+ "Allow For One Month" re-approval is keyed to **screen capture**
(`replayd/ScreenCaptureApprovals.plist`); **no reports tie it to audio-tap-only apps** — a major UX
argument for taps, *to be confirmed empirically on Tahoe*.

### Detection signals & floating panel
`kAudioDevicePropertyDeviceIsRunningSomewhere` works for built-in/wired mics but **always false for
Bluetooth (AirPods)** — Apple-acknowledged bug; use as one signal among several (frontmost app via
`NSWorkspace`, running meeting apps, calendar window, browser tab URL). **Browser tab URL: use
AppleScript** (`URL of active tab of front window`, needs Automation TCC) — the AX route is unreliable
on Chromium (lazy a11y tree, `AXEnhancedUserInterface`/`AXManualAccessibility` side effects); Firefox
has no script support (accept degraded detection). **Floating banner:** `NSPanel` with
`.nonactivatingPanel`, `isFloatingPanel`, level `.floating`+, `collectionBehavior = [.canJoinAllSpaces,
.fullScreenAuxiliary]` is the working recipe to float over fullscreen Zoom/Meet without stealing focus.

### Recommended capture architecture
Dual-track, **SCK-free**: (1) **system/remote track** via a Core Audio process tap (system-exclusive
or pinned to the detected meeting app) → aggregate device → IOProc → `AVAudioFile`; (2) **mic track**
via AVAudioEngine, **raw by default**, offline AEC using the tap as reference. Permissions: Mic + System
Audio Recording Only + Automation + Calendar. No Screen Recording, no monthly nag, and separate tracks
give **free two-party (Me/Them) separation** for the Hebrew/English ASR.

---

## 5. Consent & legal (design considerations — NOT legal advice; flag for counsel)

**Israel (home jurisdiction): one-party consent, unchanged as of mid-2026.** The Secret Monitoring
Law 5739-1979 criminalizes recording **without the consent of *any* party**, so a participant recording
their own meeting is outside the offense. Two-party proposals have recurred (2016; reportedly 2025) but
**none has passed** — counsel should monitor; a switch would invalidate silent-by-default. Edge case:
a participant recording made **to commit an offense/tort** loses the exemption.

**The real 2024–26 change is Amendment 13 to the Protection of Privacy Law (effective 2025-08-14):** it
doesn't touch one-party consent, but it makes the *stored corpus* riskier — expanded sensitive-data
definitions, PPA administrative fines, statutory damages without proof of harm, DPO duties, stronger
notice/security obligations. A library of recorded VC meetings with speaker identities is plausibly a
regulated **"database"**; founder discussions of finances/health/legal can hit "especially sensitive".

**Counterparties:** ~11–12 **US all-party states** (CA/WA/FL…); **CIPA §632 = $5,000/violation** and is
driving the current AI-notetaker litigation wave; practitioner norm = **apply the strictest
participant's rule** (an Israeli VC calling a California GP is in all-party territory). **EU/GDPR:**
recording identifiable participants is personal-data processing (no household exemption); workable basis
is **legitimate interest + prior notice + right to object**; systematic recording likely needs a DPIA.
**UK:** lawful to record as a party; the risk shifts to **sharing/processing** (pushing to Drive/Claude).

**What no-bot competitors do:** silence by default + an *optional* disclosure helper + responsibility-
shifting ToS. Granola's auto-consent-message is **Zoom-on-macOS only (Meet paused)** — meaning even the
leader has no working disclosure automation for browser Meet, IN Venture's primary platform; a
Meet-compatible disclosure would exceed industry norm. **Otter is being sued** (ECPA/CIPA) for
all-party-consent failures — live proof the risk is real.

**Design mitigations to surface (for counsel review):** per-meeting **consent metadata** field
(`consent_status`, jurisdiction hints from attendee domains/timezones); a **jurisdiction-aware nudge**
(inform, never block) when attendees resolve to US all-party / EU; optional **verbal-disclosure capture**
(timestamped affirmation in the transcript); **calendar-invite boilerplate**; **retention controls**
(auto-delete raw audio post-transcription, transcript retention windows, per-meeting purge);
**do-not-record defaults** for internal/HR/1-on-1 events (Israeli employment-privacy exposure is higher
for *internal* recordings); **least-privilege Drive access**. Counsel decisions: is the corpus a
regulated database / DPO needed; EU lawful basis + DPIA; CIPA exposure for US counterparties; internal-
recording policy; retention schedule; what consent evidence to store and for how long.

---

## 6. Features & risks NOT in the brief (consolidated, prioritized)

**High-impact design changes to consider now:**

1. **Ring-buffer / retroactive capture.** Auto-record is genuinely unreliable (even MacWhisper ships it
   as beta with data-loss warnings). A rolling buffer that retroactively saves the first minutes after
   the user confirms would leapfrog the entire category and fix the #1 silent-failure mode.
2. **Timestamped in-meeting quick-notes field.** Granola's *most-loved* interaction isn't auto-summary —
   it's sparse human notes the AI expands against the transcript. The brief has no in-meeting surface;
   adding one steals the best VC-praised pattern and improves summary grounding.
3. **Per-process audio tap (not whole-system).** Pin capture to the meeting app → notification dings,
   Slack pings, music never enter the pipeline. Both a transcription-quality and a **confidentiality**
   win (unrelated audio never recorded) that Granola explicitly cannot do.
4. **Meeting-type router (Circleback-style rules).** Route by attendee domain / invitee count / title →
   which Claude skill runs (founder pitch → saventa-summary; IC → MoM; LP call → nothing). Cheap,
   high-value, and turns the package into an automation hub rather than a one-shot.
5. **"What changed since last call" deltas** for recurring founder meetings — trivial once a package
   corpus exists; high VC value for tracking deal progression.

**Risks / constraints to bake in:**

6. **AirPods break mic-in-use detection** (Apple bug) — detection must be multi-signal or AirPods users
   miss recordings.
7. **Voice-processing AEC can duck the system track you're recording** — naive "enable echo cancellation"
   actively damages the remote audio; use raw mic + offline AEC.
8. **CT2 (the leaderboard's format) is CPU-only on Mac** — must use GGML/MLX and re-benchmark quantized WER.
9. **Fine-tune prompt-following can silently break on a model revision** (ivrit.ai's documented
   catastrophic-forgetting episode) — pin revisions, add a CI regression test for context-injection.
10. **FaceTime audio is uncapturable** by any third-party recorder — state it in the supported-platforms
    matrix.
11. **The local purple recording indicator** is Apple-controlled and visible if the user screen-shares
    their menu bar — invisible to remote participants but not to someone watching the screen; explain in
    onboarding.
12. **The "no monthly nag for taps" advantage is community-evidenced, not Apple-documented** — verify on
    Tahoe before promising "never miss a recording".
13. **macOS 26 audio regressions** reported after point updates — pin a tap+mic pipeline regression test
    to each 26.x.
14. **The Claude-context-layer concept is being commoditized** by Granola/Otter/Fireflies MCP servers —
    differentiation must stay on no-bot + on-device + Hebrew + Sevanta-specific skills, not the
    integration concept.
15. **Clip/audio export is a trust landmine** for an invisible recorder — make audio export policy-
    controlled and off by default.
16. **Internal recordings carry higher Israeli legal risk than external ones** — do-not-record defaults
    for internal/HR/1-on-1 events.
17. **Security note (unrelated to build, worth flagging):** the desktop copy of the `timeless-access`
    skill embeds a live `TIMELESS_ACCESS_TOKEN` in plaintext — rotate/remove it.

---

## Appendix — primary sources

Full per-claim citations are inline above. Anchor primary sources:

- Apple — [Capturing system audio with Core Audio taps](https://developer.apple.com/documentation/CoreAudio/capturing-system-audio-with-core-audio-taps),
  [NSAudioCaptureUsageDescription](https://developer.apple.com/documentation/bundleresources/information-property-list/nsaudiocaptureusagedescription),
  [ScreenCaptureKit capturesAudio](https://developer.apple.com/documentation/screencapturekit/scstreamconfiguration/capturesaudio),
  [SpeechTranscriber](https://developer.apple.com/documentation/speech/speechtranscriber),
  [control screen/system-audio recording](https://support.apple.com/guide/mac-help/control-access-screen-system-audio-recording-mchld6aa7d23/mac)
- ivrit.ai — [org models](https://huggingface.co/ivrit-ai), [Hebrew leaderboard](https://huggingface.co/spaces/ivrit-ai/hebrew-transcription-leaderboard),
  [whisper-large-v3 card](https://huggingface.co/ivrit-ai/whisper-large-v3),
  [turbo-ct2 card](https://huggingface.co/ivrit-ai/whisper-large-v3-turbo-ct2),
  [training blog](https://www.ivrit.ai/en/2025/02/13/training-whisper/)
- Reference impls — [insidegui/AudioCap](https://github.com/insidegui/AudioCap),
  [whisper.cpp](https://github.com/ggml-org/whisper.cpp), [mlx-whisper](https://pypi.org/project/mlx-whisper/),
  [senko](https://github.com/narcotic-sh/senko), [Meetily](https://github.com/Zackriya-Solutions/meetily)
- Capture analysis — [Recall.ai: system audio on macOS](https://www.recall.ai/blog/how-to-access-to-system-audio),
  [AudioTee write-up](https://stronglytyped.uk/articles/audiotee-capture-system-audio-output-macos)
- Cloud ASR — [Soniox Hebrew](https://soniox.com/speech-to-text/hebrew),
  [Deepgram Hebrew Nova-3](https://deepgram.com/learn/speech-to-text-for-hebrew-persian-urdu-on-nova-3),
  [ElevenLabs Scribe Hebrew](https://elevenlabs.io/speech-to-text/hebrew)
- Legal — [RecordingLaw Israel](https://www.recordinglaw.com/world-recording-laws/israel-recording-laws/),
  [IAPP Amendment 13](https://iapp.org/news/a/israel-marks-a-new-era-in-privacy-law-amendment-13-ushers-in-sweeping-reform),
  [Justia 50-state recording survey](https://www.justia.com/50-state-surveys/recording-phone-calls-and-conversations/),
  [NPR — Otter.AI lawsuit](https://www.npr.org/2025/08/15/g-s1-83087/otter-ai-transcription-class-action-lawsuit)

_~144 unique sources were consulted across the six research tracks; the consolidated list is preserved
at `/tmp/in-meetings-research/all_sources.md` and the full agent outputs at
`/tmp/in-meetings-research/extracted.json`._
