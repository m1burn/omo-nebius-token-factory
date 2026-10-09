"""QA suite for the image-baked CLI quality-gates stack.

Pytest port of the former ``test-quality-tools.sh`` (phases T0-T7).
Run from the repository root:

    pytest tests/test-quality-gate.py

An absent external tool is a SKIP, never a FAIL, matching the runner's own
contract; the suite exits non-zero only when a check FAILs. Scratch dirs come
from pytest's ``tmp_path``, so the suite leaves nothing behind.
"""

from __future__ import annotations

import json
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parent.parent
FIXTURES = REPO_ROOT / "tests" / "fixtures" / "quality-gate"
RUNNER = REPO_ROOT / "quality-gate" / "quality-gate.py"
CS_OVERLAY = REPO_ROOT / "quality-gate" / "analyzers" / "cs.analyzers.props"

EXIT_CLEAN = 0
EXIT_FINDINGS = 1
EXIT_MISUSE = 2
MIN_FINDINGS = 1
EXPECTED_CHANGED_FILES = 2

RUFF_RULES = "F,B,SIM,C4,PL,RUF,C90"
# ruff >=0.16 defaults to the multi-line "full" format, where the old
# "path:line:col:" shape no longer appears; count rule ids instead.
RUFF_FINDING = re.compile(r"\b[A-Z]+\d+\b")
SHELLCHECK_FINDING = re.compile(r"^In .+ line \d+:")
HADOLINT_FINDING = re.compile(r":\d+ [A-Z]+\d+ ")
YAMLLINT_FINDING = re.compile(r"^\s*\d+:\d+\s+(error|warning)\s")
MARKDOWNLINT_FINDING = re.compile(r"MD\d+")
TFLINT_FINDING = re.compile(r": (Warning|Error) -")
TRIVY_FINDING = re.compile(r"avd-|CRITICAL|HIGH|MEDIUM|LOW|MISCONFIG")
DOTNET_FINDING = re.compile(r"(warning|error) [A-Z]+\d+")
JSCPD_CLONES = re.compile(r"Found (\d+) clones")

VERSION_TOOLS = (
    ("shellcheck", ("--version",)),
    ("hadolint", ("--version",)),
    ("gitleaks", ("version",)),
    ("tflint", ("--version",)),
    ("trivy", ("--version",)),
    ("ruff", ("--version",)),
    ("yamllint", ("--version",)),
    ("eslint", ("--version",)),
    ("jscpd", ("--version",)),
    ("knip", ("--version",)),
    ("markdownlint-cli2", ("--version",)),
)

_PSA_PATH = str(FIXTURES / "bad.ps1")
_PSA_COMMAND = (
    f"Invoke-ScriptAnalyzer -Path '{_PSA_PATH}' -Severity Error,Warning | "
    'ForEach-Object { "$($_.ScriptName):$($_.Line): $($_.Severity) '
    '$($_.RuleName) $($_.Message)" }'
)


def have(tool):
    """True when the external tool is on PATH."""
    return shutil.which(tool) is not None


def require(tool):
    """Skip the current test when its external tool is absent."""
    if not have(tool):
        pytest.skip(f"{tool} not installed")


def run(argv, **kwargs):
    """Run a command, merging stderr into stdout; return (rc, output)."""
    proc = subprocess.run(
        argv,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        check=False,
        **kwargs,
    )
    return proc.returncode, proc.stdout


def run_split(argv, **kwargs):
    """Run a command keeping stdout and stderr separate; return (rc, out, err)."""
    proc = subprocess.run(
        argv,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        check=False,
        **kwargs,
    )
    return proc.returncode, proc.stdout, proc.stderr


def count_matches(pattern, text):
    """Number of lines matching the pattern (grep -cE parity)."""
    return sum(1 for line in text.splitlines() if pattern.search(line))


def _last_int(pattern, text):
    hits = pattern.findall(text)
    return int(hits[-1]) if hits else 0


def _pwsh_has_module(name):
    rc, _ = run(
        [
            "pwsh",
            "-NoProfile",
            "-Command",
            f"if (Get-Module -ListAvailable {name}) {{ exit 0 }} else {{ exit 1 }}",
        ]
    )
    return rc == EXIT_CLEAN


def _shell_file(body):
    return f"#!/usr/bin/env bash\nset -euo pipefail\nprintf '%s\\n' \"{body}\"\n"


