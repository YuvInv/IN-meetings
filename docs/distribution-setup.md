# Distribution Setup — Apple Developer account, signing, notarization, `.dmg`

> **Status (2026-06-15): deferred to LAST.** Packaging/signing/installer is the **final "Ship" phase**,
> done once the app is feature-complete (so the notarization pipeline is set up once, not re-fought as the
> app changes). It is **blocked on an Apple Developer Program membership** — see Step 1. Development
> continues fine on the current **Apple Development** signing; only *distribution to other Macs* needs
> Developer ID. This doc is the runbook for when we get there.

## Goal
A **notarized `.dmg`** that the ~5-person team can double-click-install and run, with audio recording
permissions working cleanly on each Mac. This app **cannot** ship via the App Store (it uses private TCC
APIs + Core Audio process taps + no sandbox, by design), so **Developer ID + notarization is the only
viable channel**.

## Current inventory (2026-06-15)
- Code-signing identities: only **`Apple Development: yuval3250@gmail.com` (team A6C6D257QN)** — a *dev* cert.
- **No `Developer ID Application` cert** (the one required for distribution). ← the blocker.
- `notarytool` present (1.1.2); **no** stored notarization credentials.

## Interim: `make dmg` — a LOCAL, UNSIGNED test installer (no account needed)
Until the Developer-ID pipeline above exists, **`make dmg`** (→ `scripts/make-dmg.sh`) builds a **Release**
configuration and packages it into `dist/INMeetings.dmg` — a drag-to-`/Applications` `.dmg` purely for
**install + onboarding/TCC testing**, so you can exercise the as-installed flow (Screen-Recording-after-restart,
launch-at-login behave differently from a DerivedData debug build).

- **Builds Release on purpose:** a Debug build uses Xcode's debug-dylib split (`ENABLE_DEBUG_DYLIB`) and isn't
  meant to run outside DerivedData, so it may not launch from `/Applications`. `make dmg` builds Release.
- **Not for distribution:** not notarized, not Developer-ID signed (it carries the Apple Development cert).
- On the machine that built it, the `.dmg` has no quarantine flag and opens normally. Copied to **another**
  Mac (download/AirDrop), Gatekeeper quarantines it → first launch needs **right-click → Open** (or
  `xattr -dr com.apple.quarantine "/Applications/INV Meetings.app"`).
- Usage: `make dmg` (builds Release + packages), then open `dist/INMeetings.dmg`, drag to Applications, launch
  from `/Applications`. `dist/` is git-ignored.
- This does **not** replace the Ship steps below — it's a stopgap to test the installer UX before the paid
  account lands.

