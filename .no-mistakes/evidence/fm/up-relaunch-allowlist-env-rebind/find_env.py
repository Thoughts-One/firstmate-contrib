#!/usr/bin/env python3
"""Print selected env of live claude processes whose environ contains argv[1]."""
import os, sys
needle = sys.argv[1].encode(); names = [n.encode() for n in sys.argv[2:]]
for pid in os.listdir("/proc"):
    if not pid.isdigit(): continue
    try:
        env = open(f"/proc/{pid}/environ","rb").read().split(b"\0")
        cmd = open(f"/proc/{pid}/cmdline","rb").read().replace(b"\0",b" ")
    except OSError: continue
    if b"claude" not in cmd.split(b" ")[0] and b"claude" not in cmd[:80]: continue
    if b"fm-spawn" in cmd or b"fm-control" in cmd or b"bash" in cmd[:20]: continue
    if not any(needle in e for e in env): continue
    print(f"pid={pid} cmd={cmd[:60].decode(errors='replace')!r}")
    for e in env:
        if any(e.startswith(n+b"=") for n in names): print("  ", e.decode(errors="replace"))
