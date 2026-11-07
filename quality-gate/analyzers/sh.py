"""shellcheck over bash/sh files."""

import shutil

from analyzers.analyzer import Analyzer
from analyzers.counters import count_matches
from analyzers.result import AnalyzerResult
from analyzers.toolrun import run_tool_batched

FINDING = r"^In .+ line [0-9]+:"


class ShAnalyzer(Analyzer):
    name = "sh"
    extensions = frozenset({"sh", "bash"})

    def run(self, files, ctx):
        gf = self.select(files)
        if shutil.which("shellcheck") is None:
            return AnalyzerResult.skipped(len(gf), "not installed")
        if not gf:
            return AnalyzerResult.skipped(0, "no matching files")
        severity = "style" if ctx.strict else "warning"
        rc, out = run_tool_batched(
            ["shellcheck", "-S", severity], self.abs_paths(gf, ctx),
            tool="shellcheck", ok_rc=(0, 1), files=len(gf),
        )
        return AnalyzerResult.emit(rc, len(gf), count_matches(out, FINDING), out)
