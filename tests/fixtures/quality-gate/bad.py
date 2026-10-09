# VIOLATIONS PLANTED FOR QUALITY-SMOKE (do not fix):
# - F401: unused import (os)
# - B006: mutable default argument (items=[])
# - B001: bare `except:` clause
import os


def collect(items=[]):
    items.append("example")
    return items


def risky():
    try:
        return 1 / 0
    except:
        return None
