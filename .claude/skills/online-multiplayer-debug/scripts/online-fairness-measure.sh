#!/usr/bin/env bash
# online-fairness-measure.sh — scrapes MG_DEBUG_QRENDER / MG_DEBUG_QTIMEOUT
# from BOTH ranked match instances' logcat buffers (see the instrumentation
# in lib/pages/modes/ranked/ranked_match_page.dart), joins them by
# roomCode+qidx, and reports per-question render-delta (A vs B) plus
# effective-time-available per client per question — the number that
# actually matters for fairness, independent of how late each client's
# Firestore snapshot for a new question arrived.
#
# Standalone script (explicit serials, no auto-detect) — same discipline as
# online-chaos.sh's functions.
#
# USAGE
#   bash online-fairness-measure.sh <serialA> <serialB> [waitSeconds]
#
#   <serialA> <serialB>  ANDROID_SERIAL values printed by online-duo-up.sh
#                        (e.g. emulator-5554 emulator-5556).
#   [waitSeconds]        Optional: sleep this long before scraping, to let a
#                        match in progress produce more data first. Default 0
#                        (scrape immediately — use this AFTER a match/several
#                        matches have already run to completion).
#
# SCENARIO
#   Run with BOTH instances set to `DebugRankedAutoplay.mode = lose` (neither
#   auto-answers) so EVERY question runs to its full timeout on both sides —
#   this gives a clean, complete effective-time measurement for every
#   question instead of only the ones nobody happened to answer early. See
#   SKILL.md's "Fairness measurement" section for the exact walkthrough.
#
# OUTPUT
#   One line per (roomCode, qidx) pair seen on BOTH instances, plus a
#   min/median/p90/max summary for: render-delta (|A-B|), A's effective
#   time, B's effective time.
#
# LIMITATIONS
#   - Only pairs a question if BOTH clients logged MG_DEBUG_QRENDER for it
#     (a client that never reached that question — e.g. it disconnected
#     first — is silently excluded from that row, not fabricated).
#   - Effective-time is timeoutWallMs - renderWallMs; a question the player
#     answered instead of timing out has no MG_DEBUG_QTIMEOUT line and is
#     reported as "answered" (no effective-time number) — use the
#     lose/lose autoplay scenario above to avoid this.
#   - Requires the dev-flavor build under test to include the
#     MG_DEBUG_QRENDER/MG_DEBUG_QTIMEOUT instrumentation (this script does
#     not check the build for it — a build predating the instrumentation
#     will just produce empty output, not an error).

set -euo pipefail

usage() {
  cat >&2 <<'USAGE'
usage: online-fairness-measure.sh <serialA> <serialB> [waitSeconds]

  Scrapes MG_DEBUG_QRENDER/MG_DEBUG_QTIMEOUT from both ranked match
  instances' logcat buffers, joins by roomCode+qidx, and prints per-question
  render-delta (A-B) + effective-time-available per client, plus a
  min/median/p90/max summary. Run AFTER (or well into) a ranked match with
  both instances on DebugRankedAutoplay.mode=lose so every question times
  out on both sides (see SKILL.md "Fairness measurement").
USAGE
  exit 1
}

SERIAL_A="${1:-}"
SERIAL_B="${2:-}"
WAIT_SECONDS="${3:-0}"
[ -n "$SERIAL_A" ] && [ -n "$SERIAL_B" ] || usage

if [[ "$WAIT_SECONDS" =~ ^[0-9]+$ ]] && [ "$WAIT_SECONDS" -gt 0 ]; then
  echo "Waiting ${WAIT_SECONDS}s before scraping logcat..." >&2
  sleep "$WAIT_SECONDS"
fi

WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT

# ── Scrape + normalize ──────────────────────────────────────────────────────
# Each MG_DEBUG_QRENDER/QTIMEOUT line is "TAG key=val key=val ...". Extract
# the raw lines first (grep, tolerant of logcat's leading timestamp/pid
# columns), then normalize each into a flat "roomCode qidx wallMs anchorMs
# remainingMs" (QTIMEOUT lines leave anchorMs/remainingMs empty) with awk.
# Dedup by (roomCode,qidx): a client logs each qidx exactly once by
# construction (_lastLoggedRenderQidx guard client-side), but the logcat
# buffer can still hold leftovers from an earlier match — keep the FIRST
# occurrence (chronological, since `logcat -d` dumps in order) per key.
scrape() {
  local serial="$1" tag="$2" out="$3"
  adb -s "$serial" logcat -d 2>/dev/null \
    | grep -oE "${tag}"' roomCode=[A-Za-z0-9_-]+ qidx=[0-9]+ wallMs=[0-9]+( anchorMs=[0-9]+ remainingMs=[0-9]+)?' \
    | awk -v tag="$tag" '
        {
          roomCode=""; qidx=""; wallMs=""; anchorMs=""; remainingMs="";
          for (i = 1; i <= NF; i++) {
            n = split($i, kv, "=");
            if (n != 2) continue;
            if (kv[1] == "roomCode") roomCode = kv[2];
            else if (kv[1] == "qidx") qidx = kv[2];
            else if (kv[1] == "wallMs") wallMs = kv[2];
            else if (kv[1] == "anchorMs") anchorMs = kv[2];
            else if (kv[1] == "remainingMs") remainingMs = kv[2];
          }
          key = roomCode "_" qidx;
          if (key in seen) next;
          seen[key] = 1;
          print roomCode, qidx, wallMs, anchorMs, remainingMs;
        }
      ' > "$out"
}

