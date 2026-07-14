#!/usr/bin/env bash
# emulator-pool.sh — atomic, self-healing Android emulator port allocation
# for parallel agents.
#
# WHY THIS EXISTS
#   Multiple Claude agents/sessions run in parallel on this machine. Each needs an
#   Android emulator, but they collided: the naive "check `adb get-state`, pick the
#   first free port" logic is a TOCTOU race. This library makes the claim ATOMIC
#   and holds it for the whole agent session — and, just as important, keeps the
#   WAITING side honest so dead/stale waiters can't starve a live agent.
#
#   History of the failure modes this file has had to kill:
#     v1  : the emulator + a dumb `sleep 7200` keeper survived agent death forever,
#           so a dead agent pinned a port until manual reaping (pool shrank 3→0).
#     v2  : added a renewable lease so a port self-heals when its agent goes quiet.
#     v2.1: judge a port by REAL USE (is a flutter/dart/adb process attached?), not
#           by whether some keeper process is merely alive (a `sleep` keeper is not
#           proof of use), and not by CPU% (an idle headless emulator burns more
#           CPU than an active one).
#     v2.2: fix the WAITING side. `mg_claim_port` used to spin forever; when it
#           outlived the Bash-tool timeout the loop was orphaned but kept running,
#           the agent relaunched, and N stale loops piled up fighting for 3 ports.
#           A stale/superseded loop could WIN a port and never consume it. Now each
#           claim loop is tied to its `claude` session: if the session dies the loop
#           self-abandons, a new claim from a session supersedes that session's old
#           loops, dead-session loops are reaped, and the wait is time-bounded.
#
# NOTE: a manual 'emulator …' boot outside mg_boot_avd/mg_keepalive_start gets reaped by the pool keeper — always boot via the pool helpers. <!-- trigger: debugger emulator reaped, 2026-07-13 -->
# NOTE: check disk space (df -h) before booting an AVD — a near-full root disk (>95%) kills qemu mid-session. <!-- trigger: inspector emulator died at 98% disk, 2026-07-13 -->
#
# THE MODEL
#   - Exactly 3 ports: 5554, 5556, 5558  → at most 3 parallel agents.
#     RAM ceiling, not arbitrary: each headless emulator eats 2–4 GB RSS and the
#     machine already swaps at 3. Do NOT add ports without RAM — a swapping
#     emulator is slower than waiting for a free one.
#   - An agent claims ONE port and keeps it for its whole session, cycling AVDs
#     on it: phone → (kill, boot tablet7) → (kill, boot tablet10) → release.
#   - If all 3 ports are busy with LIVE sessions, claim polls every 8 s (up to
#     MG_CLAIM_TIMEOUT) — but dead/idle holders and stale waiters are reaped fast.
#
# HOW "IS THIS PORT FREE?" IS DECIDED  (mg__classify_port)
#   ACTIVE (never touch) if ANY: a flutter/dart process is attached to
#     emulator-<port> AND it is not an orphaned zombie (keeper alive, lease younger
#     than MG_KEEPER_MAX, or a fresh flutter log); OR a tagged v2 keeper is alive
#     with a fresh lease; OR the lease was renewed recently; OR
#     /tmp/flutter-<port>.log is fresh. A leaked `flutter run` whose session died
#     (dead keeper + ancient lease + stale log) is RECLAIMABLE, not active.
#   FREE if no emulator and no keeper.
#   RECLAIMABLE (owner provably gone) if an emulator/keeper lingers but nothing
#     uses it and the port was pool-managed: stale v2 zombie, dead-keeper orphan,
#     idle legacy `sleep` keeper, or a port claimed but never booted (boot grace).
#   A foreign emulator (no pool marker) is left alone — never killed.
#
# HOW THE WAITING QUEUE STAYS HONEST  (mg_claim_port / mg__reap_claimers)
#   Every claim loop registers /tmp/mg-emu-locks/waiters/<pid> = its session id
#   (nearest `claude` ancestor pid) and removes it on exit. A claim, at start and
#   each poll, reaps: (a) registered loops whose PID is dead, (b) loops whose
#   SESSION is dead (orphaned to init), (c) older loops of its OWN session (the
#   new claim supersedes them). A loop also self-abandons the instant its own
#   session dies. So "old stuff with no value" can no longer sit in the queue and
#   steal a port.  Inspect with mg_emu_queue.
#
# USAGE
#   source "$(git rev-parse --show-toplevel)/.claude/skills/shared/emulator-pool.sh"
#   mg_claim_port                      # blocks (bounded) until it owns one port
#   mg_boot_avd mission_geo_phone      # boots on $MG_PORT, read-only, waits for boot
#   ... drive emulator-$MG_PORT ($ANDROID_SERIAL is exported) ...
#   mg_keepalive                       # renew the lease during a long burst
#   mg_swap_avd mission_geo_tablet7    # kill phone + boot tablet7 on the SAME port
#   mg_release_port                    # kill emulator + drop the lock
#
#   mg_emu_status                      # per-port: free / active / RECLAIMABLE
#   mg_emu_queue                       # who is waiting + is their session alive
#   mg_emu_doctor                      # reclaim leaked ports + reap stale waiters
#   mg_emu_reset                       # PANIC: kill all 3 ports' emulators + keepers
#
# mg_claim_port may return non-zero (POOL_BUSY, or "session gone"). Callers should
# treat a non-zero result as "retry later" and simply call it again — do NOT
# background it and relaunch, that is what created the pile-up. Run it with a long
# Bash-tool timeout (e.g. 600000 ms) so the tool itself doesn't orphan the loop.
#
# Each Bash tool call runs in a FRESH shell, so re-`source` this file (and re-set
# MG_PORT) in any later call that uses mg_swap_avd / mg_keepalive / mg_release_port.
# Concretely: `MG_PORT=5556 mg_release_port` (env vars from mg_claim_port don't
# persist across calls) — mg_release_port now REFUSES (loud stderr + return 1)
# when MG_PORT is unset, instead of silently no-op'ing as it used to.
# <!-- trigger: phantom port release + silent emulator death, inspector, 2026-07-11 -->
#
# For driver-less workflows (no flutter/dart/gradle attached — screenshot loops,
# one-shot adb), call mg_boot_avd AND mg_keepalive_start in the SAME Bash call:
# splitting them leaves a gap with no active driver where the TTL reaper
# (MG_LEASE_TTL, 180s) can kill the emulator before keepalive starts renewing it.
# <!-- trigger: phantom port release + silent emulator death, inspector, 2026-07-11 -->

