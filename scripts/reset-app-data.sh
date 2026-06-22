#!/usr/bin/env bash
#
# Reset IN Meetings' per-user state so the next launch behaves like a fresh install — for testing the
# onboarding / TCC flow. macOS keeps this state per-user and `rm -rf`-ing the .app + `tccutil reset` do
# NOT touch it, so the wizard won't re-open (its `onboarding.completed` flag persists) and old recordings
# linger. Run this IN THE USER SESSION you're testing.
#
# Clears: TCC permissions, preferences (incl. onboarding.completed), Google tokens (Keychain), caches,
# recordings + meetings.db. KEEPS the ~1.5 GB on-device model by default so it doesn't re-download —
# set KEEP_MODEL=0 to wipe it too.
#
# Usage:  make reset-test-data           # keeps the model
#         KEEP_MODEL=0 make reset-test-data   # also deletes the 1.5 GB model
#
# ⚠️ Destructive: deletes local recordings + disconnects Google for this user. NOT for production data.

set -euo pipefail

BUNDLE="com.in-venture.in-meetings"
SUPPORT="$HOME/Library/Application Support/IN Meetings"
KEEP_MODEL="${KEEP_MODEL:-1}"

modelNote=$([ "$KEEP_MODEL" = "1" ] && echo "(keeping the ~1.5 GB model)" || echo "+ the ~1.5 GB model")
echo "Reset IN Meetings for the CURRENT user ($USER):"
echo "  • TCC permissions (Microphone, Screen & System Audio Recording)"
echo "  • preferences incl. onboarding.completed"
echo "  • Google sign-in (Keychain) + caches"
echo "  • recordings + meetings.db $modelNote"
printf "Type 'yes' to continue: "
read -r ans
[ "$ans" = "yes" ] || { echo "Aborted."; exit 1; }

# Quit the app first so it doesn't re-write prefs on the way out.
osascript -e 'tell application "INMeetings" to quit' >/dev/null 2>&1 || true
pkill -x INMeetings >/dev/null 2>&1 || true
sleep 1

tccutil reset All "$BUNDLE" >/dev/null 2>&1 || true
defaults delete "$BUNDLE" >/dev/null 2>&1 || true
killall cfprefsd >/dev/null 2>&1 || true          # flush the prefs cache, else the old flag lingers
security delete-generic-password -s "$BUNDLE.drive" >/dev/null 2>&1 || true
rm -rf "$HOME/Library/Caches/$BUNDLE"

if [ "$KEEP_MODEL" = "1" ]; then
    rm -rf "$SUPPORT/Recordings" "$SUPPORT/meetings.db"
else
    rm -rf "$SUPPORT"
fi

echo "Done. Reinstall (or relaunch) the app — onboarding will auto-open on first launch."
