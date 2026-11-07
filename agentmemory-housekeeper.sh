#!/bin/bash
# agentmemory housekeeper — hot-scope pruning.
#
# Works around these un-fixed upstream defects (verified on agentmemory
# 0.9.29 + iii-engine v0.11.2). REMOVE/ADJUST the matching block when the
# issue is fixed upstream:
#
#  [A] Unbounded KV scopes kill the iii bridge. Consolidation appends
#      semantic facts to the mem:semantic scope forever (no entry/size cap),
#      and list endpoints like api::semantic-list return the whole scope in
#      one response (no pagination). Function results travel over the
#      iii-engine bridge WebSocket, which has a message/heartbeat budget of
#      a few MB; once a scope's serialized contents outgrow it, the engine
#      stops the invocation and drops the worker connection. Symptoms:
#      GET /agentmemory/semantic returns 500 "Invocation stopped", and the
#      resulting re-registration churn can transiently break unrelated
#      endpoints ("function_not_found" / 404 on sessions, memories, ...).
#      - OPEN  https://github.com/rohitg00/agentmemory/issues/890
#        (mesh/export unpaginated, same failure class)
#      - OPEN  https://github.com/rohitg00/agentmemory/issues/1133
#        (mem::reflect unbounded enumeration, same failure class)
#      - No dedicated issue for api::semantic-list at time of writing; the
#        pagination + side-index pattern that fixed the graph endpoints is
#        closed: #753 (v0.9.25) and #814/#828 (v0.9.27).
#      => the semantic retention tier below exists until list endpoints
#         paginate or scopes get a hard cap.
#
#  [B] Graph scopes grow unbounded too, with no retention and no vacuum:
#      graph extraction appends nodes/edges every session; reads stay
#      bounded only while the side-indexes cover them, and boot backfill is
#      skipped past ~25K nodes, after which reads fall back to full
#      enumeration = defect [A]; and mem::graph-reset only marks rows as
#      orphaned without deleting them (src/functions/graph.ts:973), so
#      files keep growing even after logical resets. The graph is derived
#      state (re-extracted from future sessions), so periodic resets are
#      the safe size control.
#      - REF   https://github.com/rohitg00/agentmemory/issues/309
#        (SQLite-backed stores epic; sharded index half shipped in #764,
#        capped graph reads still roadmap)
#      => graph reset/wipe tiers below exist until capped reads work at
#         any size and a physical vacuum lands.
#
#  [D] Retention-evict only started covering mem:semantic in v0.8.10
#      (closed https://github.com/rohitg00/agentmemory/issues/124), which
#      is why prune_semantic below is safe to use today.
#
#  [E] mem:insights is append-only: mem::reflect only ever writes it
#      (src/functions/reflect.ts), and the sole kv.delete for the scope lives
#      inside the import "replace" strategy (src/functions/export-import.ts)
#      — retention-evict does NOT cover it (compare [D]). Observed 2026-08-14
#      at 94MiB / 11,063 entries (~9KB avg): any full-scope enumeration then
#      outgrows the bridge budget = defect [A], and in-run pruning never
#      shrinks the physical file.
#      - OPEN  https://github.com/rohitg00/agentmemory/issues/1133
#        (mem::reflect unbounded enumeration, same failure class)
#      => insights hard-cap tier below: physical archive + restart. Insights
#         are derived state; future mem::reflect runs rebuild them, so no
#         re-import step is required (recovery needs none, unlike [A]).
#
# Design note: snapshot-before-prune guarantees evicted/reset data stays
# restorable from git history under $SNAPSHOT_DIR. Validation happens
# dry-run-first and the snapshot is skipped when nothing would change, so
# no-op passes do not bloat the snapshot history.
set -u

STATE_DIR=/data/state_store.db
ARCHIVE_DIR=/data/archive

SEM_SOFT_BYTES=$((4  * 1024 * 1024))   # mem:semantic -> retention-evict
SEM_WARN_BYTES=$((12 * 1024 * 1024))   # mem:semantic approaching bridge-fatal zone ([A]; iii JSON envelope = 16MiB, retention-score result already dies over it)
GRAPH_SOFT_BYTES=$((15 * 1024 * 1024)) # graph:nodes -> mem::graph-reset
GRAPH_HARD_BYTES=$((30 * 1024 * 1024)) # all graph *.bin -> physical wipe
INSIGHTS_HARD_BYTES=$((16 * 1024 * 1024)) # mem:insights -> physical archive (see [E]; <18.7MiB empirically-fatal on this stack, see lsn_8c7424da07feeb0b)
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