# Config — all overridable from the environment before sourcing (for an isolated
# test instance, or to retune). Defaults below are the production values.
MG_ANDROID_HOME="${ANDROID_HOME:-$HOME/Android/Sdk}"
: "${MG_EMULATOR_BIN:=$MG_ANDROID_HOME/emulator/emulator}"
: "${MG_ADB:=$(command -v adb 2>/dev/null || echo "$MG_ANDROID_HOME/platform-tools/adb")}"
# GPU mode. Default `host` (use the machine's real GPU): the software renderer
# `swiftshader_indirect` composes a 100% black framebuffer in this multi-instance
# setup (memory feedback_emulator_gpu_host_multi_contention) — every session lost
# time rebooting to fix it. Override with MG_GPU=swiftshader_indirect only for a
# truly headless host with no GPU/DISPLAY (e.g. CI).
: "${MG_GPU:=host}"
[ -n "${MG_PORTS+x}" ] || MG_PORTS=(5554 5556 5558)
: "${MG_LOCK_DIR:=/tmp/mg-emu-locks}"
MG_WAITERS_DIR="$MG_LOCK_DIR/waiters"
MG_WAIT_SECONDS="${MG_WAIT_SECONDS:-8}"             # responsive poll between sweeps
MG_CLAIM_TIMEOUT="${MG_CLAIM_TIMEOUT:-1800}"        # hard cap on one claim wait
MG_LEASE_TTL="${MG_LEASE_TTL:-180}"                 # 3 min no renewal ⇒ presumed dead (keeper auto-renews while a flutter/dart is attached, so an active `flutter run` never trips this)
MG_BOOT_GRACE="${MG_BOOT_GRACE:-300}"               # claimed but no emulator after this ⇒ abandoned claim
MG_ACTIVE_LOG_WINDOW="${MG_ACTIVE_LOG_WINDOW:-300}" # flutter log fresh within 5 min ⇒ active
MG_KEEPER_CHECK="${MG_KEEPER_CHECK:-30}"            # keeper re-checks the lease every 30 s
MG_KEEPER_MAX="${MG_KEEPER_MAX:-14400}"             # 4 h absolute cap, belt-and-suspenders

MG_PORT=""   # set by mg_claim_port

# ============================ zombie reaping =================================

# Force-reap any qemu/emulator process on a given port, even when adb can't
# reach it (i.e. the emulator has crashed but its qemu process is still alive,
# consuming ~3 GB of RAM).
#
# Safety note on the pkill-suicide trap (memory feedback_windowed_emulator_vulkan_off):
#   We identify qemu PIDs by argv, but NEVER use `pkill -f` on a broad pattern —
#   that could match our own shell process or unrelated scripts whose argv contains
#   the same port number. Instead we use `pgrep` to collect candidate PIDs, then
#   verify each one against /proc/<pid>/comm to confirm it is actually a qemu/
#   emulator binary before sending any signal. We also always exclude $$ (this
#   script's own PID) from the kill set.
#
# Returns 0 always (best-effort; the emulator is likely gone or was already dead).
mg__kill_port_qemu() {
  local port="$1"
  # Step 1: try the graceful path first (works only if adb can still talk to it).
  # `|| true`: on a freshly-claimed/free port there is no device to talk to yet,
  # so this returns non-zero — expected, not an error. Without the guard, a
  # caller running under `set -e` (e.g. a harness script) would abort right
  # here instead of falling through to steps 2-3, breaking this function's own
  # documented contract ("Returns 0 always").
  "$MG_ADB" -s "emulator-$port" emu kill >/dev/null 2>&1 || true

  # Step 2: collect candidate PIDs whose argv mentions the port number.
  local candidates; candidates=$(pgrep -f -- "-port $port" 2>/dev/null || true)
  local pid comm killed=0
  for pid in $candidates; do
    # Exclude ourselves (the running shell).
    [ "$pid" = "$$" ] && continue
    # Verify the process is actually a qemu/emulator binary — not, say, this
    # script itself or an unrelated process that happens to mention the port.
    comm=$(command cat "/proc/$pid/comm" 2>/dev/null || true)
    case "$comm" in
      qemu-system*|emulator*|emulator64*) ;;
      *) continue ;;
    esac
    kill "$pid" 2>/dev/null && killed=$((killed + 1))
  done

  # Step 3: wait (bounded, ~15 s) for every killed process to actually exit.
  if [ "$killed" -gt 0 ]; then
    local waited=0
    while [ "$waited" -lt 15 ]; do
      local still=0
      for pid in $candidates; do
        [ "$pid" = "$$" ] && continue
        comm=$(command cat "/proc/$pid/comm" 2>/dev/null || true)
        case "$comm" in qemu-system*|emulator*|emulator64*) still=$((still + 1)) ;; esac
      done
      [ "$still" -eq 0 ] && break
      sleep 1; waited=$((waited + 1))
    done
  fi
  return 0
}

