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
Until the Developer-ID pipeline above exists, **`make dmg`** (→ `scripts/make-dmg.sh`) packages the current
build into `dist/INMeetings.dmg` — a drag-to-`/Applications` `.dmg` purely for **install + onboarding/TCC
testing**, so you can exercise the as-installed flow (Screen-Recording-after-restart, launch-at-login behave
differently from a DerivedData debug build).

- **Not for distribution:** not notarized, not Developer-ID signed.
- On the machine that built it, the `.dmg` has no quarantine flag and opens normally. Copied to **another**
  Mac (download/AirDrop), Gatekeeper quarantines it → first launch needs **right-click → Open** (or
  `xattr -dr com.apple.quarantine /Applications/INMeetings.app`).
- Usage: `make build-mac && make dmg`, then open `dist/INMeetings.dmg`, drag to Applications, launch from
  `/Applications`. `dist/` is git-ignored.
- This does **not** replace the Ship steps below — it's a stopgap to test the installer UX before the paid
  account lands.

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
- **Sparkle** auto-update (needs Developer ID + notarization + EdDSA keys).
- Install-test on a **second Mac** (clean Gatekeeper + audio-TCC grant).

## Not needed
- ❌ App Store / TestFlight (can't pass review — private TCC APIs by design)
- ❌ Apple Developer **Enterprise** Program ($299; for 100+ employees)
- ❌ Any paid CI/signing service

---
**Net:** ~$99 + one form. Individual ≈ same-day unblock; Organization ≈ a few days but "IN Venture"-branded.
When you've enrolled, ping Claude and we do Steps 3–4 together.
