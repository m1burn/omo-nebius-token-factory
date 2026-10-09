"""jscpd copy-paste duplication scan (whole tree, --all mode only)."""

import shutil

from analyzers.analyzer import Analyzer
from analyzers.counters import last_int
from analyzers.excludes import vendor_excludes
from analyzers.result import AnalyzerResult
from analyzers.toolrun import run_tool

CLONES = r"Found ([0-9]+) clones"


class DupAnalyzer(Analyzer):
    name = "dup"

    def run(self, files, ctx):
        if ctx.mode != "all":
            return AnalyzerResult.skipped(0, "requires --all")
        if shutil.which("jscpd") is None:
            return AnalyzerResult.skipped(0, "not installed")
        if not files:
            return AnalyzerResult.skipped(0, "no files to scan")
        # jscpd gets the raw root, so the vendor excludes must be forwarded
        # as ignore globs (file-discovery filtering does not apply to it).
        ignores = ",".join(f"**/{ex}/**" for ex in vendor_excludes())
        # jscpd rc semantics are undocumented; any nonzero rc with zero
        # clones still counts as a finding below.
        rc, out = run_tool(
            [
                "jscpd", ctx.scan_root, "--min-tokens", "50",
                "--reporters", "consoleFull", "--ignore", ignores,
            ],
            tool="jscpd",
        )
        findings = last_int(out, CLONES)
        if rc != 0 and findings == 0:
            findings = 1
        if findings:
            return AnalyzerResult.failed(len(files), findings, out)
        return AnalyzerResult.passed(len(files))