# ============================ RAM preflight ==================================

# Minimum MemAvailable (kB) before we allow a new emulator boot.
# Each qemu guest eats 2-4 GB; this gate is a hard floor, not a guarantee.
MG_MIN_RAM_MB="${MG_MIN_RAM_MB:-3000}"

# Print MemAvailable in MB. Returns 0 if readable, 1 on failure.
mg__mem_available_mb() {
  local kb; kb=$(awk '/^MemAvailable:/{print $2; exit}' /proc/meminfo 2>/dev/null)
  [ -n "$kb" ] && echo $(( kb / 1024 )) || { echo 0; return 1; }
}

# Return 0 if there is enough RAM to safely boot another emulator; 1 otherwise
# (with an error message explaining the shortfall).
mg__ram_preflight() {
  local avail; avail=$(mg__mem_available_mb)
  if [ "$avail" -lt "$MG_MIN_RAM_MB" ]; then
    echo "POOL_LOW_RAM: only ${avail} MB available, need ~${MG_MIN_RAM_MB} MB/emulator — free RAM or wait for a running emulator to finish." >&2
    return 1
  fi
  return 0
}

# ============================ process / session helpers ======================

# Age (seconds) of a running pid, from its /proc dir; 0 if gone.
mg__proc_age() {
  local s; s=$(stat -c %Y "/proc/$1" 2>/dev/null || echo 0)
  [ "$s" -gt 0 ] && echo $(( $(date +%s) - s )) || echo 0
}

# Echo the nearest ancestor 'claude' pid (the owning session); empty if the
# parent chain reaches init/0 without finding one (⇒ session is dead/orphaned).
mg__owner_of() {
  local pid="$1" c
  while [ -n "$pid" ] && [ "$pid" != "0" ] && [ "$pid" != "1" ] && [ -d "/proc/$pid" ]; do
    c=$(command cat "/proc/$pid/comm" 2>/dev/null)
    [ "$c" = "claude" ] && { echo "$pid"; return 0; }
    pid=$(command awk '/^PPid:/{print $2; exit}' "/proc/$pid/status" 2>/dev/null)
  done
  return 1
}

# Reap stale claim loops. $1 = my pid (excluded), $2 = my owner session pid.
# Operates ONLY on the waiter registry, so it never mistakes a comment mention
# of "mg_claim_port" for a real claim loop.
mg__reap_claimers() {
  local me="$1" my_owner="$2" f pid owner
  [ -d "$MG_WAITERS_DIR" ] || return 0
  for f in "$MG_WAITERS_DIR"/*; do
    [ -e "$f" ] || continue
    pid=${f##*/}
    [ "$pid" = "$me" ] && continue
    if ! kill -0 "$pid" 2>/dev/null; then rm -f "$f"; continue; fi      # loop already gone
    owner=$(command cat "$f" 2>/dev/null)
    if [ -n "$owner" ] && [ "$owner" != "none" ] && ! kill -0 "$owner" 2>/dev/null; then
      kill "$pid" 2>/dev/null; rm -f "$f"; continue                      # session dead ⇒ zombie waiter
    fi
    if [ -n "$my_owner" ] && [ "$my_owner" != "none" ] && [ "$owner" = "$my_owner" ]; then
      kill "$pid" 2>/dev/null; rm -f "$f"                                # superseded same-session loop
    fi
  done
}

# ============================ lease / usage helpers ==========================

mg__lease_age() {
  local leasef="$MG_LOCK_DIR/$1.lease" lm=0
  [ -f "$leasef" ] && lm=$(stat -c %Y "$leasef" 2>/dev/null || echo 0)
  [ "$lm" -gt 0 ] && echo $(( $(date +%s) - lm )) || echo 999999
}

# Is a driver (flutter run / gradle) process attached to emulator-<port>?
# ALLOWLIST the driver only: flutter run is a `dart` process (comm "dart" or
# "dart:flutter_to"), gradle is `java`. Deliberately NOT plain `adb`: the pool
# itself spawns short-lived `adb -s emulator-<port> get-state` probes whose argv
# contains "emulator-<port>"; counting those would make the pool mistake its own
# probes for a live session and refuse to reclaim a dead port.
#
# ONE exception: a persistent `adb -s emulator-<port> logcat` attachment DOES
# count. Unlike get-state (exits in milliseconds), logcat streams and stays
# attached for as long as its owner wants — a harness with no flutter/dart/java
# driver (build-APK + `am start` + one-shot adb calls, e.g. online-duo-up.sh)
# arms one of these per claimed serial specifically so a port stays "in use"
# across a multi-agent handoff (builder boots → hands off to an inspector
# session that only issues one-shot adb) without depending on any particular
# session's liveness. Distinguished from get-state by inspecting the full
# cmdline (not just comm, which is "adb" either way) for "logcat".
mg__driver_attached() {
  local p="$1" pid comm cmdline
  for pid in $(pgrep -f "emulator-$p" 2>/dev/null); do
    comm=$(command cat "/proc/$pid/comm" 2>/dev/null)
    case "$comm" in
      dart*|flutter*|java|gradle*) return 0 ;;
      adb)
        cmdline=$(command tr '\0' ' ' < "/proc/$pid/cmdline" 2>/dev/null)
        case "$cmdline" in *logcat*) return 0 ;; esac
        ;;
    esac
  done
  return 1
}

