#!/usr/bin/env bash
# After killing the real --serve child, compare the OLD selector (wait_child + first pgrep -P child)
# with the NEW wait_serve selector for identifying the respawned serving child.
set -u
W=$1; N=${2:-6}
T=$(mktemp -d /tmp/fm-probe.XXXXXX); T=$(cd $T && pwd -P)
for i in $(seq 1 $N); do
  r=$T/r$i; mkdir -p $r/bin $T/a$i
  cp $W/bin/fm-remote-job-lib.sh $W/bin/fm-remote-job-worker.sh $r/bin/; chmod +x $r/bin/*.sh
  echo f > $r/AGENTS.md; git -C $r init -qb main; git -C $r -c user.email=t@e -c user.name=t add -A; git -C $r -c user.email=t@e -c user.name=t commit -qm x
  ( export FM_REMOTE_JOB_STATE_ROOT=$T/s$i FM_REMOTE_JOB_PLATFORM_OVERRIDE=Linux
    . $W/bin/fm-remote-job-lib.sh; fm_remote_job_start_linux_worker $r $T/a$i >/dev/null 2>&1 )
  wk=""; for _ in $(seq 100); do wk=$(pgrep -f "^/bin/bash $r/bin/fm-remote-job-worker.sh\$"|head -n1); [ -n "$wk" ] && break; sleep 0.02; done
  sv=""; for _ in $(seq 100); do sv=$(pgrep -f "^/bin/bash $r/bin/fm-remote-job-worker.sh --serve\$"|head -n1); [ -n "$sv" ] && break; sleep 0.1; done
  kill -KILL $sv; while kill -0 $sv 2>/dev/null; do sleep 0.05; done
  for _ in $(seq 500); do [ -n "$(pgrep -P $wk)" ] && break; sleep 0.01; done
  old=$(pgrep -P $wk | head -n1); oldcmd=$(ps -o args= -p "$old" 2>/dev/null)
  new=""; for _ in $(seq 150); do new=$(pgrep -f "^/bin/bash $r/bin/fm-remote-job-worker.sh --serve\$"|head -n1); [ -n "$new" ] && break; sleep 0.1; done
  newcmd=$(ps -o args= -p "$new" 2>/dev/null)
  kill -0 "$old" 2>/dev/null && oa=alive || oa=GONE
  printf 'respawn %d | killed serve=%s\n  OLD first-child pid=%s cmd=[%s] alive-later=%s\n  NEW wait_serve  pid=%s cmd=[%s]\n' $i $sv "$old" "${oldcmd:-<exited>}" $oa "$new" "$newcmd"
  kill -KILL -- -$wk 2>/dev/null; kill -KILL $wk 2>/dev/null
done
rm -rf $T
