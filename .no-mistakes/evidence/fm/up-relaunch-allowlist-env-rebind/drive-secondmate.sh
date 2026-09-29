#!/usr/bin/env bash
# Live Herdr-lab driver (isolated fm-lab-* session only). Scenarios:
#  S1 local secondmate spawn  S2 TRACEPARENT interplay  S3 Herdr restart + relaunch
#  S4 ordinary scout worker   S5 argv scan (with positive control)
set -u
. /home/kai/.no-mistakes/evidence/01M3NV6RPFZHAGKKAQPHXE80HQ/lab-common.sh
export FM_GATE_REFUSE_BYPASS=1
unset HERDR_ENV HERDR_PANE_ID HERDR_TAB_ID HERDR_WORKSPACE_ID HERDR_SOCKET_PATH HERDR_SESSION NO_MISTAKES_GATE
setup_lab sm
DUMP=$TMP_ROOT/dump; : > "$DUMP"
sed -i "s#\${FM_LAB_DUMP:-/tmp/fm-lab-claude-dump}#$DUMP#; s#echo \"--- launch \$(date +%s)\"#echo \"--- launch id=\${FM_TASK_ID:-none} \$(date +%s)\"#" "$CLAUDEBIN/claude"
cleanup() { kill "${SAMPLER:-0}" 2>/dev/null; "$LAB_HELPER" teardown "$SESSION"; chmod -R u+w "$TMP_ROOT" 2>/dev/null; rm -rf "$TMP_ROOT"; rm -rf /tmp/fm-lab{sm,sm2,sm3,w1}* 2>/dev/null; }
trap cleanup EXIT
say() { printf '\n=== %s\n' "$*"; }
STALE_TP=00-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa-bbbbbbbbbbbbbbbb-01
LAUNCHER_TP=00-cccccccccccccccccccccccccccccccc-dddddddddddddddd-01
start_server() { # stale pane values in the lab server env => every pane shell inherits them
  FM_LAB_ALLOWED=stale-pane FM_LAB_EMPTY=stale-pane FM_LAB_UNSET=stale-pane FM_LAB_AMBIENT=stale-pane \
  MODEL=stale-pane-model EFFORT=stale-pane-effort MODE=stale-pane-mode TRACEPARENT=$STALE_TP \
  PATH="$CLAUDEBIN:$ORIGINAL_PATH" "$@"
}
start_server "$LAB_HELPER" provision "$SESSION" || exit 1

HOME1=$TMP_ROOT/fmhome; ID=labsm1
mkdir -p "$HOME1"/{state,data,config,projects}
mk_sm() { # <id>
  local sm=$TMP_ROOT/smhome-$1
  git clone -q --no-hardlinks "$ROOT" "$sm" 2>/dev/null; git -C "$sm" checkout -q --detach HEAD 2>/dev/null
  mkdir -p "$sm"/{state,data,config,projects}
  printf '%s\n' "$1" > "$sm/.fm-secondmate-home"; printf '# lab charter\n' > "$sm/data/charter.md"
  echo "$sm"
}
printf '%s\n' FM_LAB_ALLOWED FM_LAB_EMPTY FM_LAB_UNSET MODEL EFFORT MODE > "$HOME1/config/launch-env-allowlist"
RAW="$CLAUDEBIN/claude --lab"
spawn_sm() { # <id> <sm-home> [env assignments...]
  local id=$1 sm=$2; shift 2
  env PATH="$FAKEBIN:$CLAUDEBIN:$ORIGINAL_PATH" FM_HOME="$HOME1" HERDR_SESSION="$SESSION" "$@" \
    "$ROOT/bin/fm-spawn.sh" "$id" "$sm" --secondmate --harness "$RAW" --backend herdr 2>&1
}
wait_launches() { local n=$1 _; for _ in $(seq 1 80); do [ "$(grep -c '^--- launch' "$DUMP")" -ge "$n" ] && return 0; sleep 0.5; done; return 1; }
last_launch() { awk '/^--- launch/{blk=""} {blk=blk $0 "\n"} END{printf "%s", blk}' "$DUMP"; }
verdict() { if [ "$2" = "$3" ]; then echo "PASS  $1"; else echo "FAIL  $1  (expected: $3 / got: $2)"; fi; }

SECRET='secretvalue-9f3a'
# ---- S5 argv sampler + positive control ----
SECRET_NEEDLE=$SECRET python3 "$EV/argv_sampler.py" "$TMP_ROOT/argv-hits" 900 & SAMPLER=$!
say "S5 positive control: sampler must see a secret placed in a real argv"
sleep 0.5; sh -c 'sleep 1; true' "positive-control-$SECRET" & sleep 1.5
grep -c "positive-control" "$TMP_ROOT/argv-hits" | sed 's/^/positive-control hits: /'
: > "$TMP_ROOT/argv-hits"   # reset; from here every hit is a leak

