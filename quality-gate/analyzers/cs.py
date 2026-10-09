"""Roslyn analyzers over C# via dotnet build with an analyzer overlay."""

import os
import shutil

from analyzers.analyzer import Analyzer
from analyzers.counters import count_matches
from analyzers.result import AnalyzerResult
from analyzers.toolrun import run_tool

OVERLAY_PATH = os.path.join(
    os.path.dirname(os.path.abspath(__file__)), "cs.analyzers.props"
)
FINDING = r"(warning|error) [A-Z]+[0-9]+"


class CsAnalyzer(Analyzer):
    name = "cs"
    extensions = frozenset({"cs", "csproj", "sln"})

    def run(self, files, ctx):
        gf = self.select(files)
        if not ctx.dotnet_enabled:
            return AnalyzerResult.skipped(len(gf), "QC_DOTNET=0")
        if shutil.which("dotnet") is None:
            return AnalyzerResult.skipped(len(gf), "not installed")
        if not gf:
            return AnalyzerResult.skipped(0, "no matching files")
        overlay = self._overlay()
        if overlay is None:
            return AnalyzerResult.skipped(len(gf), "no analyzers overlay available")
        targets = self._targets(gf, ctx.scan_root)
        if not targets:
            return AnalyzerResult.skipped(len(gf), "no csproj/sln found")
        findings = 0
        detail = []
        for t in targets:
            # nonzero rc = build failure (that IS the finding); no error class
            rc, out = run_tool(
                [
                    "dotnet", "build", t, "-v:q", "--nologo",
                    "--artifacts-path", ctx.dotnet_artifacts,
                    f"-p:CustomAfterMicrosoftCommonProps={overlay}",
                    "-p:EnableNETAnalyzers=true", "-p:AnalysisLevel=latest",
                ],
                tool="dotnet", cwd=ctx.scan_root,
            )
            warns = count_matches(out, FINDING)
            if rc != 0 or warns > 0:
                findings += warns or 1
                detail.extend(out)
        return AnalyzerResult.emit(
            1 if findings else 0, len(gf), findings, detail
        )

    @staticmethod
    def _overlay():
        return OVERLAY_PATH if os.path.isfile(OVERLAY_PATH) else None

    @staticmethod
    def _targets(gf, scan_root):
        targets = []
        for f in gf:
            base = f.rsplit("/", 1)[-1]
            if base.endswith((".csproj", ".sln")):
                cand = f
            elif base.endswith(".cs"):
                cand = CsAnalyzer._nearest_csproj(f, scan_root)
            else:
                cand = None
            if cand and cand not in targets:
                targets.append(cand)
        return targets

    @staticmethod
    def _nearest_csproj(f, scan_root):
        # .cs -> nearest *.csproj walking up; first readdir hit wins (find parity)
        d = os.path.dirname(f)
        while True:
            hit = None
            with os.scandir(os.path.join(scan_root, d)) as entries:
                for entry in entries:
                    if entry.name.endswith(".csproj"):
                        hit = entry.name
                        break
            if hit is not None:
                return f"{d}/{hit}"
            if d in (".", os.path.sep):
                return None
            d = os.path.dirname(d)
