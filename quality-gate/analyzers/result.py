"""Analyzer result value types: the one shape every analyzer returns."""

from dataclasses import dataclass
from enum import Enum

# Detail blocks are capped so one verbose tool cannot flood the log
# (parity with the bash emit_result/head_lines behavior).
DETAIL_CAP = 30


class Status(Enum):
    """Report row status; the value is what the log and JSON show."""

    PASS = "PASS"
    FAIL = "FAIL"
    SKIP = "SKIP"


@dataclass(frozen=True)
class AnalyzerResult:
    """Result of one tool group over one file set.

    status/files/findings feed the JSON row; reason is the SKIP text;
    detail lines go to the human log only, never to JSON.
    """

    status: Status
    files: int
    findings: int = 0
    reason: str = ""
    detail: tuple = ()

    def __post_init__(self):
        # Parity with bash: detail capped to its first lines; a FAIL row
        # reports at least one finding even if the count regex missed.
        object.__setattr__(self, "detail", tuple(self.detail[:DETAIL_CAP]))
        if self.status is Status.FAIL and self.findings < 1:
            object.__setattr__(self, "findings", 1)

    @classmethod
    def passed(cls, files, findings=0, detail=()):
        return cls(Status.PASS, files, findings, "", detail)

    @classmethod
    def failed(cls, files, findings, detail=()):
        return cls(Status.FAIL, files, findings, "", detail)

    @classmethod
    def skipped(cls, files, reason):
        return cls(Status.SKIP, files, 0, reason, ())

    @classmethod
    def emit(cls, rc, files, findings, detail=()):
        """Port of the bash emit_result: rc 0 -> PASS, otherwise FAIL."""
        status = Status.PASS if rc == 0 else Status.FAIL
        return cls(status, files, findings, "", detail)

    @classmethod
    def execution_error(cls, tool, rc, lines, files):
        """A tool exited outside its documented codes (error, not findings)."""
        marker = f"{tool} execution error (rc={rc})"
        return cls(Status.FAIL, files, 1, "", (marker, *lines))