SM1=$(mk_sm $ID)
say "S1 local secondmate SPAWN: launcher values, not stale pane values"
LOUT=$(spawn_sm $ID "$SM1" FM_LAB_ALLOWED="$SECRET \$(touch $TMP_ROOT/INJECTED) \"q\" 'sq'" FM_LAB_EMPTY= FM_LAB_AMBIENT=launcher-ambient \
  MODEL=launcher-model EFFORT=launcher-effort MODE=launcher-mode); echo "$LOUT" | tail -2
wait_launches 1 || echo "FAIL no launch observed"
last_launch
GOT=$(last_launch)
EXP=$'--- launch id=labsm1'
case $GOT in *"EFFORT=launcher-effort"*"FM_LAB_ALLOWED=$SECRET"*"FM_LAB_EMPTY="$'\n'"MODE=launcher-mode"$'\n'"MODEL=launcher-model"*) echo "PASS  S1 allowlisted launcher values (incl. MODEL/EFFORT/MODE, empty, metachar) delivered";; *) echo "FAIL  S1 values";; esac
case $GOT in *stale*|*FM_LAB_AMBIENT*|*FM_LAB_UNSET*) echo "FAIL  S1 stale/non-allowlisted leaked";; *) echo "PASS  S1 no stale pane value, no unlisted ambient, unset stays unset";; esac
[ -e "$TMP_ROOT/INJECTED" ] && echo "FAIL  S1 injection executed" || echo "PASS  S1 value never executed as shell"
ls "$HOME1/state" | grep -q "launch-env" && echo "FAIL  S1 snapshot file left behind" || echo "PASS  S1 one-launch snapshot removed"
PANE1=$(echo "$LOUT" | sed -n 's/.*window=[^:]*:\(w[0-9]*:p[0-9]*\).*/\1/p')
"$LAB_HELPER" run "$SESSION" pane read "$PANE1" --source recent --lines 200 2>&1 | grep -aF "$SECRET" >/dev/null && echo "FAIL  S1 secret visible in pane text" || echo "PASS  S1 secret never in pane/launch text"

say "S2 TRACEPARENT interplay (local secondmate)"
printf '%s\n' FM_LAB_ALLOWED TRACEPARENT > "$HOME1/config/launch-env-allowlist"
SM2=$(mk_sm labsm2); SM3=$(mk_sm labsm3)
: > "$DUMP"
LOUT=$(spawn_sm labsm2 "$SM2" FM_LAB_ALLOWED=fresh TRACEPARENT=$LAUNCHER_TP); echo "$LOUT" | tail -1
wait_launches 1; GOT=$(last_launch)
verdict "S2a carrier empty (tracing off): allowlisted TRACEPARENT forwards the destination pane's value (old behavior), not the launcher's" "$(echo "$GOT" | grep '^TRACEPARENT=')" "TRACEPARENT=$STALE_TP"
# tracing ON: dedicated carrier
mkdir -p "$HOME1/state"; touch "$HOME1/config/trace-context"; echo $$ > "$HOME1/state/.lock"
( . "$ROOT/bin/fm-trace-context-lib.sh"; fm_trace_context_session_start "$HOME1/config" "$HOME1/state/.trace-context-effective" ) >/dev/null 2>&1
: > "$DUMP"
LOUT=$(spawn_sm labsm3 "$SM3" FM_LAB_ALLOWED=fresh TRACEPARENT=$LAUNCHER_TP); echo "$LOUT" | tail -1
wait_launches 1; GOT=$(last_launch)
REC=$(grep '^traceparent=' "$HOME1/state/labsm3.meta" | cut -d= -f2)
echo "recorded carrier: $REC"
[ -n "$REC" ] && verdict "S2b dedicated carrier wins over allowlisted TRACEPARENT (pane and launcher values both ignored)" "$(echo "$GOT" | grep '^TRACEPARENT=')" "TRACEPARENT=$REC" || echo "FAIL S2b no carrier recorded"
rm -f "$HOME1/config/trace-context" "$HOME1/state/.trace-context-effective"*

