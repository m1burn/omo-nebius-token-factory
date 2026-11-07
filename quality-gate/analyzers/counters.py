"""Regex counting helpers over captured tool output (grep -c/-o parity)."""

import re


def count_matches(lines, pattern):
    """Number of lines matching the pattern (grep -cE)."""
    rx = re.compile(pattern)
    return sum(1 for line in lines if rx.search(line))


def last_matching_line(lines, pattern):
    """Last line matching the pattern, or None (grep -E | tail -1)."""
    rx = re.compile(pattern)
    for line in reversed(lines):
        if rx.search(line):
            return line
    return None


def first_int(text, pattern):
    """First integer captured by the pattern's single group; 0 if absent."""
    match = re.search(pattern, text)
    return int(match.group(1)) if match else 0


def last_int(lines, pattern):
    """Integer from the last match of the pattern across all lines."""
    rx = re.compile(pattern)
    last = None
    for line in lines:
        for match in rx.finditer(line):
            last = match
    return int(last.group(1)) if last else 0


def sum_ints(lines, pattern):
    """Sum of every captured integer across all lines (grep -oE | awk)."""
    rx = re.compile(pattern)
    return sum(int(m.group(1)) for line in lines for m in rx.finditer(line))
