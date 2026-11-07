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
#  [F] Orphaned search-index generations are never GC'd upstream.
#      IndexPersistence re-serializes the WHOLE BM25/vector index into a NEW
#      generation of ~2MB shards on every debounced save, then best-effort
#      deletes the previous generation (src/state/index-persistence.ts,
#      saveShardedIndex -> previous_generation_cleanup). Failed deletes are
#      only audited, never retried; load() reads only the manifest's
#      generation, so orphans are pure dead weight: the engine's file_based
#      KV loads every shard file into RAM (RSS + boot time), and each save
#      rewrites the full ~370MB live generation through the bridge. Observed
#      2026-09-22: 6 dead BM25 + 3 dead vector generations (~805MB), live
#      serialized index 367MB for 177MB of observations
#      (SearchIndex.serialize JSON-stringifies the corpus,
#      src/state/search-index.ts:194), engine RSS 5.7GB pinned at 100% CPU,
#      worker heap 91-95%+ -> Health: critical.
#      => gc_index_orphans below: keep only the manifest generations,
#         archive the rest. Requires grep -P. Restart needed for the engine
#         to release the deleted state, so it stops/starts like the wipes.
#
# Design note: snapshot-before-prune guarantees evicted/reset data stays
# restorable from git history under $SNAPSHOT_DIR.
set -u

STATE_DIR=/data/state_store.db
ARCHIVE_DIR=/data/archive

SEM_SOFT_BYTES=$((4  * 1024 * 1024))   # mem:semantic -> retention-evict
GRAPH_SOFT_BYTES=$((15 * 1024 * 1024)) # graph:nodes -> mem::graph-reset
GRAPH_HARD_BYTES=$((30 * 1024 * 1024)) # all graph *.bin -> physical wipe
INSIGHTS_HARD_BYTES=$((16 * 1024 * 1024)) # mem:insights -> physical archive (see [E]; <18.7MiB empirically-fatal on this stack, see lsn_8c7424da07feeb0b)
EVICT_THRESHOLD=0.55                   # retention-score cutoff; lower = keep more
EVICT_MAX=1000                         # max evictions per prune pass
PRUNE_INTERVAL=86400                   # daily pruning cadence
INDEX_GC_MIN_BYTES=$((50 * 1024 * 1024)) # min orphan bytes before a stop/restart GC is worth it

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

# setsid so the restarted agentmemory survives teardown of whatever shell
# invoked the housekeeping pass (plain nohup died with the pass in practice).
start_agentmemory() {
  ( cd /home/omo/.omo-agentmemory && setsid agentmemory >/dev/null 2>&1 & )
  wait_healthy || return 1
}

wipe_graph() {
  local dest="$ARCHIVE_DIR/graph-$(date +%Y%m%d-%H%M%S)"
  agentmemory stop >/dev/null 2>&1; sleep 3
  mkdir -p "$dest"; mv "$STATE_DIR"/mem%3Agraph%3A*.bin "$dest/" 2>/dev/null
  start_agentmemory
}

# [E] physical prune for mem:insights — the scope has no logical eviction
# path, so over hard-cap it is archived and re-derived by future reflects.
wipe_insights() {
  local dest="$ARCHIVE_DIR/insights-$(date +%Y%m%d-%H%M%S)"
  agentmemory stop >/dev/null 2>&1; sleep 3
  mkdir -p "$dest"; mv "$STATE_DIR/mem%3Ainsights.bin" "$dest/" 2>/dev/null
  start_agentmemory
}

manifest_gen() { # $1 = manifest entry prefix: "data" (bm25) or "vectors"
  grep -aoP "\"$1:manifest\":\{\"chars\":[0-9]+,\"generation\":\"\K[^\"]+" \
    "$STATE_DIR/mem%3Aindex%3Abm25.bin" 2>/dev/null | head -1
}

# [F] keep only the manifest's live index generations; archive orphan shards
# and stale .tmp partial writes. Stop/start like the wipes so no save is
# mid-flight while files move and the engine releases the deleted state.
gc_index_orphans() {
  local bm_gen vec_gen f orphan_bytes=0 orphan_count=0 dest
  [ -f "$STATE_DIR/mem%3Aindex%3Abm25.bin" ] || return 0
  bm_gen=$(manifest_gen data)
  vec_gen=$(manifest_gen vectors)
  [[ "$bm_gen" == idx_* ]] || { log "index-gc: live generation unreadable; skip"; return 1; }
  : "${vec_gen:=__none__}"
  for f in "$STATE_DIR"/mem%3Aindex%3Abm25%3Abm25%3Aidx_*.bin \
           "$STATE_DIR"/mem%3Aindex%3Abm25%3Avectors%3Aidx_*.bin \
           "$STATE_DIR"/mem%3Aindex%3Abm25%3A*.bin.tmp; do
    [ -e "$f" ] || continue
    case "$f" in *"$bm_gen"*|*"$vec_gen"*) continue ;; esac
    orphan_bytes=$((orphan_bytes + $(stat -c%s "$f")))
    orphan_count=$((orphan_count + 1))
  done
  if [ "$orphan_bytes" -lt "$INDEX_GC_MIN_BYTES" ]; then
    [ "$orphan_count" -gt 0 ] && log "index-gc: ${orphan_count} orphan shard(s) (${orphan_bytes}B) under ${INDEX_GC_MIN_BYTES}B; left in place"
    return 0
  fi
  log "index-gc: ${orphan_count} orphan shards (${orphan_bytes}B); archiving (keeping $bm_gen / $vec_gen)"
  snapshot "pre-index-gc"
  agentmemory stop >/dev/null 2>&1; sleep 3
  bm_gen=$(manifest_gen data); vec_gen=$(manifest_gen vectors)
  [[ "$bm_gen" == idx_* ]] || { log "index-gc: live generation unreadable after stop; abort"; start_agentmemory; return 1; }
  : "${vec_gen:=__none__}"
  dest="$ARCHIVE_DIR/index-gc-$(date +%Y%m%d-%H%M%S)"; mkdir -p "$dest"
  cp "$STATE_DIR/mem%3Aindex%3Abm25.bin" "$dest/manifest-backup.bin" 2>/dev/null
  for f in "$STATE_DIR"/mem%3Aindex%3Abm25%3Abm25%3Aidx_*.bin \
           "$STATE_DIR"/mem%3Aindex%3Abm25%3Avectors%3Aidx_*.bin \
           "$STATE_DIR"/mem%3Aindex%3Abm25%3A*.bin.tmp; do
    [ -e "$f" ] || continue
    case "$f" in *"$bm_gen"*|*"$vec_gen"*) continue ;; esac
    mv "$f" "$dest/"
  done
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
    snapshot "pre-semantic-prune"; prune_semantic
  fi

  if [ "$insights_size" -gt "$INSIGHTS_HARD_BYTES" ]; then
    log "mem:insights ${insights_size}B > hard cap; physical archive (derived scope; reflect rebuilds)"
    snapshot "pre-insights-wipe"; wipe_insights
  fi

  if [ "$graph_size" -gt "$GRAPH_HARD_BYTES" ]; then
    log "graph scopes ${graph_size}B > hard cap; physical wipe"
    snapshot "pre-graph-wipe"; wipe_graph
  elif [ "$graph_nodes_size" -gt "$GRAPH_SOFT_BYTES" ]; then
    log "graph:nodes ${graph_nodes_size}B > soft cap; logical reset (extraction rebuilds)"
    snapshot "pre-graph-reset"; tri mem::graph-reset '{}'
  fi

  gc_index_orphans

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
