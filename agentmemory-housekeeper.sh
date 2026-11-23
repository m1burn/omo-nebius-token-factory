#!/bin/bash
# agentmemory housekeeper — hot-scope pruning for agentmemory 0.9.33 +
# iii v0.25.1.
#
# The bridge-era failure mode is gone: large state/semantic/insight
# reads are paged, reflect/export are bounded/paginated, and the iii
# transport frame is 64MiB with a 60MiB safe budget
# (src/state/frame-guard.ts). What still needs housekeeping:
#
#  - mem:semantic writes are unbounded (no server-side size cap); the
#    only control is retention-evict, server-capped at 1000 evictions
#    per call (src/functions/retention.ts) — hence the soft cap +
#    retention-score + dry-run + up-to-five evict loop below.
#  - Graph scopes have no vacuum: mem::graph-reset re-initializes the
#    active generation but keeps the old physical storage
#    (physicalStorageRetained, src/functions/graph.ts), so only the
#    physical wipe below reclaims disk; the wipe then runs graph-reset
#    so the uninitialized store gets a ready generation/index
#    (docs/reliability/graph-index-migration.md).
#  - mem:insights decay is soft-delete only (src/functions/reflect.ts);
#    nothing shrinks the physical file, so the hard cap below archives
#    and restarts. Insights are derived state; future reflects rebuild.
#
# Snapshots (mem::snapshot-create) include episodic memories, graph,
# and observations — NOT semantic or insights
# (src/functions/snapshot.ts) — so they gate only the evict and
# graph-wipe paths; the insights and graph wipes keep their moved
# files under $ARCHIVE_DIR.
#
# Design note: validation happens dry-run-first and the snapshot is
# skipped when nothing would change, so no-op passes do not bloat the
# snapshot history.
set -u

STATE_DIR=/data/state_store.db
ARCHIVE_DIR=/data/archive

SEM_SOFT_BYTES=$((4  * 1024 * 1024))       # mem:semantic -> retention-evict (writes unbounded; evict capped at 1000/call)
GRAPH_HARD_BYTES=$((30 * 1024 * 1024))     # all graph *.bin -> physical wipe (no vacuum; reset retains storage)
INSIGHTS_HARD_BYTES=$((16 * 1024 * 1024))  # mem:insights -> physical archive (decay is soft-delete only; conservative disk/working-set cap)
EVICT_THRESHOLD=0.60                   # retention-score cutoff; lower = keep more. 0.55 never fired: live store's score floor measured 0.5501 (2026-10), so every prune pass evicted 0
EVICT_MAX=1000                         # max evictions per retention-evict call (server-side cap, retention.ts)
EVICT_LOOPS=5                          # bounded evict calls per pass; loop stops early when a call evicts 0
PRUNE_INTERVAL=86400                   # daily pruning cadence

log()  { echo "[agentmemory_housekeeper] $(date -Is) $*"; }
tri_json() { iii trigger -n "${III_NAMESPACE:-agentmemory-3111}" --timeout-ms "${III_TIMEOUT_MS:-180000}" "$1" --json "$2" 2>&1; } # full result, for parsing (bulky)
tri()  { tri_json "$1" "$2" | head -c 300; } # log-truncated; do NOT parse from this (fields past 300 chars are cut)
size() {
  local total=0 f
  for f in "$@"; do
    [ -f "$f" ] && total=$((total + $(stat -c%s "$f")))
  done
  echo "$total"
}

wait_healthy() {
  for _ in $(seq 1 60); do
    curl -sf --max-time 2 -H "Authorization: Bearer ${AGENTMEMORY_SECRET:-}" \
      http://127.0.0.1:3111/agentmemory/health >/dev/null && return 0
    sleep 5
  done
  log "agentmemory not healthy after 5min; skipping pass"; return 1
}

# Fails closed: iii nonzero exit (function errors exit non-zero, e.g.
# function_not_found), missing/non-JSON output, {success:false}, and the
# success-but-"already in progress" case all count as failure. Only an
# explicit success that is not already-in-progress passes, so callers
# gate destructive steps on a snapshot actually existing. jq is
# installed by the Dockerfile.
snapshot() {
  local out rc=0 ok
  log "snapshot-create ($1)"
  out=$(tri_json mem::snapshot-create "{\"message\":\"agentmemory_housekeeper: $1\"}") || rc=$?
  printf '%s' "$out" | head -c 300; echo
  if [ "$rc" -ne 0 ]; then return "$rc"; fi
  ok=$(printf '%s' "$out" | jq -r 'if (.success == true) and ((.message // "") | test("already in progress") | not) then "true" else "false" end' 2>/dev/null) || ok=false
  [ "$ok" = "true" ] || return 1
}

