#!/usr/bin/env bash
# Live e2e: real bin/fm-spawn.sh + bin/fm-teardown.sh on an isolated fm-lab-* Herdr
# session. A stale /tmp/fm-<id> truly owned by ANOTHER uid (subordinate uid via
# podman unshare) stands in the way. Usage: <script> <checkout-root> <label>
set -u
ROOT=$(cd "$1" && pwd); LABEL=$2
WT_ROOT=/home/kai/.no-mistakes/worktrees/7605832e1988/01M37E1WM59T8HSCSHJH7MT2AH
. "$WT_ROOT/tests/herdr-test-safety.sh"
herdr_forget_inherited_pane
say() { printf '[%s] %s\n' "$LABEL" "$*"; }
TMP_ROOT=$(mktemp -d "/tmp/fm-live-uidtmp.XXXXXX")
HELPER="$WT_ROOT/bin/fm-herdr-lab.sh"
SESSION=$("$HELPER" name uidtmp) || exit 1
export HERDR_SESSION=$SESSION
UID_=$(id -u); SFX=$$
ID1=uidtmpA$SFX; ID2=uidtmpB$SFX
LEGACY1=/tmp/fm-$ID1; NEW1=/tmp/fm-$UID_-$ID1; NEW2=/tmp/fm-$UID_-$ID2
WORKTREES=()
cleanup() {
  for wt in ${WORKTREES[@]+"${WORKTREES[@]}"}; do treehouse return --force "$wt" >/dev/null 2>&1; done
  "$HELPER" teardown "$SESSION"; say "lab teardown rc=$?"
  podman unshare rm -rf "$LEGACY1" 2>/dev/null; rm -rf "$NEW1" "$NEW2" "$TMP_ROOT"
}
trap cleanup EXIT
"$HELPER" provision "$SESSION" || { say "provision failed"; exit 1; }
say "lab session: $SESSION"
lab() { "$HELPER" run "$SESSION" "$@"; }
HOME_=$TMP_ROOT/home; mkdir -p "$HOME_/state" "$HOME_/config"
printf 'off\n' > "$HOME_/config/herdr-presentation-spaces"
PROJ=$TMP_ROOT/proj; mkdir -p "$PROJ"; git -C "$PROJ" init -q; echo x > "$PROJ/README.md"
git -C "$PROJ" add README.md; git -C "$PROJ" -c user.name=t -c user.email=t@e.invalid commit -qm i
git clone -q --bare "$PROJ" "$PROJ.origin.git"; git -C "$PROJ" remote add origin "file://$PROJ.origin.git"
for id in $ID1 $ID2; do mkdir -p "$HOME_/data/$id"; printf '# Task\n## Captain'"'"'s intent\nx\n\n## Firstmate spec\ny\n' > "$HOME_/data/$id/brief.md"; done
spawn() { env -u HERDR_ENV -u HERDR_PANE_ID -u HERDR_SOCKET_PATH HERDR_SESSION="$SESSION" FM_SPAWN_NO_GUARD=1 \
  FM_HOME="$HOME_" FM_ROOT_OVERRIDE="$ROOT" "$ROOT/bin/fm-spawn.sh" "$1" "$PROJ" \
  "sh -c 'echo GOTMPDIR=\$GOTMPDIR; sleep 600'" --backend herdr --mode no-mistakes --yolo off; }

echo "=== Scenario 1: stale /tmp/fm-<id> owned by another local account ==="
mkdir "$LEGACY1" && podman unshare chown 1:1 "$LEGACY1"
say "planted: $(stat -c 'uid=%u mode=%a %n' "$LEGACY1")  (this account uid=$UID_)"
spawn "$ID1" >"$TMP_ROOT/s1.out" 2>"$TMP_ROOT/s1.err"; rc=$?
say "fm-spawn rc=$rc"; sed 's/^/  stderr: /' "$TMP_ROOT/s1.err" | tail -5
META=$HOME_/state/$ID1.meta
if [ "$rc" -eq 0 ]; then
  wt=$(grep '^worktree=' "$META" | cut -d= -f2-); [ -n "$wt" ] && WORKTREES+=("$wt")
  say "meta: $(grep '^tasktmp=' "$META")"
  say "root: $(stat -c 'uid=%u mode=%a %n' "$NEW1")  gotmp: $(stat -c 'mode=%a %n' "$NEW1/gotmp")"
  say "legacy after spawn: $(stat -c 'uid=%u mode=%a %n' "$LEGACY1")"
  pane=$(grep '^herdr_pane_id=' "$META" | cut -d= -f2-); sleep 2
  say "pane output: $(lab pane read "$pane" 2>/dev/null | jq -r '.result.text // .result.content // empty' 2>/dev/null | grep -m1 GOTMPDIR || lab pane read "$pane" 2>&1 | grep -o 'GOTMPDIR=[^ \"\\]*' | head -1)"
  [ "$LABEL" = target ] || exit 0
  echo "=== Scenario 3: teardown removes the uid-namespaced root, leaves foreign dir ==="
  FM_ROOT_OVERRIDE="$ROOT" FM_STATE_OVERRIDE="$HOME_/state" FM_DATA_OVERRIDE="$HOME_/data" FM_CONFIG_OVERRIDE="$HOME_/config" \
    "$ROOT/bin/fm-teardown.sh" "$ID1" >"$TMP_ROOT/td.out" 2>&1; say "fm-teardown rc=$?"
  WORKTREES=()
  [ -e "$NEW1" ] && say "FAIL: $NEW1 still exists" || say "$NEW1 removed"
  say "foreign legacy dir still: $(stat -c 'uid=%u %n' "$LEGACY1")"
else
  exit 0
fi

echo "=== Scenario 2 (adversarial): unsafe pre-planted /tmp/fm-<uid>-<id> still refused ==="
mkdir "$NEW2"; chmod 777 "$NEW2"
say "planted: $(stat -c 'uid=%u mode=%a %n' "$NEW2")"
panes_before=$(lab pane list 2>/dev/null | jq '[.result.panes[]?] | length')
spawn "$ID2" >"$TMP_ROOT/s2.out" 2>"$TMP_ROOT/s2.err"; rc=$?
say "fm-spawn rc=$rc"; sed 's/^/  stderr: /' "$TMP_ROOT/s2.err" | tail -3
say "meta exists: $([ -f "$HOME_/state/$ID2.meta" ] && echo yes || echo no); panes before=$panes_before after=$(lab pane list 2>/dev/null | jq '[.result.panes[]?] | length')"
say "dir after: $(stat -c 'mode=%a %n' "$NEW2")"
rm -rf "$NEW2"; ln -s "$TMP_ROOT" "$NEW2"
spawn "$ID2" >"$TMP_ROOT/s3.out" 2>"$TMP_ROOT/s3.err"; rc=$?
say "symlink variant: fm-spawn rc=$rc"; sed 's/^/  stderr: /' "$TMP_ROOT/s3.err" | tail -2
rm -f "$NEW2"
