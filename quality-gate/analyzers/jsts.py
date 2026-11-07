"""eslint over js/ts files (repo config wins; see also deadcode.py)."""

import os
import shutil

from analyzers.analyzer import Analyzer
from analyzers.counters import first_int, last_matching_line
from analyzers.result import AnalyzerResult
from analyzers.toolrun import run_tool_batched

CONFIG_NAMES = ("eslint.config.js", "eslint.config.mjs", "eslint.config.cjs")
SUMMARY = r"problem[s]? \("

FALLBACK_CONFIG_PATH = os.path.join(
    os.path.dirname(os.path.abspath(__file__)), "jsts.eslint.config.mjs"
)
ANCHOR_ENV = "QC_ESLINT_ANCHOR"


def find_repo_config():
    directory = os.getcwd()
    while True:
        for name in CONFIG_NAMES:
            candidate = os.path.join(directory, name)
            if os.path.isfile(candidate):
                return candidate
        if directory == os.path.sep:
            return None
        directory = os.path.dirname(directory)


def eslint_package_json():
    bin_path = shutil.which("eslint")
    if bin_path is None:
        return None
    pkg_json = os.path.join(
        os.path.dirname(os.path.dirname(os.path.realpath(bin_path))), "package.json"
    )
    return pkg_json if os.path.isfile(pkg_json) else None


class JstsAnalyzer(Analyzer):
    name = "jsts"
    extensions = frozenset({"js", "mjs", "cjs", "ts", "mts", "cts", "jsx", "tsx"})

    def run(self, files, ctx):
        gf = self.select(files)
        if shutil.which("eslint") is None:
            return AnalyzerResult.skipped(len(gf), "not installed")
        if not gf:
            return AnalyzerResult.skipped(0, "no matching files")
        repo_cfg = find_repo_config()
        if repo_cfg is not None:
            return self._lint(repo_cfg, False, gf, ctx)
        anchor = eslint_package_json()
        if anchor is None or not os.path.isfile(FALLBACK_CONFIG_PATH):
            return AnalyzerResult.skipped(len(gf), "no eslint config available")
        env = {**os.environ, ANCHOR_ENV: anchor}
        return self._lint(FALLBACK_CONFIG_PATH, True, gf, ctx, env)

    def _lint(self, cfg, lookup_blocked, gf, ctx, env=None):
        argv = ["eslint", "--config", cfg, "--no-error-on-unmatched-pattern"]
        if lookup_blocked:
            argv.append("--no-config-lookup")
        if ctx.strict:
            argv.append("--max-warnings=0")
        rc, out = run_tool_batched(
            argv, self.abs_paths(gf, ctx),
            tool="eslint", ok_rc=(0, 1), files=len(gf), cwd=ctx.scan_root, env=env,
        )
        summary = last_matching_line(out, SUMMARY)
        finds = first_int(summary, r"([0-9]+) problem") if summary else 0
        return AnalyzerResult.emit(rc, len(gf), finds, out)
