#!/usr/bin/env python3
"""Poll /proc argv of every process; log any argv containing $SECRET_NEEDLE (passed via env, never argv)."""
import os, sys, time
needle = os.environ["SECRET_NEEDLE"].encode()
me = os.getpid()
out = open(sys.argv[1], "ab", buffering=0)
end = time.time() + float(sys.argv[2])
seen = set()
while time.time() < end:
    for pid in os.listdir("/proc"):
        if not pid.isdigit() or int(pid) == me:
            continue
        try:
            with open(f"/proc/{pid}/cmdline", "rb") as f:
                data = f.read()
        except OSError:
            continue
        if needle in data and (pid, data) not in seen:
            seen.add((pid, data))
            shown = data.replace(b"\0", b" ")[:300]
            out.write(("pid=%s argv=%r\n" % (pid, shown)).encode())
    time.sleep(0.002)