scrape "$SERIAL_A" MG_DEBUG_QRENDER  "$WORKDIR/a_render.tsv"
scrape "$SERIAL_A" MG_DEBUG_QTIMEOUT "$WORKDIR/a_timeout.tsv"
scrape "$SERIAL_B" MG_DEBUG_QRENDER  "$WORKDIR/b_render.tsv"
scrape "$SERIAL_B" MG_DEBUG_QTIMEOUT "$WORKDIR/b_timeout.tsv"

for f in a_render a_timeout b_render b_timeout; do
  n=$(wc -l < "$WORKDIR/$f.tsv" | tr -d ' ')
  echo "  scraped $f: $n line(s)" >&2
done

if [ ! -s "$WORKDIR/a_render.tsv" ] || [ ! -s "$WORKDIR/b_render.tsv" ]; then
  echo "" >&2
  echo "No MG_DEBUG_QRENDER lines found on one or both instances." >&2
  echo "  - Is this a dev-flavor build WITH the instrumentation (this branch)?" >&2
  echo "  - Did a ranked match actually reach the question phase on both sides?" >&2
  echo "  - Logcat buffer rotated past the lines? Scrape sooner after the match." >&2
  exit 2
fi

# ── Join by (roomCode, qidx) ────────────────────────────────────────────────
# A key present in a_render AND b_render is a question BOTH clients reached.
JOIN_KEYS="$WORKDIR/join_keys.txt"
awk '{print $1"_"$2}' "$WORKDIR/a_render.tsv" > "$WORKDIR/a_keys.txt"
awk '{print $1"_"$2}' "$WORKDIR/b_render.tsv" > "$WORKDIR/b_keys.txt"
comm -12 <(sort "$WORKDIR/a_keys.txt") <(sort "$WORKDIR/b_keys.txt") > "$JOIN_KEYS"

if [ ! -s "$JOIN_KEYS" ]; then
  echo "No (roomCode, qidx) pair was rendered on BOTH instances — nothing to join." >&2
  exit 2
fi

lookup() {
  # lookup <file.tsv> <key> <field#> — field# is 1-based over the printed
  # "roomCode qidx wallMs anchorMs remainingMs" columns.
  local file="$1" key="$2" field="$3"
  awk -v key="$key" -v f="$field" '$1"_"$2 == key { print $f; exit }' "$file"
}

RESULTS="$WORKDIR/results.tsv"
: > "$RESULTS"

while IFS= read -r key; do
  a_render_wall=$(lookup "$WORKDIR/a_render.tsv" "$key" 3)
  b_render_wall=$(lookup "$WORKDIR/b_render.tsv" "$key" 3)
  a_timeout_wall=$(lookup "$WORKDIR/a_timeout.tsv" "$key" 3)
  b_timeout_wall=$(lookup "$WORKDIR/b_timeout.tsv" "$key" 3)

  render_delta=$(( a_render_wall - b_render_wall ))

  if [ -n "$a_timeout_wall" ]; then
    a_effective=$(( a_timeout_wall - a_render_wall ))
  else
    a_effective="answered"
  fi
  if [ -n "$b_timeout_wall" ]; then
    b_effective=$(( b_timeout_wall - b_render_wall ))
  else
    b_effective="answered"
  fi

  roomCode="${key%_*}"
  qidx="${key##*_}"
  printf '%s\t%s\t%s\t%s\t%s\n' "$roomCode" "$qidx" "$render_delta" "$a_effective" "$b_effective" >> "$RESULTS"
done < "$JOIN_KEYS"

echo ""
echo "roomCode   qidx  renderDelta(A-B,ms)  effectiveA(ms)  effectiveB(ms)"
sort -k1,1 -k2,2n "$RESULTS" | while IFS=$'\t' read -r roomCode qidx delta effA effB; do
  printf '%-10s %4s  %19s  %14s  %14s\n' "$roomCode" "$qidx" "$delta" "$effA" "$effB"
done

# ── Distribution summary (min/median/p90/max) ───────────────────────────────
stats() {
  # Reads one number per line on stdin, prints "min=.. median=.. p90=.. max=.."
  # (or "no data" if empty / all non-numeric).
  local vals
  vals=$(grep -E '^-?[0-9]+$' || true)
  if [ -z "$vals" ]; then
    echo "no data"
    return
  fi
  echo "$vals" | sort -n | awk '
    { a[NR] = $1 }
    END {
      n = NR;
      min = a[1]; max = a[n];
      mid = int((n + 1) / 2);
      if (n % 2 == 1) median = a[mid]; else median = (a[mid] + a[mid + 1]) / 2;
      p90idx = int(0.9 * (n - 1)) + 1; # 1-based, nearest-rank
      if (p90idx > n) p90idx = n;
      p90 = a[p90idx];
      printf "min=%s median=%s p90=%s max=%s (n=%d)", min, median, p90, max, n;
    }'
  echo ""
}

echo ""
echo "── Render-delta |A-B| (ms), fairness gap between clients ──"
awk -F'\t' '{ d = $3; if (d < 0) d = -d; print d }' "$RESULTS" | stats

echo ""
echo "── Effective time A (ms), only questions A timed out on ──"
awk -F'\t' '{ print $4 }' "$RESULTS" | stats

echo ""
echo "── Effective time B (ms), only questions B timed out on ──"
awk -F'\t' '{ print $5 }' "$RESULTS" | stats

echo ""
echo "Reminder: server-anchored design means effective time is EXPECTED to be"
echo "< 10000ms whenever a client's snapshot for the new question arrived late"
echo "— see the anchoring audit in CLAUDE.md / this task's build report before"
echo "treating any single number here as a bug on its own."
