# AGENTS.md

## Runtime environment

- You run inside a Docker container. No direct host access.
- Only `/home/omo/project` is shared with the host.
- No shared auth sessions with the host. This blocks access to live environments. Ask the human to run commands/scripts there and post results back for validation.
- Missing software? Install it inside the container yourself.

## MEMORY-FIRST Protocol

Query memory first. Every turn. No exceptions.

1. Before any response or tool call, run `memory_recall` or `memory_smart_search`.
2. Get relevant observations, lessons, and decisions.
3. Then reason. Memory beats assumptions.
4. Empty results? Say "No relevant memory found" and continue.
5. No exemptions. Not for simple, quick, urgent, or cheap tasks.

Never:
- Answer from training data before checking memory.
- Treat memory as optional.
- Ignore memory results.
- Skip retrieval to save time or cost.
