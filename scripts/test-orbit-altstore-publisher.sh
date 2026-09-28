#!/usr/bin/env bash
set -euo pipefail

# The release publisher is staged outside this checkout by the existing
# release workflow. Keep this contract test next to the iOS source so a future
# publication cannot silently regain backend deployment side effects.
publisher="${ORBIT_ALTSTORE_PUBLISHER:-/home/ubuntu/Documents/Codex/2026-08-27/orbit-voice-ios-release-evidence/.publisher-stage/orbit-publish-altstore}"
[[ -f "$publisher" ]] || { echo "publisher not found: $publisher" >&2; exit 1; }

bash -n "$publisher"

if grep -Eq 'docker[[:space:]]+(compose[[:space:]]+)?(build|up|restart)|docker[[:space:]]+build|docker[[:space:]]+restart' "$publisher"; then
  echo "publisher contains a forbidden Docker deployment command" >&2
  exit 1
fi

grep -Fq 'mv -f "$tmp_ipa" "$target_path"' "$publisher"
grep -Fq 'mv -f "$tmp_feed" "$live_feed"' "$publisher"
grep -Fq 'orbit-realtime-web' "$publisher"

echo "altstore publisher safety contract: pass"