say "S3 Herdr-backed secondmate RESTART then relaunch (real claude; env read from /proc/<pid>/environ)"
printf '%s\n' FM_LAB_ALLOWED FM_LAB_EMPTY FM_LAB_UNSET MODEL EFFORT MODE > "$HOME1/config/launch-env-allowlist"
"$LAB_HELPER" stop "$SESSION" >/dev/null 2>&1 && echo "lab session stopped" || echo "FAIL could not stop lab"
sleep 1
start_server env PATH="$CLAUDEBIN:$ORIGINAL_PATH" bash -c ". '$ROOT/bin/fm-backend.sh'; fm_backend_source herdr; fm_backend_herdr_server_ensure '$SESSION'" && echo "server restarted"
"$LAB_HELPER" run "$SESSION" pane get "$PANE1" >/dev/null 2>&1 && echo "pane $PANE1 survived restart (husk shell)" || echo "pane gone after restart"
ROUT=$(env PATH="$FAKEBIN:$CLAUDEBIN:$ORIGINAL_PATH" FM_HOME="$HOME1" HERDR_SESSION="$SESSION" FM_SPAWN_NO_GUARD=1 FM_CONTROL_POLL=0.2 FM_CONTROL_EXIT_WAIT=3 \
  FM_LAB_ALLOWED="relaunch-fresh $SECRET" FM_LAB_EMPTY= FM_LAB_AMBIENT=launcher-ambient MODEL=relaunch-model EFFORT=relaunch-effort MODE=relaunch-mode \
  "$ROOT/bin/fm-control.sh" $ID relaunch 2>&1); echo "rc=$?"; echo "$ROUT" | tail -4
for _ in $(seq 1 40); do ENVOUT=$(python3 "$EV/find_env.py" "FM_LAB_ALLOWED=" FM_LAB_ALLOWED FM_LAB_EMPTY FM_LAB_UNSET FM_LAB_AMBIENT MODEL EFFORT MODE); [ -n "$ENVOUT" ] && break; sleep 1; done
echo "$ENVOUT"
ok=1; for want in "FM_LAB_ALLOWED=relaunch-fresh $SECRET" "MODEL=relaunch-model" "EFFORT=relaunch-effort" "MODE=relaunch-mode" "FM_LAB_EMPTY="; do echo "$ENVOUT" | grep -qxF "   $want" || { ok=0; echo "missing: $want"; }; done
[ $ok = 1 ] && echo "PASS  S3 relaunched real claude holds the fresh launcher allowlist" || echo "FAIL  S3 values"
case $ENVOUT in *stale*|*FM_LAB_AMBIENT*|*FM_LAB_UNSET*) echo "FAIL  S3 stale/non-allowlisted leaked";; *) echo "PASS  S3 no stale pane values after Herdr restart, unlisted/unset absent";; esac
ls "$HOME1/state" | grep -q "launch-env" && echo "FAIL  S3 snapshot left" || echo "PASS  S3 snapshot removed"

say "S4 ORDINARY scout worker launch (existing behavior: destination-pane values, launcher not captured)"
PROJ=$HOME1/projects/labproj; mkdir -p "$PROJ"; git -C "$PROJ" init -q -b main; git -C "$PROJ" -c user.name=t -c user.email=t@e commit -q --allow-empty -m init
: > "$DUMP"
env FM_HOME="$HOME1" "$ROOT/bin/fm-brief.sh" labw1 labproj --scout --herdr-lab 2>&1 | tail -2
sed -i "s/{TASK}/lab scout task/; s/{FIRSTMATE_SPEC}/do nothing/" "$HOME1/data/labw1/brief.md" 2>/dev/null
WOUT=$(env PATH="$FAKEBIN:$CLAUDEBIN:$ORIGINAL_PATH" FM_HOME="$HOME1" HERDR_SESSION="$SESSION" \
  FM_LAB_ALLOWED=launcher-only-val MODEL=launcher-model "$ROOT/bin/fm-spawn.sh" labw1 "$PROJ" --scout --harness "$RAW" --backend herdr 2>&1); echo "rc=$?"; echo "$WOUT" | tail -4
wait_launches 1; GOT=$(last_launch); echo "$GOT"
case $GOT in *"FM_LAB_ALLOWED=stale-pane"*"MODEL=stale-pane-model"*) echo "PASS  S4 ordinary worker keeps existing destination-pane expansion";; *) echo "FAIL/INCONCLUSIVE S4";; esac

say "S5 argv scan verdict (hits during S1/S2/S3/S4 spawn+relaunch; must be empty)"
kill $SAMPLER 2>/dev/null; SAMPLER=
[ -s "$TMP_ROOT/argv-hits" ] && { echo "FAIL argv leak:"; head -3 "$TMP_ROOT/argv-hits"; } || echo "PASS  no launcher value in any process argv"
