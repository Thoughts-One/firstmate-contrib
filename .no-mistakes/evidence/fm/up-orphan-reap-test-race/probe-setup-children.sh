#!/usr/bin/env bash
# Tight-polls every direct child of a freshly started real worker until --serve appears,
# listing each distinct child observed (setup children before --serve = the race window).
set -u
W=$1; N=${2:-5}
T=$(mktemp -d /tmp/fm-probe.XXXXXX); T=$(cd $T && pwd -P)
for i in $(seq 1 $N); do
  r=$T/r$i; mkdir -p $r/bin $T/a$i
  cp $W/bin/fm-remote-job-lib.sh $W/bin/fm-remote-job-worker.sh $r/bin/; chmod +x $r/bin/*.sh
  echo f > $r/AGENTS.md; git -C $r init -qb main; git -C $r -c user.email=t@e -c user.name=t add -A; git -C $r -c user.email=t@e -c user.name=t commit -qm x
  ( export FM_REMOTE_JOB_STATE_ROOT=$T/s$i FM_REMOTE_JOB_PLATFORM_OVERRIDE=Linux
    . $W/bin/fm-remote-job-lib.sh; fm_remote_job_start_linux_worker $r $T/a$i >/dev/null 2>&1 ) &
  wk=""; while [ -z "$wk" ]; do wk=$(pgrep -f "^/bin/bash $r/bin/fm-remote-job-worker.sh\$"|head -n1); done
  seen=""; end=$((SECONDS+10))
  while [ $SECONDS -lt $end ]; do
    for c in $(ps -o pid= --ppid $wk); do
      case " $seen " in *" $c "*) continue;; esac; seen="$seen $c"
      a=$(ps -o args= -p $c 2>/dev/null); echo "start $i child pid=$c cmd=[${a:-<exited>}]"
      case "$a" in *--serve) end=0;; esac
    done
  done
  wait; kill -KILL -- -$wk 2>/dev/null; kill -KILL $wk 2>/dev/null
done
rm -rf $T