def _fixture_copy(dest):
    """Copy the planted-violation fixtures so runner runs never mutate them.

    The tf analyzer bootstraps modules with a backend-less ``terraform init``
    inside the scanned dir, which drops ``.terraform/``; scanning a disposable
    copy keeps ``tests/fixtures/quality-gate`` pristine.
    """
    shutil.copytree(
        FIXTURES,
        dest,
        ignore=shutil.ignore_patterns(
            ".terraform", ".terraform.lock.hcl", "__pycache__"
        ),
    )
    return dest


def _first_stray_build_dir(root):
    for dirpath, dirnames, _ in os.walk(root):
        for name in dirnames:
            if name in ("bin", "obj"):
                return os.path.join(dirpath, name)
    return None


@pytest.fixture(scope="session", autouse=True)
def _fixture_dir_present():
    """Abort early when the planted-violation fixtures are missing."""
    if not FIXTURES.is_dir():
        pytest.exit(f"tests/fixtures/quality-gate not found: {FIXTURES}", returncode=1)


# ------------------------------------------------------------- T0 versions --
@pytest.mark.parametrize(
    ("tool", "args"), VERSION_TOOLS, ids=[name for name, _ in VERSION_TOOLS]
)
def test_t0_tool_version(tool, args):
    require(tool)
    rc, out = run([tool, *args])
    assert rc == EXIT_CLEAN, f"{tool} {' '.join(args)} exited {rc}: {out.strip()}"
    assert out.strip(), f"{tool} produced no version output"


def test_t0_pwsh_version():
    require("pwsh")
    rc, out = run(
        ["pwsh", "-NoProfile", "-Command", "$PSVersionTable.PSVersion.ToString()"]
    )
    assert rc == EXIT_CLEAN and out.strip(), "pwsh produced no version output"


def test_t0_pwsh_modules():
    require("pwsh")
    missing = [
        name for name in ("PSScriptAnalyzer", "Pester") if not _pwsh_has_module(name)
    ]
    if missing:
        pytest.skip(f"pwsh modules missing: {', '.join(missing)}")


def test_t0_dotnet_sdk():
    require("dotnet")
    rc, out = run(["dotnet", "--list-sdks"])
    assert rc == EXIT_CLEAN and out.strip(), "dotnet present but no SDK in --list-sdks"


# --------------------------------------------------- T1 fixture detection --
def test_t1_shellcheck_flags_bad_sh():
    require("shellcheck")
    rc, out = run(["shellcheck", str(FIXTURES / "bad.sh")])
    assert rc != EXIT_CLEAN and count_matches(SHELLCHECK_FINDING, out) >= MIN_FINDINGS


def test_t1_hadolint_flags_bad_dockerfile():
    require("hadolint")
    rc, out = run(["hadolint", str(FIXTURES / "bad.Dockerfile")])
    assert rc != EXIT_CLEAN and count_matches(HADOLINT_FINDING, out) >= MIN_FINDINGS


def test_t1_ruff_flags_bad_py():
    require("ruff")
    rc, out = run(["ruff", "check", "--select", RUFF_RULES, str(FIXTURES / "bad.py")])
    assert rc != EXIT_CLEAN and count_matches(RUFF_FINDING, out) >= MIN_FINDINGS


def test_t1_eslint_flags_bad_ts(tmp_path):
    require("eslint")
    shutil.copy(FIXTURES / "bad.ts", tmp_path / "bad.ts")
    _, out, _ = run_split(
        [sys.executable, str(RUNNER), "--dir", str(tmp_path), "--tool", "jsts", "--json"]
    )
    payload = json.loads(out) if out.strip() else {}
    row = next((t for t in payload.get("tools", ()) if t["tool"] == "jsts"), None)
    assert row is not None, "runner reported no jsts row"
    if row["status"] == "SKIP":
        pytest.skip("jsts skipped")
    assert row["status"] == "FAIL" and row["findings"] >= MIN_FINDINGS, row


def test_t1_yamllint_flags_bad_yml():
    require("yamllint")
    rc, out = run(["yamllint", str(FIXTURES / "bad.yml")])
    assert rc != EXIT_CLEAN and count_matches(YAMLLINT_FINDING, out) >= MIN_FINDINGS


def test_t1_markdownlint_flags_bad_md():
    require("markdownlint-cli2")
    rc, out = run(["markdownlint-cli2", str(FIXTURES / "bad.md")])
    assert rc != EXIT_CLEAN and count_matches(MARKDOWNLINT_FINDING, out) >= MIN_FINDINGS


