---
description: Run the image-baked CLI quality gates, triage findings, apply minimal fixes, and re-check (max 3 passes)
---

# /quality-gate — local quality gates loop

Me run gates on scope. Gate fail → me fix small. Me run again to prove fix.
Tools baked in image; command only drives them. Fix nothing outside a finding.

**Never:** no git (commit, stage, branch, merge, push, PR) · no touch
outside mounted project · no runtime install (absent tool = SKIP — report
it, never install) · no create/edit tool configs (eslint, yamllint, ruff,
hadolint, gitleaks) · no read or edit `.env.secrets` · no drive-by
refactor/reformat.

## Steps

1. **Preflight** — `command -v` each: `shellcheck hadolint gitleaks
   tflint trivy ruff yamllint eslint jscpd knip markdownlint-cli2 pwsh
   dotnet`. Report RUN vs `[SKIP] (not installed)`; a skip never fails.
2. **Scope** — no arg → `--changed` (git diff + untracked, read-only);
   `--full` → `--all` (whole tree, vendor excluded); `--range A..B` →
   `git diff --name-only A..B`, then `--dir` on the dirs holding those
   files (no per-file mode → whole dirs scanned). Say scope + file count
   before run.
3. **Run** — `/usr/local/bin/quality-gate.py <flags>` (host:
   `quality-gate/quality-gate.py` from repo root). Keep
   `[PASS]/[FAIL]/[SKIP]` output + `SUMMARY` line verbatim.
4. **Triage** — worst first: security (gitleaks secrets, trivy
   misconfig, PSScriptAnalyzer errors) → build/analyzer errors (dotnet,
   eslint, ruff) → warnings → info. Group by tool, then file; one file
   per fix batch.
5. **Fix** — fix all findings. Skip only findings justified in code,
   comment, or doc — leave them, cite where. Flagged lines only, small
   diff, one finding at a time, match nearby style and names. Never
   reformat untouched code, refactor past the finding, or edit config to
   silence a rule. Never suppress.
6. **Re-run + Summary** — same files, same scope. Stop when clean;
   findings left → mark `UNCAPPED-FAIL`.
   End with:

| Tool | Before | After |
| --- | --- | --- |
| (each tool that ran) | n | m |

Plus the final `SUMMARY` line and the skipped-tool list with reasons.
