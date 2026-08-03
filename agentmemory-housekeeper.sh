#!/bin/bash
# agentmemory housekeeper — scheduled snapshots + hot-scope pruning.
#
# Works around these un-fixed upstream defects (verified on agentmemory
# 0.9.28 + iii-engine v0.11.2). REMOVE/ADJUST the matching block when the
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
#  [C] Snapshot scheduling is dead config: loadSnapshotConfig() reads
#      SNAPSHOT_INTERVAL and the boot log prints "Git snapshots: <dir>
#      (every 3600s)", but no code path anywhere calls mem::snapshot-create
#      automatically, and agentmemory registers zero cron triggers — so
#      SNAPSHOT_ENABLED=true alone never produces a single snapshot; only
#      manual REST/MCP calls do. No upstream issue found at time of writing.
#      => the snapshot ticker below implements what upstream intended:
#         same SNAPSHOT_INTERVAL variable, same unit (seconds), same
#         default (3600). Exists until upstream wires the real timer; the
#         loop is also the only general scheduler (see [A]/[B]).
#
#  [D] Retention-evict only started covering mem:semantic in v0.8.10
#      (closed https://github.com/rohitg00/agentmemory/issues/124), which
#      is why prune_semantic below is safe to use today.
#
# Design note: snapshot-before-prune guarantees evicted/reset data stays
# restorable from git history under $SNAPSHOT_DIR.
set -u

STATE_DIR=/data/state_store.db
ARCHIVE_DIR=/data/archive

SEM_SOFT_BYTES=$((4  * 1024 * 1024))   # mem:semantic -> retention-evict
GRAPH_SOFT_BYTES=$((15 * 1024 * 1024)) # graph:nodes -> mem::graph-reset
GRAPH_HARD_BYTES=$((30 * 1024 * 1024)) # all graph *.bin -> physical wipe
EVICT_THRESHOLD=0.55                   # retention-score cutoff; lower = keep more
EVICT_MAX=1000                         # max evictions per prune pass
PRUNE_INTERVAL=86400                   # daily pruning cadence

SNAPSHOT_INTERVAL="${SNAPSHOT_INTERVAL:-3600}"   # via entrypoint set -a

log()  { echo "[agentmemory_housekeeper] $(date -Is) $*"; }
tri()  { iii trigger --function-id "$1" --payload "$2" 2>&1 | head -c 300; }
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

snapshot() {
  log "snapshot-create ($1)"; tri mem::snapshot-create "{\"message\":\"agentmemory_housekeeper: $1\"}"
}

prune_semantic() {
  tri mem::retention-score '{}'
  tri mem::retention-evict "{\"threshold\":$EVICT_THRESHOLD,\"maxEvict\":$EVICT_MAX,\"dryRun\":true}"
  tri mem::retention-evict "{\"threshold\":$EVICT_THRESHOLD,\"maxEvict\":$EVICT_MAX}"
}

wipe_graph() {
  local dest="$ARCHIVE_DIR/graph-$(date +%Y%m%d-%H%M%S)"
  agentmemory stop >/dev/null 2>&1; sleep 3
  mkdir -p "$dest"; mv "$STATE_DIR"/mem%3Agraph%3A*.bin "$dest/" 2>/dev/null
  cd /home/omo/.omo-agentmemory && nohup agentmemory >/dev/null 2>&1 &
  wait_healthy || return 1
}

prune() {
  local sem="$STATE_DIR/mem%3Asemantic.bin" sem_size graph_size graph_nodes_size

  sem_size=$(size "$sem")
  graph_size=$(size "$STATE_DIR"/mem%3Agraph%3A*.bin)
  graph_nodes_size=$(size "$STATE_DIR/mem%3Agraph%3Anodes.bin")

  if [ "$sem_size" -gt "$SEM_SOFT_BYTES" ]; then
    log "mem:semantic ${sem_size}B > soft cap; retention prune"
    snapshot "pre-semantic-prune"; prune_semantic
  fi

  if [ "$graph_size" -gt "$GRAPH_HARD_BYTES" ]; then
    log "graph scopes ${graph_size}B > hard cap; physical wipe"
    snapshot "pre-graph-wipe"; wipe_graph
  elif [ "$graph_nodes_size" -gt "$GRAPH_SOFT_BYTES" ]; then
    log "graph:nodes ${graph_nodes_size}B > soft cap; logical reset (extraction rebuilds)"
    snapshot "pre-graph-reset"; tri mem::graph-reset '{}'
  fi

  local s f
  for s in procedural lessons crystals insights; do
    f="$STATE_DIR/mem%3A${s}.bin"
    [ "$(size "$f")" -gt "$SEM_SOFT_BYTES" ] && log "WARNING: mem:$s ($(size "$f")B) growing; prune manually"
  done
}

log "starting (snapshots every ${SNAPSHOT_INTERVAL}s, pruning every ${PRUNE_INTERVAL}s)"
last_snapshot=0
last_prune=0
while true; do
  now=$(date +%s)
  if [ $((now - last_snapshot)) -ge "$SNAPSHOT_INTERVAL" ]; then
    if wait_healthy; then snapshot "scheduled"; last_snapshot=$(date +%s); fi
  fi
  if [ $((now - last_prune)) -ge "$PRUNE_INTERVAL" ]; then
    if wait_healthy; then prune; last_prune=$(date +%s); fi
  fi
  sleep 60
done
