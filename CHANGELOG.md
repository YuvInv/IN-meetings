# Changelog

All notable changes to INV Meetings. Format loosely follows [Keep a Changelog](https://keepachangelog.com).
The user-visible version is `MARKETING_VERSION`; the Sparkle build number is the CI run number.

To cut a release: `make release VERSION=x.y.z` (from `main`) → the `v*` tag triggers the GitHub release
workflow, which builds the `.dmg`, signs + publishes the Sparkle appcast, and creates the GitHub Release.

## [Unreleased]

### Added
- **In-app auto-update (Sparkle 2).** "Check for Updates…" in the app menu and the menu-bar dropdown;
  automatic daily background checks. Update integrity is EdDSA-signed, so updates work for the internal
  unsigned builds too — the Apple Developer account only gates a Gatekeeper-clean *first* install.
- **Release pipeline.** `make release VERSION=x.y.z` bumps the version, tags, and pushes; CI builds the
  `.dmg`, packages the Sparkle `.zip`, generates the signed appcast (→ `gh-pages`), and publishes a GitHub
  Release. Version is stamped from the git tag; the build number is the CI run number.
- **v1 "must-have" features** (merged via #23): user notifications (transcript/summary ready, failures) with
  tap-to-open; meeting delete + sort + live transcription progress; full-text transcript search (Hebrew-
  capable, jump-to-moment); Markdown + PDF export (RTL); inline transcript editing + global find-and-replace
  that teaches the correction vocabulary; structured action-items checklists; a recording HUD with per-track
  level meters and pause; a layered macOS 26 app icon.

### Fixed
- `.gitignore` patterns had trailing inline `#` comments (unsupported by git), so `dist/` was never actually
  ignored. Comments moved to their own lines.

<!-- Older history lives in git log + DECISIONS.md. -->