def test_t1_tflint_flags_bad_tf():
    require("tflint")
    rc, out = run(["tflint", "--chdir", str(FIXTURES), "--format", "compact"])
    assert rc == EXIT_MISUSE and TFLINT_FINDING.search(out), (
        f"rc={rc} (expected 2=issues-found with finding lines)"
    )


def test_t1_trivy_flags_bad_tf():
    require("trivy")
    rc, out = run(
        ["trivy", "config", "--skip-policy-update", "--exit-code", "1", str(FIXTURES)]
    )
    assert rc != EXIT_CLEAN and TRIVY_FINDING.search(out), f"rc={rc} no misconfig evidence"


@pytest.fixture(scope="module")
def bad_ps1_output():
    if not have("pwsh") or not _pwsh_has_module("PSScriptAnalyzer"):
        pytest.skip("pwsh/PSScriptAnalyzer not installed")
    _, out = run(["pwsh", "-NoProfile", "-Command", _PSA_COMMAND])
    return out


def test_t1_psscriptanalyzer_flags_bad_ps1(bad_ps1_output):
    diagnostics = sum(1 for line in bad_ps1_output.splitlines() if line.strip())
    assert diagnostics >= MIN_FINDINGS, "0 diagnostics"


def test_t1_gitleaks_flags_fixture_dir():
    require("gitleaks")
    rc, out = run(["gitleaks", "dir", "-v", "--redact", "--no-banner", str(FIXTURES)])
    leaks = sum(1 for line in out.splitlines() if "RuleID:" in line)
    assert rc != EXIT_CLEAN and leaks >= MIN_FINDINGS, f"rc={rc} leaks={leaks}"


def test_t1_jscpd_flags_dup_pair(tmp_path):
    require("jscpd")
    rc, out = run(
        [
            "jscpd",
            "--min-tokens",
            "50",
            "--reporters",
            "consoleFull",
            "--output",
            str(tmp_path),
            str(FIXTURES / "dup-a.ts"),
            str(FIXTURES / "dup-b.ts"),
        ]
    )
    clones = _last_int(JSCPD_CLONES, out)
    assert clones >= MIN_FINDINGS or rc != EXIT_CLEAN, f"rc={rc} clones={clones}"


# ----------------------------------------------- T2 runner exit codes --
def test_t2_dirty_fixture_dir_exits_one(tmp_path):
    scan = _fixture_copy(tmp_path / "fixtures")
    rc, out, _ = run_split(
        [sys.executable, str(RUNNER), "--dir", str(scan), "--json"]
    )
    if rc == EXIT_FINDINGS:
        return
    assert rc == EXIT_CLEAN, f"runner exit={rc} (expected 1; 2 would mean misuse)"
    assert out.strip(), f"no valid JSON from runner (exit={rc})"
    payload = json.loads(out)
    fail = payload["summary"]["fail"]
    ran = sum(1 for t in payload["tools"] if t["status"] in ("PASS", "FAIL"))
    vacuous = sum(
        1
        for t in payload["tools"]
        if t["tool"] == "tf" and t["status"] == "PASS" and t["findings"] == 0
    )
    assert fail == 0, f"exit=0 with fail={fail} (runner contract broken)"
    if ran - vacuous > 0:
        pytest.fail(
            f"exit=0 — {ran - vacuous} group(s) ran on dirty fixtures without findings"
        )
    pytest.skip("no linter installed (only vacuous group PASS), exit=0")


def test_t2_clean_dir_exits_zero(tmp_path):
    (tmp_path / "clean.py").write_text('print("hello")\n')
    (tmp_path / "clean.sh").write_text(_shell_file("hello"))
    (tmp_path / "clean.md").write_text(
        "# Clean fixture\n\nA short paragraph.\n\n- one item\n- two items\n"
    )
    (tmp_path / "clean.ts").write_text('export const greeting: string = "hello";\n')
    rc, _, err = run_split(
        [sys.executable, str(RUNNER), "--dir", str(tmp_path), "--json"]
    )
    assert rc == EXIT_CLEAN, (
        f"runner exit={rc} on clean dir (clean files tripped a linter?)\n{err}"
    )


# --------------------------------------------- T3 --changed honors git --
def _git(root, *args):
    return run(["git", "-C", str(root), *args])