# Has flutter written to /tmp/flutter-<port>.log within the active window? A fresh
# log is proof a session is working RIGHT NOW (independent of lease/keeper state).
mg__log_fresh() {
  local p="$1" lg="/tmp/flutter-$p.log" m
  [ -f "$lg" ] || return 1
  m=$(stat -c %Y "$lg" 2>/dev/null || echo 0)
  [ "$m" -gt 0 ] && [ $(( $(date +%s) - m )) -lt "$MG_ACTIVE_LOG_WINDOW" ]
}

# Any "real use" signal at all: a driver attached OR a fresh flutter log.
mg__emu_active_session() {
  local p="$1"
  mg__driver_attached "$p" && return 0
  mg__log_fresh "$p"
}

# Real use that is NOT an orphaned (dead-session) zombie. A leaked `flutter run`
# keeps its `dart` process attached to emulator-<port> for hours after its owning
# session died (reparented to init) — mg__driver_attached alone cannot tell that
# apart from a live run, so a zombie would pin a pool port forever (the v1 failure
# mode, in disguise: 2026-05-25 immich-flutter-on-5554 incident). A GENUINELY live
# claim always leaves a trail the orphan cannot fake:
#   - a fresh flutter log (working right now), OR
#   - a live keeper (it renews the lease every MG_KEEPER_CHECK while attached), OR
#   - a lease younger than the keeper's own max lifetime (MG_KEEPER_MAX) — past
#     that even a renewing keeper would have given up, so an attached driver beyond
#     it is provably orphaned.
mg__live_attached() {
  local p="$1"
  mg__log_fresh "$p" && return 0
  mg__driver_attached "$p" || return 1
  local kpf="$MG_LOCK_DIR/$p.keeperpid" kp keeper_alive=0
  if [ -f "$kpf" ]; then
    kp=$(<"$kpf"); kp="${kp//[!0-9]/}"
    [ -n "$kp" ] && kill -0 "$kp" 2>/dev/null && keeper_alive=1
  fi
  [ "$keeper_alive" -eq 1 ] && return 0
  [ "$(mg__lease_age "$p")" -lt "$MG_KEEPER_MAX" ] && return 0
  return 1
}

# Classify a port. Echoes a reason. return 0 = RECLAIMABLE | 1 = busy/active | 2 = free
mg__classify_port() {
  local p="$1"
  local kpf="$MG_LOCK_DIR/$p.keeperpid" ownedf="$MG_LOCK_DIR/$p.owned"
  # Keeper liveness only — no grep on /proc (the user's shell may define `grep`
  # as a function, which would abort us). "Fresh lease ⇒ active" below makes the
  # v1-vs-v2 keeper distinction unnecessary: a working session keeps its lease
  # fresh (explicitly or via the keeper's attachment-renewal); an idle/legacy
  # keeper has a stale-or-absent lease and is reclaimable.
  local keeper_alive=0 kp=""
  if [ -f "$kpf" ]; then
    kp=$(<"$kpf"); kp="${kp//[!0-9]/}"
    [ -n "$kp" ] && kill -0 "$kp" 2>/dev/null && keeper_alive=1
  fi
  local emu_alive=0
  "$MG_ADB" -s "emulator-$p" get-state >/dev/null 2>&1 && emu_alive=1
  local had_marker=0
  { [ -f "$ownedf" ] || [ -f "$kpf" ]; } && had_marker=1
  local age; age=$(mg__lease_age "$p")
  local active=0
  mg__live_attached "$p" && active=1

  # 1. A LIVE driver / fresh log (NOT an orphaned zombie) ⇒ active, never touch.
  if [ "$active" -eq 1 ]; then echo "active (flutter/dart/adb attached)"; return 1; fi
  # 2. Held by a keeper but no emulator for longer than the boot grace ⇒ a
  #    claim that was won (perhaps by a superseded loop) and never used.
  if [ "$keeper_alive" -eq 1 ] && [ "$emu_alive" -eq 0 ] && [ "$age" -ge "$MG_BOOT_GRACE" ]; then
    echo "RECLAIMABLE — held but no emulator for ${age}s"; return 0
  fi
  # 3. Fresh lease ⇒ a live session (renewing) ⇒ active.
  if [ "$age" -lt "$MG_LEASE_TTL" ]; then echo "active (lease ${age}s ago)"; return 1; fi
  # 4. Nothing alive at all ⇒ free.
  if [ "$emu_alive" -eq 0 ] && [ "$keeper_alive" -eq 0 ]; then echo "free"; return 2; fi
  # 5. Pool-managed but stale (zombie keeper / idle legacy keeper / orphan emu).
  if [ "$had_marker" -eq 1 ]; then echo "RECLAIMABLE — stale, no active session (lease ${age}s ago)"; return 0; fi
  # 6. An emulator we never booted ⇒ foreign, leave alone.
  echo "foreign emulator (not pool-managed) — left alone"; return 1
}

