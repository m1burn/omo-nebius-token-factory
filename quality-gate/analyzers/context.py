"""Run context shared by every analyzer invocation."""

from dataclasses import dataclass


@dataclass(frozen=True)
class RunContext:
    """Per-run facts an analyzer may need beyond its file list."""

    scan_root: str         # absolute path being scanned
    mode: str             # changed | all | dir
    repo_root: str        # repository shipping these scripts (fallback configs)
    strict: bool          # QC_STRICT=1: stricter tool flags
    dotnet_enabled: bool  # QC_DOTNET=0 disables the cs group
    dotnet_artifacts: str # shared --artifacts-path (keeps bin/obj out of trees)
