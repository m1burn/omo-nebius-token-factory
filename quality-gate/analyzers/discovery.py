"""Candidate file discovery for the three run modes."""

import os
import subprocess


def is_excluded(rel_path, excludes):
    return any(part in excludes for part in rel_path.split("/"))


def git_lines(args):
    # check=False is deliberate: `git diff HEAD` legitimately fails in a fresh
    # repo with no commits yet, and the run must proceed on untracked files.
    proc = subprocess.run(
        args, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
        check=False, text=True,
    )
    return proc.stdout.splitlines()


def raise_walk_error(error):
    """os.walk onerror: fail the run instead of silently skipping unreadable dirs."""
    raise error


def walk_files(scan_root):
    found = []
    for dirpath, _dirnames, filenames in os.walk(scan_root, onerror=raise_walk_error):
        for name in filenames:
            full = os.path.join(dirpath, name)
            if os.path.isfile(full):
                found.append(os.path.relpath(full, scan_root))
    return found


def discover_files(mode, scan_root, excludes):
    """Return the sorted candidate list (paths relative to scan_root)."""
    if mode == "changed":
        names = git_lines(["git", "diff", "--name-only", "HEAD", "--", "."])
        names += git_lines(["git", "ls-files", "--others", "--exclude-standard"])
    else:
        names = walk_files(scan_root)
    files = sorted(name for name in set(names) if name)
    if mode != "dir":
        files = [name for name in files if not is_excluded(name, excludes)]
    if mode == "changed":
        # --changed lists deleted paths too; linters must only see files on disk.
        files = [name for name in files if os.path.isfile(os.path.join(scan_root, name))]
    return files