# Evict a port's owner (keeper + emulator) and clear its markers.
mg__reclaim() {
  local p="$1" kpf="$MG_LOCK_DIR/$p.keeperpid" i kp
  kp=$(command cat "$kpf" 2>/dev/null)
  if [ -n "$kp" ]; then
    # `|| true`: the keeper may already be dead (that's often WHY this port is
    # reclaimable) — kill failing here is expected, not an error. Bare under
    # `set -e` this would otherwise abort a caller mid-reclaim.
    kill "$kp" 2>/dev/null || true
    # Wait for the keeper to actually die — it holds the flock on its fd 9, which
    # is only released when the process exits. Returning before it dies would make
    # the immediate re-flock fail and the claimer skip a port it just freed.
    for i in $(seq 1 30); do kill -0 "$kp" 2>/dev/null || break; sleep 0.1; done
  fi
  # `|| true`: no live device to kill is the common case for a reclaimable
  # port — same `set -e` safety as above.
  "$MG_ADB" -s "emulator-$p" emu kill >/dev/null 2>&1 || true
  for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15; do
    "$MG_ADB" -s "emulator-$p" get-state >/dev/null 2>&1 || break
    sleep 1
  done
  # NEVER remove the .lock file: flock coordinates on the file's INODE, so an
  # rm+recreate by two racing contenders yields two different inodes and both
  # would "win" the flock → mutual-exclusion break (double-booked port). The
  # lock file is a permanent 0-byte anchor; only the lease/owned/keeperpid go.
  rm -f "$kpf" "$MG_LOCK_DIR/$p.lease" "$MG_LOCK_DIR/$p.owned"
}

# Spawn the detached keeper that holds the flock + watches the lease.
# Echoes the keeper pid if it acquired the flock, nothing otherwise.
mg__spawn_keeper() {
  local p="$1" mk="$2"
  local lf="$MG_LOCK_DIR/$p.lock"
  local leasef="$MG_LOCK_DIR/$p.lease" ownedf="$MG_LOCK_DIR/$p.owned" kpf="$MG_LOCK_DIR/$p.keeperpid"
  nohup bash -c '
    p="$1"; lf="$2"; mk="$3"; leasef="$4"; ownedf="$5"; kpf="$6"
    adb="$7"; check="$8"; leasettl="$9"; maxttl="${10}"
    exec 9>"$lf"
    flock -n 9 || exit 1
    touch "$mk" "$leasef"
    start=$(date +%s)
    while :; do
      sleep "$check"
      now=$(date +%s)
      [ $((now - start)) -ge "$maxttl" ] && break
      lm=0; [ -f "$leasef" ] && lm=$(stat -c %Y "$leasef" 2>/dev/null || echo 0)
      if [ $((now - lm)) -ge "$leasettl" ]; then
        # Stale lease. Before reclaiming, check for a live flutter/dart/java/
        # gradle driver, OR a persistent `adb ... logcat` attachment (see
        # mg__driver_attached'"'"'s doc comment — distinguished from the pool'"'"'s own
        # short-lived get-state probes by cmdline, not just comm) attached to
        # this emulator: if the session is demonstrably working it just forgot
        # to keepalive — renew the lease ourselves and keep holding.
        att=0
        for q in $(pgrep -f "emulator-$p" 2>/dev/null); do
          cc=$(command cat "/proc/$q/comm" 2>/dev/null)
          case "$cc" in
            dart*|flutter*|java|gradle*) att=1; break ;;
            adb)
              qcmd=$(command tr '"'"'\0'"'"' '"'"' '"'"' < "/proc/$q/cmdline" 2>/dev/null)
              case "$qcmd" in *logcat*) att=1; break ;; esac
              ;;
          esac
        done
        [ "$att" = 1 ] && { touch "$leasef"; continue; }
        break
      fi
    done
    "$adb" -s "emulator-$p" emu kill >/dev/null 2>&1
    rm -f "$leasef" "$ownedf" "$kpf"
    exit 0
  ' mg-emu-keeper "$p" "$lf" "$mk" "$leasef" "$ownedf" "$kpf" \
    "$MG_ADB" "$MG_KEEPER_CHECK" "$MG_LEASE_TTL" "$MG_KEEPER_MAX" \
    >/dev/null 2>&1 &
  echo $!
  disown
}

