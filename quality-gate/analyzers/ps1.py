"""PSScriptAnalyzer over PowerShell files (pwsh hosts the module)."""

import os
import shutil

from analyzers.analyzer import Analyzer
from analyzers.result import AnalyzerResult
from analyzers.toolrun import run_tool

MODULE_PROBE = (
    "if (Get-Module -ListAvailable PSScriptAnalyzer) { exit 0 } else { exit 1 }"
)
ANALYZE = (
    "Invoke-ScriptAnalyzer -Path {paths} -Severity Error,Warning "
    '| ForEach-Object {{ "$($_.ScriptName):$($_.Line): '
    '$($_.Severity) $($_.RuleName) $($_.Message)" }}'
)


class Ps1Analyzer(Analyzer):
    name = "ps1"
    extensions = frozenset({"ps1", "psm1", "psd1"})

    def run(self, files, ctx):
        gf = self.select(files)
        if shutil.which("pwsh") is None:
            return AnalyzerResult.skipped(len(gf), "not installed")
        rc, _probe = run_tool(
            ["pwsh", "-NoProfile", "-Command", MODULE_PROBE], tool="pwsh"
        )
        if rc != 0:
            return AnalyzerResult.skipped(len(gf), "PSScriptAnalyzer not installed")
        if not gf:
            return AnalyzerResult.skipped(0, "no matching files")
        paths = ",".join(f"'{os.path.join(ctx.scan_root, f)}'" for f in gf)
        # PSSA reports findings via output lines, not exit codes; any
        # nonzero rc is an execution error.
        rc, out = run_tool(
            ["pwsh", "-NoProfile", "-Command", ANALYZE.format(paths=paths)],
            tool="pwsh", ok_rc=(0,), files=len(gf),
        )
        findings = sum(1 for line in out if line)
        if findings:
            return AnalyzerResult.failed(len(gf), findings, out)
        return AnalyzerResult.passed(len(gf))
