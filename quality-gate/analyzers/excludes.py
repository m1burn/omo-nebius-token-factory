"""Vendor excludes: the one list shared by discovery and the dup scan."""

import os
from functools import lru_cache

_EXCLUDES_FILE = os.path.join(
    os.path.dirname(os.path.abspath(__file__)), "vendor-excludes.txt"
)


@lru_cache(maxsize=1)
def vendor_excludes():
    """Directory names excluded from discovery (any path component).

    A missing file fails loudly: silently scanning everything would
    turn vendored noise into gate failures.
    """
    with open(_EXCLUDES_FILE, encoding="utf-8") as handle:
        return frozenset(line.strip() for line in handle if line.strip())