def test_t3_changed_honors_git(tmp_path):
    require("git")
    _git(tmp_path, "init", "-q")
    _git(tmp_path, "config", "user.email", "qa@quality-smoke.local")
    _git(tmp_path, "config", "user.name", "quality-smoke")
    (tmp_path / "kept.sh").write_text(_shell_file("hello"))
    (tmp_path / "mod.sh").write_text(_shell_file("world"))
    _git(tmp_path, "add", "kept.sh", "mod.sh")
    _git(tmp_path, "commit", "-qm", "init")
    (tmp_path / "mod.sh").write_text(_shell_file("world-modified"))
    (tmp_path / "fresh.py").write_text('print("hello")\n')

    rc, out, err = run_split(
        [sys.executable, str(RUNNER), "--changed", "--json"], cwd=tmp_path
    )
    assert rc != EXIT_MISUSE, "runner exit=2 (misuse / not a git repo)"
    assert out.strip(), f"no valid JSON from runner (exit={rc})"
    payload = json.loads(out)
    changed = sum(
        t["files"]
        for t in payload["tools"]
        if t["tool"] not in ("secrets", "dup", "deadcode")
    )
    assert changed == EXPECTED_CHANGED_FILES, f"expected 2 changed files, got {changed}"
    assert "kept.sh" not in err, "committed-unchanged kept.sh appears in findings log"


# -------------------------------------------- T4 eslint config sonarjs --
def _run_jsts_over_bad_ts(tmp_path):
    """Run the runner's jsts group over a copy of bad.ts; return its log."""
    require("eslint")
    shutil.copy(FIXTURES / "bad.ts", tmp_path / "bad.ts")
    _, out = run(
        [sys.executable, str(RUNNER), "--dir", str(tmp_path), "--tool", "jsts"],
        cwd=tmp_path,
    )
    return out


def test_t4_eslint_config_loads(tmp_path):
    out = _run_jsts_over_bad_ts(tmp_path)
    assert "[SKIP] jsts" not in out, "jsts skipped (config/plugin unavailable)"
    assert "[FAIL] jsts" in out, "no jsts findings under the config"


def test_t4_eslint_reports_sonarjs_rule_id(tmp_path):
    out = _run_jsts_over_bad_ts(tmp_path)
    assert "sonarjs" in out, "no sonarjs rule id in output"


# ----------------------------------------------- T5 psscriptanalyzer --
def test_t5_output_names_bad_ps1(bad_ps1_output):
    assert "bad.ps1" in bad_ps1_output, "bad.ps1 not named in output"


def test_t5_reports_expected_diagnostics(bad_ps1_output):
    assert re.search(r"Invoke-Expression|PlainTextPassword", bad_ps1_output), (
        "expected diagnostics missing"
    )


# ---------------------------------------------------- T6 trivy offline --
@pytest.fixture(scope="module")
def trivy_config_run():
    require("trivy")
    return run(
        ["trivy", "config", "--skip-policy-update", "--exit-code", "1", str(FIXTURES)]
    )


def test_t6_flags_misconfig_offline(trivy_config_run):
    rc, out = trivy_config_run
    assert rc != EXIT_CLEAN and TRIVY_FINDING.search(out), f"rc={rc} no misconfig evidence"


def test_t6_no_db_fetch_error(trivy_config_run):
    _, out = trivy_config_run
    assert "FATAL" not in out, "FATAL in output (DB/policy fetch failed?)"


# ------------------------------------------------- T7 dotnet analyzers --
def test_t7_qcdotnet_zero_skips_cs(tmp_path):
    scan = _fixture_copy(tmp_path / "fixtures")
    _, _, err = run_split(
        [sys.executable, str(RUNNER), "--dir", str(scan), "--json"],
        env={**os.environ, "QC_DOTNET": "0"},
    )
    assert "[SKIP] cs (QC_DOTNET=0)" in err, "cs group not skipped under QC_DOTNET=0"


def test_t7_analyzer_warnings_and_artifacts_isolation(tmp_path):
    if not have("dotnet"):
        pytest.skip("dotnet not installed")
    if not CS_OVERLAY.is_file():
        pytest.skip("analyzer overlay props not found")
    artifacts = tmp_path / "artifacts"
    rc, out = run(
        [
            "dotnet",
            "build",
            str(FIXTURES / "cs" / "Hello.csproj"),
            "-v:q",
            "--nologo",
            "--artifacts-path",
            str(artifacts),
            f"-p:CustomAfterMicrosoftCommonProps={CS_OVERLAY}",
            "-p:EnableNETAnalyzers=true",
            "-p:AnalysisLevel=latest",
        ]
    )
    warns = count_matches(DOTNET_FINDING, out)
    assert warns >= MIN_FINDINGS, f"rc={rc}, 0 analyzer warnings"
    stray = _first_stray_build_dir(FIXTURES)
    assert stray is None, f"stray build dir: {stray}"
