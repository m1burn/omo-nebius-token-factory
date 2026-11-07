"""knip dead-code over package.json dirs (--all mode only)."""

import os
import shutil

from analyzers.analyzer import Analyzer
from analyzers.counters import sum_ints
from analyzers.result import AnalyzerResult
from analyzers.toolrun import run_tool

COUNT = r"\(([0-9]+)\)$"  # knip's trailing per-section "(N)" counters


class DeadcodeAnalyzer(Analyzer):
    name = "deadcode"

    def run(self, files, ctx):
        if ctx.mode != "all":
            return AnalyzerResult.skipped(0, "requires --all")
        if shutil.which("knip") is None:
            return AnalyzerResult.skipped(0, "not installed")
        pkg_dirs = []
        for f in files:
            if f.rsplit("/", 1)[-1] != "package.json":
                continue
            d = os.path.dirname(f)
            if d not in pkg_dirs:
                pkg_dirs.append(d)
        if not pkg_dirs:
            return AnalyzerResult.skipped(0, "no package.json found")
        findings = 0
        detail = []
        for d in pkg_dirs:
            rc, out = run_tool(
                ["knip", "--no-progress"],
                tool="knip", ok_rc=(0, 1), files=len(pkg_dirs),
                cwd=os.path.join(ctx.scan_root, d),
            )
            if rc != 0:
                findings += sum_ints(out, COUNT) or 1
                detail.extend(out)
        return AnalyzerResult.emit(
            1 if findings else 0, len(pkg_dirs), findings, detail
        )
