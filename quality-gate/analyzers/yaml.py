"""yamllint over YAML files."""

import shutil

from analyzers.analyzer import Analyzer
from analyzers.counters import count_matches
from analyzers.result import AnalyzerResult
from analyzers.toolrun import run_tool_batched

FINDING = r"^\s*[0-9]+:[0-9]+\s+(error|warning)\s"


class YamlAnalyzer(Analyzer):
    name = "yaml"
    extensions = frozenset({"yml", "yaml"})

    def run(self, files, ctx):
        gf = self.select(files)
        if shutil.which("yamllint") is None:
            return AnalyzerResult.skipped(len(gf), "not installed")
        if not gf:
            return AnalyzerResult.skipped(0, "no matching files")
        rc, out = run_tool_batched(
            ["yamllint"], self.abs_paths(gf, ctx),
            tool="yamllint", ok_rc=(0, 1), files=len(gf),
        )
        return AnalyzerResult.emit(rc, len(gf), count_matches(out, FINDING), out)
