"""ruff over python files (the repo's rule selection)."""

import shutil

from analyzers.analyzer import Analyzer
from analyzers.counters import count_matches
from analyzers.result import AnalyzerResult
from analyzers.toolrun import run_tool_batched

RULES = "F,B,SIM,C4,PL,RUF,C90"
FINDING = r":[0-9]+:[0-9]+: [A-Z]+[0-9]+ "


class PyAnalyzer(Analyzer):
    name = "py"
    extensions = frozenset({"py", "pyi"})

    def run(self, files, ctx):
        gf = self.select(files)
        if shutil.which("ruff") is None:
            return AnalyzerResult.skipped(len(gf), "not installed")
        if not gf:
            return AnalyzerResult.skipped(0, "no matching files")
        rc, out = run_tool_batched(
            ["ruff", "check", "--select", RULES], self.abs_paths(gf, ctx),
            tool="ruff", ok_rc=(0, 1), files=len(gf),
        )
        return AnalyzerResult.emit(rc, len(gf), count_matches(out, FINDING), out)
