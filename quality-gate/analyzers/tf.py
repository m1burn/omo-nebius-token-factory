"""terraform group: tflint + trivy + terraform validate per module dir.

An uninitialized module is bootstrapped with a backend-less init so
validate can resolve providers without state access or cloud credentials.
"""

import os
import shutil
import sys

from analyzers.analyzer import Analyzer
from analyzers.counters import count_matches
from analyzers.result import AnalyzerResult
from analyzers.toolrun import run_tool

TFLINT_FINDING = r"^(Error|Warning):"
TRIVY_FINDING = r"CRITICAL|HIGH|MEDIUM|LOW"


class TfAnalyzer(Analyzer):
    name = "tf"
    extensions = frozenset({"tf", "tfvars"})

    def run(self, files, ctx):
        gf = self.select(files)
        if not gf:
            return AnalyzerResult.skipped(0, "no matching files")
        if not any(
            shutil.which(t) for t in ("tflint", "trivy", "terraform")
        ):
            return AnalyzerResult.skipped(len(gf), "not installed")
        dirs = []
        for f in gf:
            d = os.path.dirname(f)
            if d not in dirs:
                dirs.append(d)
        findings = 0
        detail = []
        for d in dirs:
            ad = os.path.join(ctx.scan_root, d)
            findings += self._tflint(ad, len(gf), detail)
            findings += self._trivy(ad, len(gf), detail)
            findings += self._validate(ad, d, detail)
        return AnalyzerResult.emit(
            1 if findings else 0, len(gf), findings, detail
        )

    @staticmethod
    def _tflint(ad, files, detail):
        if shutil.which("tflint") is None:
            print("[SKIP] tflint (not installed)", file=sys.stderr)
            return 0
        # tflint: rc 2 = issues found; rc 1 (or >2) = error occurred
        rc, out = run_tool(
            ["tflint", "--chdir", ad], tool="tflint", ok_rc=(0, 2), files=files
        )
        if rc == 0:
            return 0
        counted = count_matches(out, TFLINT_FINDING) or 1
        detail.extend(out)
        return counted

    @staticmethod
    def _trivy(ad, files, detail):
        if shutil.which("trivy") is None:
            print("[SKIP] trivy (not installed)", file=sys.stderr)
            return 0
        # --exit-code 1: trivy defaults to exit 0 even with findings.
        rc, out = run_tool(
            ["trivy", "config", "--skip-policy-update", "--exit-code", "1", ad],
            tool="trivy", ok_rc=(0, 1), files=files,
        )
        if rc == 0:
            return 0
        counted = count_matches(out, TRIVY_FINDING) or 1
        detail.extend(out)
        return counted

    @staticmethod
    def _validate(ad, rel_dir, detail):
        if shutil.which("terraform") is None:
            print("[SKIP] terraform (not installed)", file=sys.stderr)
            return 0
        if not os.path.isdir(os.path.join(ad, ".terraform")):
            # validate needs the provider plugins init installs into
            # .terraform/; bootstrap them backend-less (no state, no login)
            rc, out = run_tool(
                [
                    "terraform", f"-chdir={ad}", "init",
                    "-backend=false", "-input=false",
                ],
                tool="terraform",
            )
            if rc != 0:
                print(
                    f"[SKIP] terraform ({rel_dir} init failed)",
                    file=sys.stderr,
                )
                detail.extend(out)
                return 0
        # nonzero rc = invalid config (that IS the finding); no error class
        rc, out = run_tool(
            ["terraform", f"-chdir={ad}", "validate"], tool="terraform"
        )
        if rc == 0:
            return 0
        detail.extend(out)
        return 1