# Try to claim ONE port. 0 = got it, 1 = couldn't.
mg__try_claim() {
  local p="$1"
  local leasef="$MG_LOCK_DIR/$p.lease" ownedf="$MG_LOCK_DIR/$p.owned" kpf="$MG_LOCK_DIR/$p.keeperpid"

  local why rc; why=$(mg__classify_port "$p"); rc=$?
  case "$rc" in
    1) return 1 ;;            # busy: active session or foreign emulator
    0) # owner provably gone → evict. Final safety net: NEVER evict a port that
       # has a LIVE (non-orphaned) flutter/dart session attached, whatever classify
       # said. An orphaned zombie driver must NOT block reclamation.
       if mg__live_attached "$p"; then return 1; fi
       mg__reclaim "$p" ;;
    # 2 = free → fall through
  esac

  local mk="$MG_LOCK_DIR/.ack-$p.$$.$RANDOM"
  local kpid; kpid=$(mg__spawn_keeper "$p" "$mk")
  local i
  for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15; do
    [ -f "$mk" ] && break
    kill -0 "$kpid" 2>/dev/null || break
    sleep 0.2
  done
  if [ -f "$mk" ] && kill -0 "$kpid" 2>/dev/null; then
    rm -f "$mk"
    local had_marker=0
    { [ -f "$ownedf" ] || [ -f "$kpf" ]; } && had_marker=1
    if "$MG_ADB" -s "emulator-$p" get-state >/dev/null 2>&1; then
      if [ "$had_marker" -eq 1 ]; then
        "$MG_ADB" -s "emulator-$p" emu kill >/dev/null 2>&1
        while "$MG_ADB" -s "emulator-$p" get-state >/dev/null 2>&1; do sleep 1; done
      else
        kill "$kpid" 2>/dev/null; return 1   # foreign emulator → respect it
      fi
    fi
    echo "$kpid" > "$kpf"
    touch "$leasef"
    return 0
  fi
  kill "$kpid" 2>/dev/null; rm -f "$mk"
  return 1
}

# Claim one of the 3 ports. Bounded, session-aware, self-reaping.
mg_claim_port() {
  command -v flock >/dev/null || { echo "flock not found (install util-linux)" >&2; return 1; }
  mkdir -p "$MG_LOCK_DIR" "$MG_WAITERS_DIR"
  local my_owner; my_owner=$(mg__owner_of "$$") || my_owner="none"
  local wf="$MG_WAITERS_DIR/$$"
  echo "$my_owner" > "$wf"
  # A bare `trap '…' TERM` would clean up but then RESUME the loop — so a reaper's
  # SIGTERM wouldn't actually stop a stale/superseded waiter. Make the signal
  # traps exit; EXIT handles the normal-return path.
  trap 'rm -f "'"$wf"'"' EXIT
  trap 'rm -f "'"$wf"'"; trap - EXIT; exit 143' TERM
  trap 'rm -f "'"$wf"'"; trap - EXIT; exit 130' INT

  mg__reap_claimers "$$" "$my_owner"
  local start; start=$(date +%s)
  while :; do
    # self-abandon if my own session died (orphaned loop ⇒ no value)
    if [ "$my_owner" != "none" ] && ! kill -0 "$my_owner" 2>/dev/null; then
      echo "Owner session ($my_owner) is gone — abandoning claim." >&2
      rm -f "$wf"; trap - EXIT INT TERM; return 1
    fi
    local p
    for p in "${MG_PORTS[@]}"; do
      if mg__try_claim "$p"; then
        MG_PORT="$p"; export ANDROID_SERIAL="emulator-$p"
        rm -f "$wf"; trap - EXIT INT TERM
        echo "Claimed port $p (ANDROID_SERIAL=$ANDROID_SERIAL)"
        return 0
      fi
    done
    if [ $(( $(date +%s) - start )) -ge "$MG_CLAIM_TIMEOUT" ]; then
      echo "POOL_BUSY: waited ${MG_CLAIM_TIMEOUT}s, all 3 ports held by live sessions. Call mg_claim_port again to retry." >&2
      rm -f "$wf"; trap - EXIT INT TERM; return 1
    fi
    mg__reap_claimers "$$" "$my_owner"
    echo "All 3 ports (${MG_PORTS[*]}) busy with live sessions — polling every ${MG_WAIT_SECONDS}s..." >&2
    sleep "$MG_WAIT_SECONDS"
  done
}

# Renew the lease so the keeper doesn't reclaim an active emulator.
mg_keepalive() {
  [ -n "$MG_PORT" ] && touch "$MG_LOCK_DIR/$MG_PORT.lease"
}

# ─────────────────────────────────────────────────────────────────────────────
# Session-aware lease KEEPALIVE daemon — for workflows with NO flutter/dart/java
# driver attached to the port (build-APK + `am start` + logcat, manual ADB
# driving, screenshot loops). The pool keeper only AUTO-renews a lease while such
# a driver is attached; without one it reclaims the emulator after MG_LEASE_TTL
# (the "they died on their own after ~3 min" symptom). This daemon renews the
# given ports' leases every MG_KEEPALIVE_INTERVAL — but ONLY while the owning
# `claude` session is alive, and stops the instant that session dies, so a dead
# agent can NOT pin ports forever (that was the v1 leak the whole pool exists to
# prevent). One daemon per session (keyed by the owner pid); calling start again
# supersedes the previous one and covers the new full port set.
MG_KEEPALIVE_INTERVAL="${MG_KEEPALIVE_INTERVAL:-60}"

mg__keepalive_pidfile() {
  local owner; owner=$(mg__owner_of "$$") || owner="solo"
  echo "$MG_LOCK_DIR/keepalive.$owner.pid"
}

