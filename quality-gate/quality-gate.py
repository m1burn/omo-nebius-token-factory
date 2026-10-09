#!/usr/bin/env python3
"""Unified quality gate runner (orchestrator).

Discovers the candidate files, then runs every Analyzer registered in
analyzers/ (one class per file; registry order = report row order) and
accumulates [PASS]/[FAIL]/[SKIP] per tool group.
Exit 1 iff any group FAILs, 2 on misuse.
Writes nothing outside /tmp. Installs nothing. Fixes nothing.
"""

import argparse
import os
import shutil
import subprocess
import sys

from analyzers import ANALYZERS
from analyzers.context import RunContext
from analyzers.discovery import discover_files
from analyzers.excludes import vendor_excludes
from analyzers.reporter import Reporter
from analyzers.result import AnalyzerResult
from analyzers.toolrun import ToolError

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
NOT_GIT_MSG = "quality-gate: not a git repo \u2014 use --all or --dir"
EXIT_MISUSE = 2


def die(msg):
    """Exit 2 with a misuse message, mirroring the bash die_misuse shape."""
    print(f"quality-gate: {msg}", file=sys.stderr)
    print("Try 'quality-gate.py --help'.", file=sys.stderr)
    sys.exit(EXIT_MISUSE)


def tool_list(value):
    """argparse type: comma-separated analyzer names, validated in place."""
    names = value.split(",")
    known = [analyzer.name for analyzer in ANALYZERS]
    for name in names:
        if name not in known:
            raise argparse.ArgumentTypeError(
                f"unknown tool group: {name} (known: {', '.join(known)})"
            )
    return names


def parse_args(argv):
    parser = argparse.ArgumentParser(
        prog="quality-gate.py",
        description="Run all installed language linters over a project.",
        epilog=(
            "tool groups: " + ", ".join(a.name for a in ANALYZERS) + "; dup and"
            " deadcode run only in --all mode. Each group is an Analyzer"
            " class in quality-gate/analyzers/<group>.py implementing the shared"
            " interface; an absent tool binary is a SKIP.\n"
            "\n"
            "environment: QC_STRICT=1 selects shellcheck -S style (default"
            " -S warning) and eslint --max-warnings=0; QC_DOTNET=0 skips"
            " the cs (dotnet) group.\n"
            "\n"
            "exit codes: 0 = no failures, 1 = at least one group FAIL,"
            " 2 = misuse / not a git repo."
        ),
    )
    modes = parser.add_mutually_exclusive_group()
    modes.add_argument(
        "--changed", action="store_const", dest="mode", const="changed",
        help="scan files changed vs HEAD plus untracked files (git CWD) [default]",
    )
    modes.add_argument(
        "--all", action="store_const", dest="mode", const="all",
        help="walk the current directory recursively",
    )
    modes.add_argument(
        "--dir", dest="dir_arg", metavar="PATH",
        help="scan an explicit path (vendor excludes NOT applied)",
    )
    parser.add_argument(
        "--tool", type=tool_list, metavar="NAME[,NAME...]",
        help="run ONLY the named tool groups",
    )
    parser.add_argument(
        "--skip", type=tool_list, metavar="NAME[,NAME...]",
        help="skip the named tool groups",
    )
    parser.add_argument(
        "--json", action="store_true",
        help="machine summary to stdout, human log to stderr",
    )
    parser.set_defaults(mode="changed")
    args = parser.parse_args(argv)
    if args.dir_arg is not None:
        args.mode = "dir"
        if not os.path.isdir(args.dir_arg):
            die(f"--dir path does not exist or is not a directory: {args.dir_arg}")
    return args


def group_selected(name, only_tools, skip_tools):
    if only_tools is not None and name not in only_tools:
        return False
    return skip_tools is None or name not in skip_tools


def ensure_git_repo():
    proc = subprocess.run(
        ["git", "rev-parse", "--is-inside-work-tree"],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False,
    )
    if proc.returncode:
        print(NOT_GIT_MSG, file=sys.stderr)
        sys.exit(EXIT_MISUSE)


def run_analyzer(analyzer, files, ctx, reporter):
    try:
        result = analyzer.run(files, ctx)
    except ToolError as exc:
        # A tool exited outside its documented codes: a marked FAIL row,
        # not a crash of the whole report.
        result = AnalyzerResult.execution_error(
            exc.tool, exc.rc, exc.lines, exc.files
        )
    except Exception as exc:
        # A crashing analyzer must not kill the report either.
        result = AnalyzerResult.failed(0, 1, (f"analyzer crashed: {exc}",))
    reporter.record(analyzer.name, result)


def main(argv=None):
    args = parse_args(argv)
    scan_root = os.getcwd() if args.mode != "dir" else os.path.abspath(args.dir_arg)
    if args.mode == "changed":
        ensure_git_repo()
    excludes = vendor_excludes()
    dotnet_artifacts = f"/tmp/qc-dotnet-{os.getpid()}"
    os.makedirs(dotnet_artifacts, exist_ok=True)
    try:
        files = discover_files(args.mode, scan_root, excludes)
        ctx = RunContext(
            scan_root=scan_root,
            mode=args.mode,
            repo_root=os.path.dirname(SCRIPT_DIR),
            strict=os.environ.get("QC_STRICT") == "1",
            dotnet_enabled=os.environ.get("QC_DOTNET", "1") != "0",
            dotnet_artifacts=dotnet_artifacts,
        )
        reporter = Reporter(args.json)
        for analyzer in ANALYZERS:
            if group_selected(analyzer.name, args.tool, args.skip):
                run_analyzer(analyzer, files, ctx, reporter)
        reporter.log(reporter.summary_line())
        if args.json:
            print(reporter.json_line(args.mode, scan_root))
        sys.exit(1 if reporter.counts["FAIL"] > 0 else 0)
    finally:
        shutil.rmtree(dotnet_artifacts, ignore_errors=True)


if __name__ == "__main__":
    main()
