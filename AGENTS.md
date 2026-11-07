# AGENTS.md

## MEMORY-FIRST Protocol (MANDATORY — ZERO EXCEPTIONS)

Applies every turn without exception. No task too small, simple, or urgent to skip.

### Mandatory First Action

Before ANY response, tool call, or reasoning — query memory. Includes trivial questions, greetings, one-line fixes, "quick" answers.

### Consequences of Non-Compliance

Skipping memory retrieval = protocol violation. Training data or "common knowledge" contradict project standards. Memory wins always.

### Compliance Steps (Non-Negotiable)

1. First action each turn: Call `memory_recall` or `memory_smart_search`.
2. Query scope: Retrieve all relevant past observations, lessons, and decisions for current topic.
3. After retrieval: Proceed with reasoning. Memory ALWAYS wins over assumption.
4. Empty results: State "No relevant memory found" then proceed.
5. No exemptions. Model size, task complexity, time pressure — none excuse skipping.

### Common Failures (Strictly Prohibited)

- Answering from training data before checking memory.
- Treating memory as optional for "simple" or "obvious" tasks.
- Calling memory and ignoring results.
- Skipping retrieval for any reason, including speed or cost.