# mg_keepalive_start [port...]   (defaults to $MG_PORT if none given)
mg_keepalive_start() {
  mkdir -p "$MG_LOCK_DIR"
  local ports="$*"; [ -n "$ports" ] || ports="$MG_PORT"
  [ -n "$ports" ] || { echo "mg_keepalive_start: no ports" >&2; return 1; }
  mg_keepalive_stop                              # supersede any prior daemon (this session)
  local owner; owner=$(mg__owner_of "$$") || owner="solo"
  local pidf; pidf=$(mg__keepalive_pidfile)
  nohup bash -c '
    ports="$1"; lockdir="$2"; adb="$3"; owner="$4"; interval="$5"
    while :; do
      # Owning session gone ⇒ stop renewing so the keeper reclaims on TTL.
      if [ "$owner" != "solo" ] && ! kill -0 "$owner" 2>/dev/null; then exit 0; fi
      alive=0
      for p in $ports; do
        if "$adb" -s "emulator-$p" get-state >/dev/null 2>&1; then
          touch "$lockdir/$p.lease" 2>/dev/null; alive=$((alive+1))
        fi
      done
      [ "$alive" -eq 0 ] && exit 0               # nothing left to keep alive
      sleep "$interval"
    done
  ' mg-emu-keepalive "$ports" "$MG_LOCK_DIR" "$MG_ADB" "$owner" "$MG_KEEPALIVE_INTERVAL" \
    >/dev/null 2>&1 &
  echo "$!" > "$pidf"
  disown
  echo "keepalive daemon $! renewing leases [$ports] while session $owner is alive"
}

mg_keepalive_stop() {
  local pidf; pidf=$(mg__keepalive_pidfile)
  [ -f "$pidf" ] || return 0
  kill "$(command cat "$pidf" 2>/dev/null)" 2>/dev/null
  rm -f "$pidf"
}

# Boot an AVD on the claimed port (read-only) and wait for full boot.
mg_boot_avd() {
  local avd="$1"
  [ -n "$MG_PORT" ] || { echo "mg_boot_avd: no port claimed — call mg_claim_port first" >&2; return 1; }
  [ -n "$avd" ]     || { echo "mg_boot_avd: missing AVD name" >&2; return 1; }
  # RAM preflight: refuse to boot if available memory is too low.
  mg__ram_preflight || return 1
  # Reap any zombie qemu on this port BEFORE starting a new one — prevents
  # stacking multiple qemu processes on the same port (the crash/OOM spiral).
  mg__kill_port_qemu "$MG_PORT"
  touch "$MG_LOCK_DIR/$MG_PORT.owned" "$MG_LOCK_DIR/$MG_PORT.lease"
  nohup "$MG_EMULATOR_BIN" -avd "$avd" -no-window -no-audio \
    -gpu "$MG_GPU" -no-snapshot-save -read-only \
    -port "$MG_PORT" > "/tmp/emulator-$MG_PORT.log" 2>&1 &
  disown
  echo "Booting $avd on emulator-$MG_PORT ..."
  until [ "$("$MG_ADB" -s "emulator-$MG_PORT" shell getprop sys.boot_completed 2>/dev/null | command tr -d '\r')" = "1" ]; do
    touch "$MG_LOCK_DIR/$MG_PORT.lease"   # renew while a slow boot is in progress
    sleep 5
  done
  touch "$MG_LOCK_DIR/$MG_PORT.lease"
  echo "$avd booted on emulator-$MG_PORT"
}

# Kill the emulator on the claimed port; KEEP the port lock held (renew lease so
# a long-running session that swaps AVDs isn't seen as an abandoned claim).
# Also reaps any zombie qemu on this port so the slot is clean for the next boot.
mg_kill_current() {
  [ -n "$MG_PORT" ] || return 0
  touch "$MG_LOCK_DIR/$MG_PORT.lease"
  mg__kill_port_qemu "$MG_PORT"
  while "$MG_ADB" -s "emulator-$MG_PORT" get-state >/dev/null 2>&1; do sleep 1; done
  rm -f "$MG_LOCK_DIR/$MG_PORT.owned"
}

mg_swap_avd() {
  mg_kill_current   # reaps zombie + waits for clean slot before mg_boot_avd
  mg_boot_avd "$1"
}

mg_release_port() {
  if [ -z "$MG_PORT" ]; then
    echo "mg_release_port: MG_PORT is unset — NOTHING released (this looked like success before). Each Bash tool call is a fresh shell: re-source this file and set MG_PORT=<port> (the one mg_claim_port gave you), or call mg_emu_down which does this per-port for you." >&2
    return 1
  fi
  mg_kill_current
  local kpf="$MG_LOCK_DIR/$MG_PORT.keeperpid"
  [ -f "$kpf" ] && kill "$(command cat "$kpf")" 2>/dev/null
  rm -f "$kpf" "$MG_LOCK_DIR/$MG_PORT.lease" "$MG_LOCK_DIR/$MG_PORT.owned"
  echo "Released port $MG_PORT"
  MG_PORT=""
}

# ============================ inspection / maintenance =======================

mg_emu_status() {
  local p why
  for p in "${MG_PORTS[@]}"; do
    why=$(mg__classify_port "$p")
    echo "  $p: $why"
  done
}

