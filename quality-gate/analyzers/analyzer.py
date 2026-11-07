"""Analyzer interface: one report row per tool group.

Every analyzer is a class in its own file under analyzers/ and implements
run(); the registry in analyzers/__init__.py fixes both the analyzer set
and the report row order. Analyzers receive the full candidate list
and select their own files (default: basename extension match).
"""

import os
from abc import ABC, abstractmethod
from typing import ClassVar

from analyzers.result import AnalyzerResult


class Analyzer(ABC):
    """Base contract for a tool group."""

    name: ClassVar[str]
    # Basename extensions this group lints (lowercase, no dot). Empty
    # for analyzers that select by other rules (docker, secrets, dup...).
    extensions: ClassVar[frozenset] = frozenset()

    def match(self, rel_path):
        """Default selection: basename extension in self.extensions."""
        base = rel_path.rsplit("/", 1)[-1]
        if "." not in base:
            return False
        return base.rsplit(".", 1)[-1].lower() in self.extensions

    def select(self, files):
        return [f for f in files if self.match(f)]

    def abs_paths(self, files, ctx):
        return [os.path.join(ctx.scan_root, f) for f in files]

    @abstractmethod
    def run(self, files, ctx) -> AnalyzerResult:
        """Run the group over the candidates; return an AnalyzerResult."""