# Propagates the iii trigger exit code (function errors exit non-zero, e.g.
# invocation_stopped / function_not_found) so callers can gate destructive
# steps on a restorable snapshot actually existing.
snapshot() {
  local out rc=0
  log "snapshot-create ($1)"
  out=$(tri_json mem::snapshot-create "{\"message\":\"agentmemory_housekeeper: $1\"}") || rc=$?
  printf '%s' "$out" | head -c 300; echo
  return "$rc"
}

# retention-score refreshes the persisted scores retention-evict consumes.
# Past ~16MiB of scored entries its RESULT envelope exceeds the iii bridge
# budget ([A]) and the trigger replies payload_too_large; the scores still
# land server-side, so that reply is expected and non-fatal.
prune_semantic() {
  local out n i
  out=$(tri mem::retention-score '{}')
  case "$out" in
    *payload_too_large*) log "retention-score result exceeds bridge envelope; scores refreshed server-side (expected past ~16MiB, see [A])" ;;
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

wipe_graph() {
  local dest
  dest="$ARCHIVE_DIR/graph-$(date +%Y%m%d-%H%M%S)"
  agentmemory stop >/dev/null 2>&1; sleep 3
  mkdir -p "$dest"; mv "$STATE_DIR"/mem%3Agraph%3A*.bin "$dest/" 2>/dev/null
  start_agentmemory
}

# [E] physical prune for mem:insights — the scope has no logical eviction
# path, so over hard-cap it is archived and re-derived by future reflects.
wipe_insights() {
  local dest
  dest="$ARCHIVE_DIR/insights-$(date +%Y%m%d-%H%M%S)"
  agentmemory stop >/dev/null 2>&1; sleep 3
  mkdir -p "$dest"; mv "$STATE_DIR/mem%3Ainsights.bin" "$dest/" 2>/dev/null
  start_agentmemory
}

prune() {
  local sem="$STATE_DIR/mem%3Asemantic.bin" sem_size graph_size graph_nodes_size insights_size

  sem_size=$(size "$sem")
  graph_size=$(size "$STATE_DIR"/mem%3Agraph%3A*.bin)
  graph_nodes_size=$(size "$STATE_DIR/mem%3Agraph%3Anodes.bin")
  insights_size=$(size "$STATE_DIR/mem%3Ainsights.bin")

  if [ "$sem_size" -gt "$SEM_SOFT_BYTES" ]; then
    log "mem:semantic ${sem_size}B > soft cap; retention prune"
    if [ "$sem_size" -gt "$SEM_WARN_BYTES" ]; then
      log "WARNING: mem:semantic ${sem_size}B > ${SEM_WARN_BYTES}B; full-scope enumerations (semantic-list/reflect/export, see [A]) already fail at this size; retention pruning alone will not clear the bridge-fatal zone"
    fi
    prune_semantic
  fi

  if [ "$insights_size" -gt "$INSIGHTS_HARD_BYTES" ]; then
    log "mem:insights ${insights_size}B > hard cap; physical archive (derived scope; reflect rebuilds)"
    if snapshot "pre-insights-wipe"; then wipe_insights; else log "snapshot failed; insights wipe aborted"; fi
  fi

  if [ "$graph_size" -gt "$GRAPH_HARD_BYTES" ]; then
    log "graph scopes ${graph_size}B > hard cap; physical wipe"
    if snapshot "pre-graph-wipe"; then wipe_graph; else log "snapshot failed; graph wipe aborted"; fi
  elif [ "$graph_nodes_size" -gt "$GRAPH_SOFT_BYTES" ]; then
    log "graph:nodes ${graph_nodes_size}B > soft cap; logical reset (extraction rebuilds)"
    if snapshot "pre-graph-reset"; then tri mem::graph-reset '{}'; else log "snapshot failed; graph reset aborted"; fi
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
