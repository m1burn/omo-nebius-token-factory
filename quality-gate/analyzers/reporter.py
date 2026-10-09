"""Result accumulation: human log rows plus the JSON summary line."""

import json
import sys

from analyzers.result import Status


class Reporter:
    """Accumulates per-group results; prints the human log and JSON summary."""

    def __init__(self, use_json):
        self.use_json = use_json
        self.counts = {"PASS": 0, "FAIL": 0, "SKIP": 0}
        self.rows = []

    def log(self, line):
        stream = sys.stderr if self.use_json else sys.stdout
        print(line, file=stream)

    def record(self, group, result):
        if result.status is Status.PASS:
            self.log(f"[PASS] {group} ({result.files} files, {result.findings} findings)")
        elif result.status is Status.FAIL:
            self.log(f"[FAIL] {group} ({result.findings} findings)")
        else:
            self.log(f"[SKIP] {group} ({result.reason})")
        for line in result.detail:
            if line:
                self.log(f"  {line}")
        self.counts[result.status.value] += 1
        self.rows.append(
            {
                "tool": group,
                "status": result.status.value,
                "files": result.files,
                "findings": result.findings,
            }
        )

    def summary_line(self):
        return (
            f"SUMMARY: F={self.counts['FAIL']}"
            f" P={self.counts['PASS']} S={self.counts['SKIP']}"
        )

    def json_line(self, mode, scan_root):
        payload = {
            "mode": mode,
            "root": scan_root,
            "tools": self.rows,
            "summary": {
                "fail": self.counts["FAIL"],
                "pass": self.counts["PASS"],
                "skip": self.counts["SKIP"],
            },
        }
        return json.dumps(payload, separators=(",", ":"))
