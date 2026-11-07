"""gitleaks over the raw scan root (vendored code included)."""

import shutil

from analyzers.analyzer import Analyzer
from analyzers.counters import count_matches
from analyzers.result import AnalyzerResult
from analyzers.toolrun import run_tool

FINDING = r"^RuleID:"
# gitleaks 8.24.3: `dir` is inherently non-git (--no-git was removed from
# the CLI); -v prints the per-finding blocks the RuleID counter greps.


class SecretsAnalyzer(Analyzer):
    name = "secrets"

    def run(self, files, ctx):
        if shutil.which("gitleaks") is None:
            return AnalyzerResult.skipped(0, "not installed")
        if not files:
            return AnalyzerResult.skipped(0, "no files to scan")
        rc, out = run_tool(
            ["gitleaks", "dir", "-v", "--redact", "--no-banner", ctx.scan_root],
            tool="gitleaks", ok_rc=(0, 1), files=len(files),
        )
        return AnalyzerResult.emit(
            rc, len(files), count_matches(out, FINDING), out
        )
