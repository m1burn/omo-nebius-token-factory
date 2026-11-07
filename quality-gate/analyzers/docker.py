"""hadolint over Dockerfiles (name-based selection, not extension)."""

import shutil

from analyzers.analyzer import Analyzer
from analyzers.counters import count_matches
from analyzers.result import AnalyzerResult
from analyzers.toolrun import run_tool_batched

FINDING = r":[0-9]+ [A-Z]+[0-9]+ "


class DockerAnalyzer(Analyzer):
    name = "docker"

    def match(self, rel_path):
        base = rel_path.rsplit("/", 1)[-1]
        return (
            base == "Dockerfile"
            or base.startswith("Dockerfile.")
            or base.endswith(".Dockerfile")
        )

    def run(self, files, ctx):
        gf = self.select(files)
        if shutil.which("hadolint") is None:
            return AnalyzerResult.skipped(len(gf), "not installed")
        if not gf:
            return AnalyzerResult.skipped(0, "no matching files")
        rc, out = run_tool_batched(
            ["hadolint"], self.abs_paths(gf, ctx),
            tool="hadolint", ok_rc=(0, 1), files=len(gf),
        )
        return AnalyzerResult.emit(rc, len(gf), count_matches(out, FINDING), out)
