"""Guarded subprocess execution of the external analysis tools."""

import subprocess


class ToolError(Exception):
    """A tool exited outside its documented codes: an execution error,
    not findings. The orchestrator converts this into a marked FAIL row."""

    def __init__(self, tool, rc, lines, files):
        super().__init__(f"{tool} execution error (rc={rc})")
        self.tool = tool
        self.rc = rc
        self.lines = lines
        self.files = files


# Per-invocation argv budget for file paths. Linux caps a single execve
# argument list at ARG_MAX (~2 MiB) and each argument at MAX_ARG_STRLEN
# (128 KiB); handing a whole tree's file list to one process overruns it
# with Errno 7 (E2BIG). Chunk paths well below the cap instead.
ARGV_PATH_BUDGET = 64 * 1024


def batched(paths, budget=ARGV_PATH_BUDGET):
    """Yield path sublists whose combined byte length stays under budget."""
    batch, size = [], 0
    for path in paths:
        length = len(path) + 1
        if batch and size + length > budget:
            yield batch
            batch, size = [], 0
        batch.append(path)
        size += length
    if batch:
        yield batch


def run_tool(argv, tool, ok_rc=None, files=0, **exec_opts):
    """Run one analysis tool with merged output captured.

    ok_rc is the set of exit codes meaning a normal outcome for this
    tool (findings included); a code outside it raises ToolError.
    ok_rc None means every exit code is a normal outcome (the tool has
    no separate error class, e.g. dotnet build or terraform validate).
    exec_opts pass through to subprocess.run (cwd, env, ...).
    """
    proc = subprocess.run(
        argv, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
        text=True, check=False, **exec_opts,
    )
    lines = proc.stdout.splitlines()
    if ok_rc is not None and proc.returncode not in ok_rc:
        raise ToolError(tool, proc.returncode, lines, files)
    return proc.returncode, lines


def run_tool_batched(argv, paths, tool, ok_rc=None, files=0, **exec_opts):
    """run_tool over many paths, chunked so a huge file list cannot E2BIG.

    argv is the fixed prefix (program plus flags); paths are appended per
    batch. A batch exiting outside ok_rc still raises ToolError; otherwise
    the merged code is the first non-zero normal code, so a findings-bearing
    batch still reads as FAIL. files/exec_opts are as in run_tool.
    """
    merged_rc = 0
    merged_lines = []
    for batch in batched(paths):
        rc, out = run_tool(
            [*argv, *batch], tool, ok_rc, len(batch), **exec_opts,
        )
        merged_lines.extend(out)
        if rc != 0 and merged_rc == 0:
            merged_rc = rc
    return merged_rc, merged_lines