# retention-score refreshes the persisted scores retention-evict consumes.
# Past ~60MiB of scored entries its result envelope exceeds the iii
# transport budget (64MiB frame, 60MiB safe budget) and the trigger
# replies payload_too_large; the scores still land server-side, so that
# reply is expected and non-fatal.
prune_semantic() {
  local out n i
  out=$(tri mem::retention-score '{}')
  case "$out" in
    *payload_too_large*) log "retention-score result exceeds transport envelope (64MiB frame / 60MiB safe budget); scores refreshed server-side" ;;
    *) printf '%s\n' "$out" ;;
  esac

  # Gate on the dry-run so snapshot+evict (and the daily ~100MB git commit)
  # only happen when there is data that will actually change.
  out=$(tri_json mem::retention-evict "{\"threshold\":$EVICT_THRESHOLD,\"maxEvict\":$EVICT_MAX,\"dryRun\":true}")
  n=$(printf '%s' "$out" | sed -n 's/.*"wouldEvict": *\([0-9][0-9]*\).*/\1/p')
  case "$n" in
    *[!0-9]*|'') log "dry-run result unreadable ($(printf '%s' "$out" | head -c 200)); skipping evict this pass"; return ;;
    0) log "nothing evictable below $EVICT_THRESHOLD; skipping snapshot + evict"; return ;;
  esac
  log "dry-run wouldEvict=$n (threshold $EVICT_THRESHOLD)"

  if ! snapshot "pre-semantic-prune"; then
    log "snapshot failed; skipping evict this pass"
    return
  fi
  for i in $(seq 1 "$EVICT_LOOPS"); do
    out=$(tri_json mem::retention-evict "{\"threshold\":$EVICT_THRESHOLD,\"maxEvict\":$EVICT_MAX}")
    n=$(printf '%s' "$out" | sed -n 's/.*"evicted": *\([0-9][0-9]*\).*/\1/p')
    case "$n" in
      *[!0-9]*|'') log "evict result unreadable ($(printf '%s' "$out" | head -c 200)); stopping loop"; return ;;
    esac
    log "evict pass $i/$EVICT_LOOPS: evicted=$n"
    [ "$n" -eq 0 ] && break
  done
}

# setsid so the restarted agentmemory survives teardown of whatever shell
# invoked the housekeeping pass (plain nohup died with the pass in practice).
start_agentmemory() {
  ( cd /home/omo/.omo-agentmemory && setsid agentmemory >/dev/null 2>&1 & )
  wait_healthy || return 1
}

# Physical graph wipe: archive every graph scope, restart, then run
# mem::graph-reset so the freshly wiped (uninitialized) store gets a
# ready generation/index. The reset itself retains physical storage —
# the mv above is what reclaims disk; the reset only re-initializes. A
# failed reset leaves the graph store uninitialized, so it is logged
# and returned nonzero, never swallowed.
wipe_graph() {
  local dest out rc=0 ok
  dest="$ARCHIVE_DIR/graph-$(date +%Y%m%d-%H%M%S)"
  agentmemory stop >/dev/null 2>&1; sleep 3
  mkdir -p "$dest"; mv "$STATE_DIR"/mem%3Agraph%3A*.bin "$dest/" 2>/dev/null
  start_agentmemory || return 1
  out=$(tri_json mem::graph-reset '{}') || rc=$?
  printf '%s' "$out" | head -c 300; echo
  ok=$(printf '%s' "$out" | jq -r 'if .success == true then "true" else "false" end' 2>/dev/null) || ok=false
  if [ "$rc" -eq 0 ] && [ "$ok" = "true" ]; then
    log "graph generation re-initialized after wipe"
    return 0
  fi
  log "graph-reset after wipe failed (rc=$rc); graph store left uninitialized — run mem::graph-reset manually"
  return 1
}

# Physical prune for mem:insights — decay is soft-delete only and no
# logical eviction covers the scope, so over hard-cap it is archived
# (the archive retains the moved scope) and re-derived by future
# reflects. No snapshot gate: snapshots omit insights.
wipe_insights() {
  local dest
  dest="$ARCHIVE_DIR/insights-$(date +%Y%m%d-%H%M%S)"
  agentmemory stop >/dev/null 2>&1; sleep 3
  mkdir -p "$dest"; mv "$STATE_DIR/mem%3Ainsights.bin" "$dest/" 2>/dev/null
  start_agentmemory
}

prune() {
  local sem="$STATE_DIR/mem%3Asemantic.bin" sem_size graph_size insights_size

  sem_size=$(size "$sem")
  graph_size=$(size "$STATE_DIR"/mem%3Agraph%3A*.bin)
  insights_size=$(size "$STATE_DIR/mem%3Ainsights.bin")

  if [ "$sem_size" -gt "$SEM_SOFT_BYTES" ]; then
    log "mem:semantic ${sem_size}B > soft cap; retention prune"
    prune_semantic
  fi

  if [ "$insights_size" -gt "$INSIGHTS_HARD_BYTES" ]; then
    log "mem:insights ${insights_size}B > hard cap; physical archive (derived scope; reflect rebuilds; snapshots omit insights)"
    wipe_insights
  fi

  if [ "$graph_size" -gt "$GRAPH_HARD_BYTES" ]; then
    log "graph scopes ${graph_size}B > hard cap; physical wipe"
    if snapshot "pre-graph-wipe"; then
      wipe_graph || log "graph wipe/reset failed; graph store may be uninitialized — see errors above"
    else
      log "snapshot failed; graph wipe aborted"
    fi
  fi

  local s f
  for s in procedural lessons crystals; do
    f="$STATE_DIR/mem%3A${s}.bin"
    [ "$(size "$f")" -gt "$SEM_SOFT_BYTES" ] && log "WARNING: mem:$s ($(size "$f")B) growing; prune manually"
  done
}

log "starting (pruning every ${PRUNE_INTERVAL}s)"
last_prune=0
while true; do
  now=$(date +%s)
  if [ $((now - last_prune)) -ge "$PRUNE_INTERVAL" ]; then
    if wait_healthy; then prune; last_prune=$(date +%s); fi
  fi
  sleep 60
done