# Show the waiting queue and whether each waiter's session is still alive.
mg_emu_queue() {
  local f pid owner n=0
  echo "Waiting mg_claim_port loops:"
  if [ -d "$MG_WAITERS_DIR" ]; then
    for f in "$MG_WAITERS_DIR"/*; do
      [ -e "$f" ] || continue
      pid=${f##*/}
      if ! kill -0 "$pid" 2>/dev/null; then echo "  pid $pid: DEAD entry (will be reaped)"; n=$((n+1)); continue; fi
      owner=$(command cat "$f" 2>/dev/null)
      if [ "$owner" = "none" ]; then echo "  pid $pid (age $(mg__proc_age "$pid")s): no session owner"
      elif kill -0 "$owner" 2>/dev/null; then echo "  pid $pid (age $(mg__proc_age "$pid")s): session $owner ALIVE"
      else echo "  pid $pid (age $(mg__proc_age "$pid")s): session $owner DEAD ⇒ zombie (will be reaped)"; fi
      n=$((n+1))
    done
  fi
  [ "$n" -eq 0 ] && echo "  (none)"
}

# Reclaim leaked/idle ports AND reap stale waiters, right now. SAFE.
# Extended checks (B.3 in task spec):
#   (a) qemu processes that adb cannot see (crashed-but-alive zombies)
#   (b) DUPLICATE qemu on the same port (symptom of the reboot-stacking spiral)
# Both are reaped via mg__kill_port_qemu when the port is also not active.
mg_emu_doctor() {
  mkdir -p "$MG_LOCK_DIR" "$MG_WAITERS_DIR"
  local p why rc reclaimed=0

  # ── Pass 1: standard pool-marker–based reclaim ─────────────────────────────
  for p in "${MG_PORTS[@]}"; do
    why=$(mg__classify_port "$p"); rc=$?
    # Reclaim ONLY on an explicit, non-empty reclaimable verdict AND a final
    # re-check that nothing live is attached. An empty/ambiguous classify result
    # is treated as "leave alone" — fail safe, never kill on doubt.
    if [ "$rc" -eq 0 ] && [ -n "$why" ] && ! mg__live_attached "$p"; then
      echo "  $p: reclaiming — $why"
      mg__reclaim "$p"
      reclaimed=$((reclaimed + 1))
    else
      echo "  $p: pool marker — ${why:-(no verdict / active — not touched)}"
    fi
  done

  # ── Pass 2: detect adb-invisible zombies and duplicate qemu on each port ───
  # A crashed emulator's qemu process is NOT visible via `adb get-state` but IS
  # visible in /proc. We scan for these and reap them — but only when no LIVE
  # attached session is present (safety: never kill a port a live run uses).
  echo "Checking for adb-invisible zombie / duplicate qemu processes..."
  for p in "${MG_PORTS[@]}"; do
    if mg__live_attached "$p"; then
      echo "  $p: live session attached — skipping zombie scan"
      continue
    fi
    # Count qemu processes claiming this port (any beyond 1 = stacking; 1 when
    # adb cannot see it = zombie).
    local qpids qcount
    qpids=$(pgrep -f -- "-port $p" 2>/dev/null || true)
    qcount=0
    local pid comm
    for pid in $qpids; do
      [ "$pid" = "$$" ] && continue
      comm=$(command cat "/proc/$pid/comm" 2>/dev/null || true)
      case "$comm" in qemu-system*|emulator*|emulator64*) qcount=$((qcount + 1)) ;; esac
    done
    local adb_sees=0
    "$MG_ADB" -s "emulator-$p" get-state >/dev/null 2>&1 && adb_sees=1
    if [ "$qcount" -ge 2 ]; then
      echo "  $p: DUPLICATE qemu ($qcount processes, adb_sees=$adb_sees) — reaping via mg__kill_port_qemu"
      mg__kill_port_qemu "$p"
      mg__reclaim "$p" 2>/dev/null || true
      reclaimed=$((reclaimed + 1))
    elif [ "$qcount" -eq 1 ] && [ "$adb_sees" -eq 0 ]; then
      echo "  $p: adb-invisible zombie qemu — reaping via mg__kill_port_qemu"
      mg__kill_port_qemu "$p"
      mg__reclaim "$p" 2>/dev/null || true
      reclaimed=$((reclaimed + 1))
    elif [ "$qcount" -eq 0 ] && [ "$adb_sees" -eq 0 ]; then
      echo "  $p: no qemu process, no adb visibility — clean"
    else
      echo "  $p: $qcount qemu process(es), adb_sees=$adb_sees — OK"
    fi
  done

  echo "Reaping stale/dead-session waiters..."
  mg__reap_claimers "$$" "none"   # owner=none ⇒ only reaps dead-pid + dead-session loops
  echo "Doctor done — reclaimed $reclaimed port(s)."
}

# PANIC button: kill every pool emulator + keeper + waiter. Nukes other agents too.
mg_emu_reset() {
  local p f
  for p in "${MG_PORTS[@]}"; do
    "$MG_ADB" -s "emulator-$p" emu kill 2>/dev/null
    local kpf="$MG_LOCK_DIR/$p.keeperpid"
    [ -f "$kpf" ] && kill "$(command cat "$kpf")" 2>/dev/null
    rm -f "$kpf" "$MG_LOCK_DIR/$p.lease" "$MG_LOCK_DIR/$p.owned"   # keep .lock (flock anchor)
  done
  if [ -d "$MG_WAITERS_DIR" ]; then
    for f in "$MG_WAITERS_DIR"/*; do
      [ -e "$f" ] || continue
      kill "${f##*/}" 2>/dev/null; rm -f "$f"
    done
  fi
  echo "Reset ports ${MG_PORTS[*]} (all pool emulators + keepers + waiters killed)"
}