### `make reset-test-data` — fresh-install state (for repeat onboarding tests)
macOS keeps per-user state that **`rm -rf` the .app + `tccutil reset` do NOT clear** — the app's preferences
(incl. the `onboarding.completed` flag, so the wizard won't re-open), recordings, model cache, and the
Keychain Google token. **`make reset-test-data`** (→ `scripts/reset-app-data.sh`) clears all of it for the
**current user** (run it in the session you're testing), with a typed-`yes` confirm. It **keeps the ~1.5 GB
model by default** (`KEEP_MODEL=0 make reset-test-data` to wipe it too). After it runs, reinstall/relaunch and
onboarding auto-opens. ⚠️ Destructive — deletes local recordings + disconnects Google for that user.

---

## Step 0 — Check whether you already have access (may save the whole thing)
1. Sign in at **<https://developer.apple.com/account>** with the Apple ID you'd use.
   - Shows an active **Apple Developer Program** membership / Team ID → already paid; skip to Step 3.
   - Free account only / can't reach Certificates → not enrolled.
2. **Ask IN Venture IT/admin** whether the firm already has an Apple Developer account (common for MDM /
   past apps). If yes, get **invited** with an **Admin** or **Account Holder** role — no new $99.

> Team `A6C6D257QN` is almost certainly a free **"Personal Team"** (free teams can't create Developer ID
> certs). Confirm at the link above.

## Step 1 — Choose entity type

| | **Individual** | **Organization** |
|---|---|---|
| Cost | $99/yr | $99/yr |
| Speed | often same day | days (D‑U‑N‑S + legal verification) |
| Needs | your Apple ID + ID verification | legal entity name, **D‑U‑N‑S number**, authority to bind IN Venture, website |
| App shows developer as | *Yuval Naor* | *IN Venture* |
| Team roles | just you | multiple, role-based |

**Recommendation:** to unblock fastest, enrol **Individual** under a **company-owned Apple ID** now;
migrate to Organization later if desired. Go **Organization** up front only if you want it "IN Venture"-
branded and have the D‑U‑N‑S ready.

> **Use a company-owned Apple ID** (e.g. `yuval@in-venture.com` or a shared `dev@in-venture.com`), **not**
> the personal gmail — the account + certs get tied to it. Enable **2-factor auth** (Apple requires it).

## Step 2 — Enrol
1. Ensure the Apple ID has 2FA on + name/address filled in.
2. Go to **<https://developer.apple.com/programs/enroll>** (or the **"Apple Developer"** app on iPhone/iPad —
   Apple often routes individual identity verification there; have a **government ID** ready).
3. Pick Individual / Organization. Organization also asks for legal entity name + **D‑U‑N‑S number**
   (free to request via Apple's D‑U‑N‑S lookup during enrollment; can take days if IN Venture isn't listed).
4. Pay **$99** (auto-renews yearly).
5. Wait for the **Welcome** email. Individual ≈ minutes–hours; Organization ≈ days.

## Step 3 — After approval (the technical half — **Claude drives this with you, ~20 min**)
1. **Create the Developer ID Application cert** — Xcode → Settings → Accounts → (team) → *Manage
   Certificates* → **+** → **Developer ID Application**. (Lands in your Keychain.)
2. **Notarization credentials** — recommended: an **App Store Connect API key** (App Store Connect →
   *Users and Access → Integrations → App Store Connect API* → generate a key with Developer access →
   download the **`.p8`** + note **Key ID** + **Issuer ID**). Alternative: an **app-specific password**
   from <https://appleid.apple.com>.
3. Store once: `xcrun notarytool store-credentials "<profile>"` (paste Key ID / Issuer ID / `.p8`, or the
   Apple ID + app-specific password + team ID).

## Step 4 — The pipeline Claude builds (not your job)
- Flip the app target to **Developer ID** signing + **hardened runtime** (`--options runtime`); keep the
  entitlements.
- `make dist`: build → **codesign** (Developer ID) → **`notarytool submit --wait`** → **`stapler staple`** →
  package a **drag-to-`/Applications` `.dmg`**.
- **Launch-at-login** (`SMAppService`) wired against the *installed* app + quiet-login (no dashboard pop).
- **Sparkle** auto-update — ✅ already built (EdDSA, account-independent; activate per "Auto-update" below).
- Install-test on a **second Mac** (clean Gatekeeper + audio-TCC grant).

## Not needed
- ❌ App Store / TestFlight (can't pass review — private TCC APIs by design)
- ❌ Apple Developer **Enterprise** Program ($299; for 100+ employees)
- ❌ Any paid CI/signing service

---
**Net:** ~$99 + one form. Individual ≈ same-day unblock; Organization ≈ a few days but "IN Venture"-branded.
When you've enrolled, ping Claude and we do Steps 3–4 together.

---

## Release hosting + auto-update (the chosen architecture)

> Added 2026-06-24. Implements the "plan now, account later" decision: the unsigned
> release path is live-ready TODAY (no Apple account); signed + Sparkle auto-update
> activates when the $99 Developer account lands.

### Architecture

| Concern | Tool | Notes |
|---|---|---|
| Binary hosting | **GitHub Releases** | one `.dmg` (unsigned now, signed+notarized later) per tag |
| Auto-update feed | **GitHub Pages** (`gh-pages` branch) | serves `appcast.xml` |
| Auto-update client | **Sparkle 2** (EdDSA) | `SPUStandardUpdaterController` in-app |
| Signatures | EdDSA via `generate_appcast` | keys generated once with `generate_keys` |

### The `release.yml` workflow (`.github/workflows/release.yml`)

Triggers on `push: tags: v*` **or** `workflow_dispatch`.

**NOW (no account needed):**
1. `brew install xcodegen` → `make gen`
2. `make dmg` → `dist/INMeetings.dmg` (unsigned Release build)
3. `softprops/action-gh-release@v2` publishes a pre-release tagged "unsigned internal build"
4. Artifact: `INMeetings.dmg`

**LATER (account-gated — activate by adding secrets):**

Each account-gated step is wrapped in `if: ${{ secrets.DEVELOPER_ID_CERT != '' }}` (or
`SPARKLE_ED_PRIVATE_KEY`). The unsigned path succeeds regardless. Steps that activate:
1. Import Developer ID cert into runner keychain
2. `codesign --options runtime` (Hardened Runtime; sign frameworks first, then the bundle — never `--deep`)
3. `notarytool submit --wait` → `stapler staple`
4. Repackage as `INMeetings-signed.dmg` + produce `INMeetings.zip` (Sparkle's download artifact)
5. `generate_appcast` (EdDSA) → `dist/appcast.xml` → push to `gh-pages` branch

### Now vs Later split at a glance

| Step | Now (no account) | Later (account + secrets) |
|---|---|---|
| Build | ✅ `make dmg` | same |
| Sign | ❌ unsigned | ✅ Developer ID + Hardened Runtime |
| Notarize | ❌ | ✅ `notarytool submit --wait` + `stapler staple` |
| GitHub Release | ✅ unsigned `.dmg` | ✅ also signed `.dmg` + `.zip` |
| Auto-update | ✅ Sparkle 2 appcast via `gh-pages` (needs the `SPARKLE_ED_PRIVATE_KEY` secret + Pages — **no account**) | same, over the signed build |
| Gatekeeper (first install) | right-click → Open | transparent |

### Auto-update (Sparkle) — DONE in the app; works WITHOUT the Apple account

> **Updated 2026-06-28.** The app-side Sparkle integration is **complete** and Sparkle's update integrity
> is **EdDSA-based, independent of Apple Developer-ID/notarization** — so auto-update works for the
> internal *unsigned* builds too. The $99 account only gates a **Gatekeeper-clean first install**, not
> updates. (Earlier this doc treated Sparkle as fully account-gated; that was over-conservative.)

**Already done in the app** (`Apps/INMeetings/…`):
- Sparkle 2 SPM dependency (`project.yml`); `SPUStandardUpdaterController` started at launch.
- "Check for Updates…" in the app menu **and** the menu-bar dropdown.
- `Info.plist`: `SUFeedURL` → `https://yuvinv.github.io/IN-meetings/appcast.xml`, `SUPublicEDKey`
  (the generated public key), `SUEnableAutomaticChecks`, `SUScheduledCheckInterval` (daily).
- EdDSA keypair generated: public key embedded; **private key exported to
  `.secrets/sparkle_ed_private_key.txt` (gitignored)**.

**To turn the update FEED on — 3 steps, NO Apple account needed:**
1. **Add the GitHub secret `SPARKLE_ED_PRIVATE_KEY`** = the contents of `.secrets/sparkle_ed_private_key.txt`
   (repo → Settings → Secrets and variables → Actions → New repository secret).
2. **Enable GitHub Pages** (repo → Settings → Pages → Source: `gh-pages` branch, `/ (root)`). The first
   release run creates the `gh-pages` branch + `appcast.xml`.
3. **Cut a release:** `make release VERSION=0.2.0`. CI builds the `.dmg` + Sparkle `.zip`, signs + publishes
   the appcast to `gh-pages`, and creates the GitHub Release. Installed apps then auto-update on next check.

> First *manual* install of an unsigned build still needs **right-click → Open** (Gatekeeper) until the
> account lands. Every *update* after that is automatic.

### What the Apple Developer account still gates (Gatekeeper only)

Only **Developer-ID signing + notarization**, for a clean first install with no Gatekeeper prompt. When it lands:

**Add these GitHub Actions secrets:**

| Secret name | What it is |
|---|---|
| `DEVELOPER_ID_CERT` | Base64-encoded Developer ID Application `.p12` |
| `DEVELOPER_ID_CERT_PW` | Password for that `.p12` |
| `AC_API_KEY` | App Store Connect API key (`.p8` contents) |
| `AC_API_KEY_ISSUER` | Issuer ID from App Store Connect |
| `AC_API_KEY_ID` | Key ID from App Store Connect |

**Flip the app target** (project.yml): `CODE_SIGN_STYLE = Manual`, `CODE_SIGN_IDENTITY = Developer ID
Application`, `ENABLE_HARDENED_RUNTIME = YES`. The release workflow's signing/notarization steps then
activate automatically (they're already authored, gated on `DEVELOPER_ID_CERT`).

### Version-bump rule (per release)

**Use `make release VERSION=0.2.0`** (from `main`). It bumps `MARKETING_VERSION` in `project.yml`, commits,
tags `v0.2.0`, and pushes — the tag fires the workflow. CI then stamps the build at tag time:
- `MARKETING_VERSION` — from the tag (`v0.2.0` → `0.2.0`); the user-visible version in Sparkle's dialog.
- `CURRENT_PROJECT_VERSION` — the **CI run number** (monotonic), the build number Sparkle compares to detect
  a newer release. (So you never hand-manage the build number; the committed `project.yml` value is just a
  local dev default.)

### Appcast template

`docs/appcast.xml` is a committed, **not-yet-served** template showing the correct Sparkle 2 feed
structure (fields: `sparkle:version` = build number, `sparkle:shortVersionString`, `enclosure` with
`url` → GitHub Releases `.zip`, `sparkle:edSignature`). `generate_appcast` replaces this automatically
when the account-gated step runs — do not hand-edit the signature field.
