"""markdownlint-cli2 over markdown files."""

import shutil

from analyzers.analyzer import Analyzer
from analyzers.counters import count_matches, first_int, last_matching_line
from analyzers.result import AnalyzerResult
from analyzers.toolrun import run_tool_batched

SUMMARY = r"Summary: [0-9]+ error"
FALLBACK = r":[0-9]+(:[0-9]+)? MD[0-9]+"


class MdAnalyzer(Analyzer):
    name = "md"
    extensions = frozenset({"md", "markdown"})

    def run(self, files, ctx):
        gf = self.select(files)
        if shutil.which("markdownlint-cli2") is None:
            return AnalyzerResult.skipped(len(gf), "not installed")
        if not gf:
            return AnalyzerResult.skipped(0, "no matching files")
        rc, out = run_tool_batched(
            ["markdownlint-cli2"], self.abs_paths(gf, ctx),
            tool="markdownlint-cli2", ok_rc=(0, 1), files=len(gf),
        )
        summary = last_matching_line(out, SUMMARY)
        if summary is not None:
            finds = first_int(summary, r"([0-9]+)")
        else:
            finds = count_matches(out, FALLBACK)
        return AnalyzerResult.emit(rc, len(gf), finds, out)
