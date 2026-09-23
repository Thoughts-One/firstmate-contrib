#!/usr/bin/env bash
# Starts the real worker via fm_remote_job_start_linux_worker (as the test does) N times.
# For each start: capture what the OLD selector (first pgrep -P child right after any child appears)
# returns and whether it is the --serve process / still alive one line later, vs the NEW wait_serve selector.
set -u
W=$1; N=${2:-10}
T=$(mktemp -d /tmp/fm-probe.XXXXXX); T=$(cd $T && pwd -P)
for i in $(seq 1 $N); do
  r=$T/r$i; mkdir -p $r/bin $T/a$i
  cp $W/bin/fm-remote-job-lib.sh $W/bin/fm-remote-job-worker.sh $r/bin/; chmod +x $r/bin/*.sh
  echo f > $r/AGENTS.md; git -C $r init -qb main; git -C $r -c user.email=t@e -c user.name=t add -A; git -C $r -c user.email=t@e -c user.name=t commit -qm x
  ( export FM_REMOTE_JOB_STATE_ROOT=$T/s$i FM_REMOTE_JOB_PLATFORM_OVERRIDE=Linux
    . $W/bin/fm-remote-job-lib.sh; fm_remote_job_start_linux_worker $r $T/a$i >/dev/null 2>&1 )
  wk=""; for _ in $(seq 100); do wk=$(pgrep -f "^/bin/bash $r/bin/fm-remote-job-worker.sh\$"|head -n1); [ -n "$wk" ] && break; sleep 0.02; done
  # OLD selector
  for _ in $(seq 500); do [ -n "$(pgrep -P $wk)" ] && break; sleep 0.01; done
  old=$(pgrep -P $wk | head -n1); oldcmd=$(ps -o args= -p "$old" 2>/dev/null); sleep 0.05
  kill -0 "$old" 2>/dev/null && oa=alive || oa=GONE
  # NEW selector
  new=""; for _ in $(seq 100); do new=$(pgrep -f "^/bin/bash $r/bin/fm-remote-job-worker.sh --serve\$"|head -n1); [ -n "$new" ] && break; sleep 0.1; done
  newcmd=$(ps -o args= -p "$new" 2>/dev/null)
  printf 'start %2d | OLD first-child pid=%s alive-after=%s cmd=[%s]\n         | NEW wait_serve pid=%s cmd=[%s]\n' $i "$old" $oa "${oldcmd:-<exited>}" "$new" "$newcmd"
  kill -KILL -- -$wk 2>/dev/null; kill -KILL $wk 2>/dev/null
done
rm -rf $T
