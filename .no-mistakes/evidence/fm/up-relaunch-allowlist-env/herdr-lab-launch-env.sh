#!/usr/bin/env bash
# Live Herdr lab proof for the local-secondmate launch-env snapshot.
# Runs only inside a named fm-lab-* session through tests/herdr-test-safety.sh
# (which delegates to bin/fm-herdr-lab.sh prepare/teardown).
set -u
ROOT=${ROOT:?}
EVID=${EVID:?}
fail() { printf 'FAIL - %s\n' "$1"; FAILED=1; }
pass() { printf 'PASS - %s\n' "$1"; }
FAILED=0
. "$ROOT/tests/herdr-test-safety.sh"
herdr_forget_inherited_pane
TMP_ROOT=$(mktemp -d "$(cd "${TMPDIR:-/tmp}" && pwd -P)/fm-lenv-lab.XXXXXX")
SESSION=$("$ROOT/bin/fm-herdr-lab.sh" name lenv) || exit 1
export HERDR_SESSION="$SESSION"
echo "lab session: $SESSION"
WT1=; WT2=
cleanup_all() {
  [ -n "$WT1" ] && treehouse return --force "$WT1" >/dev/null 2>&1
  [ -n "$WT2" ] && treehouse return --force "$WT2" >/dev/null 2>&1
  herdr_safe_stop_and_delete "$SESSION"
  rm -rf "$TMP_ROOT"
}
trap cleanup_all EXIT
# The Herdr server (and so every pane shell) starts with these stale "pane" values.
export FM_LAB_ALLOWED=stale-pane-value FM_LAB_UNSET=stale-pane-value FM_LAB_EMPTY=stale-pane-value FM_LAB_AMBIENT=stale-pane-value
fm_herdr_lab_prepare "$SESSION" || { echo "lab prepare failed"; exit 1; }
. "$ROOT/bin/fm-backend.sh"; fm_backend_source herdr
fm_backend_herdr_server_ensure "$SESSION" || { echo "lab server start failed"; exit 1; }
unset FM_LAB_ALLOWED FM_LAB_UNSET FM_LAB_EMPTY FM_LAB_AMBIENT

PRIMARY_HOME="$TMP_ROOT/primary-home"
mkdir -p "$PRIMARY_HOME/state" "$PRIMARY_HOME/data/lenvcm" "$PRIMARY_HOME/config"
printf 'off\n' > "$PRIMARY_HOME/config/herdr-presentation-spaces"
printf '%s\n' FM_LAB_ALLOWED FM_LAB_EMPTY FM_LAB_UNSET TRACEPARENT > "$PRIMARY_HOME/config/launch-env-allowlist"
printf '# Task\n## Captain'"'"'s intent\nlab\n\n## Firstmate spec\nlab\n' > "$PRIMARY_HOME/data/lenvcm/brief.md"
SM_HOME="$TMP_ROOT/secondmate-home"
mkdir -p "$SM_HOME/state" "$SM_HOME/data" "$SM_HOME/config" "$SM_HOME/projects" "$SM_HOME/bin"
printf 'off\n' > "$SM_HOME/config/herdr-presentation-spaces"
printf '# agents\n' > "$SM_HOME/AGENTS.md"; printf 'lenvsm\n' > "$SM_HOME/.fm-secondmate-home"
printf 'charter\n' > "$SM_HOME/data/charter.md"
PROJ="$TMP_ROOT/proj"; mkdir -p "$PROJ"; git -C "$PROJ" init -q; echo x > "$PROJ/R"; git -C "$PROJ" add R
git -C "$PROJ" -c user.name=t -c user.email=t@example.invalid commit -qm i
git clone -q --bare "$PROJ" "$PROJ.origin.git"; git -C "$PROJ" remote add origin "file://$PROJ.origin.git"

PROBE="$TMP_ROOT/probe.sh"
cat > "$PROBE" <<'P'
#!/bin/sh
out=$1
{ printf 'FM_LAB_ALLOWED=%s\n' "${FM_LAB_ALLOWED-<unset>}"
  printf 'FM_LAB_EMPTY=%s\n' "${FM_LAB_EMPTY-<unset>}"
  printf 'FM_LAB_UNSET=%s\n' "${FM_LAB_UNSET-<unset>}"
  printf 'FM_LAB_AMBIENT=%s\n' "${FM_LAB_AMBIENT-<unset>}"
  printf 'TRACEPARENT=%s\n' "${TRACEPARENT-<unset>}"; } > "$out.tmp" && mv "$out.tmp" "$out"
echo probe-done; exec sleep 600
P
chmod +x "$PROBE"
wait_file() { local i=0; while [ ! -f "$1" ] && [ $i -lt 100 ]; do sleep 0.2; i=$((i+1)); done; [ -f "$1" ]; }
field() { grep "^$1=" "$2" | cut -d= -f2-; }
spawn() { # <env assignments...> -- <fm-spawn args...>
  local envs=(); while [ "$1" != -- ]; do envs+=("$1"); shift; done; shift
  env "${envs[@]}" FM_SPAWN_NO_GUARD=1 FM_HOME="$PRIMARY_HOME" FM_ROOT_OVERRIDE="$ROOT" "$ROOT/bin/fm-spawn.sh" "$@"
}

# ---- Scenario A: ordinary worker keeps destination-pane expansion ----
SECRET_A='launcher-ordinary-secret-A1'
spawn FM_LAB_ALLOWED="$SECRET_A" FM_LAB_EMPTY= FM_LAB_AMBIENT=launcher-ambient -- \
  lenvcm "$PROJ" "/bin/sh $PROBE $TMP_ROOT/cm1.env" --mode no-mistakes --yolo off --backend herdr \
  > "$EVID/A-spawn.log" 2>&1 || fail "A: ordinary spawn failed ($(tail -3 "$EVID/A-spawn.log"))"
WT1=$(field worktree "$PRIMARY_HOME/state/lenvcm.meta")
if wait_file "$TMP_ROOT/cm1.env"; then
  cp "$TMP_ROOT/cm1.env" "$EVID/A-worker-env.txt"
  echo "--- A worker env ---"; cat "$TMP_ROOT/cm1.env"
  [ "$(field FM_LAB_ALLOWED "$TMP_ROOT/cm1.env")" = stale-pane-value ] && pass "A: ordinary worker FM_LAB_ALLOWED expands from the destination pane (unchanged behavior)" || fail "A: ordinary worker FM_LAB_ALLOWED not from pane"
  [ "$(field FM_LAB_AMBIENT "$TMP_ROOT/cm1.env")" = '<unset>' ] && pass "A: non-allowlisted ambient name is filtered" || fail "A: ambient leaked"
else fail "A: ordinary worker never ran"; fi
[ ! -e "$PRIMARY_HOME/state/lenvcm.launch-env" ] && pass "A: no launch-env snapshot for an ordinary worker" || fail "A: ordinary worker got a snapshot"
P1=$(field herdr_pane_id "$PRIMARY_HOME/state/lenvcm.meta")
fm_backend_herdr_capture "$SESSION:$P1" 200 > "$EVID/A-pane-capture.txt" 2>&1
grep -q "$SECRET_A" "$EVID/A-pane-capture.txt" && fail "A: launcher value visible in pane" || pass "A: launcher value never appears in the pane text"

# ---- Scenario B: local secondmate spawn captures launcher values ----
SECRET_B='launcher-sm-secret-B1 $(touch '"$TMP_ROOT"'/PWNED) "q"'
spawn FM_LAB_ALLOWED="$SECRET_B" FM_LAB_EMPTY= FM_LAB_AMBIENT=launcher-ambient -- \
  lenvsm "$SM_HOME" "/bin/sh $PROBE $TMP_ROOT/sm1.env" --secondmate --backend herdr \
  > "$EVID/B-spawn.log" 2>&1 || fail "B: secondmate spawn failed ($(tail -3 "$EVID/B-spawn.log"))"
if wait_file "$TMP_ROOT/sm1.env"; then
  cp "$TMP_ROOT/sm1.env" "$EVID/B-secondmate-env.txt"
  echo "--- B secondmate env ---"; cat "$TMP_ROOT/sm1.env"
  [ "$(field FM_LAB_ALLOWED "$TMP_ROOT/sm1.env")" = "$SECRET_B" ] && pass "B: secondmate receives the launcher's allowlisted value verbatim" || fail "B: secondmate FM_LAB_ALLOWED wrong"
  [ "$(field FM_LAB_EMPTY "$TMP_ROOT/sm1.env")" = '' ] && pass "B: empty launcher value stays empty (pane stale value ignored)" || fail "B: empty not preserved"
  [ "$(field FM_LAB_UNSET "$TMP_ROOT/sm1.env")" = '<unset>' ] && pass "B: launcher-unset name stays unset despite stale pane value" || fail "B: unset not preserved"
  [ "$(field FM_LAB_AMBIENT "$TMP_ROOT/sm1.env")" = '<unset>' ] && pass "B: non-allowlisted name filtered" || fail "B: ambient leaked"
else fail "B: secondmate never ran"; fi
[ ! -e "$TMP_ROOT/PWNED" ] && pass "B: value is data, not code (no command substitution executed)" || fail "B: injected command executed"
[ ! -e "$PRIMARY_HOME/state/lenvsm.launch-env" ] && pass "B: one-launch snapshot removed after the secondmate started" || fail "B: snapshot left behind"
P2=$(field herdr_pane_id "$PRIMARY_HOME/state/lenvsm.meta")
fm_backend_herdr_capture "$SESSION:$P2" 200 > "$EVID/B-pane-capture.txt" 2>&1
grep -q 'launcher-sm-secret-B1' "$EVID/B-pane-capture.txt" && fail "B: launcher value visible in pane text" || pass "B: launcher value never appears in the secondmate pane text"

# ---- Scenario C: secondmate restart (endpoint gone -> recovery respawn) captures fresh values ----
fm_backend_herdr_kill "$SESSION:$P2"; sleep 1
spawn FM_LAB_ALLOWED=launcher-restart-value-C2 -- \
  lenvsm "$SM_HOME" "/bin/sh $PROBE $TMP_ROOT/sm2.env" --secondmate --backend herdr \
  > "$EVID/C-respawn.log" 2>&1 || fail "C: secondmate respawn failed ($(tail -3 "$EVID/C-respawn.log"))"
if wait_file "$TMP_ROOT/sm2.env"; then
  cp "$TMP_ROOT/sm2.env" "$EVID/C-secondmate-restart-env.txt"
  echo "--- C restarted secondmate env ---"; cat "$TMP_ROOT/sm2.env"
  [ "$(field FM_LAB_ALLOWED "$TMP_ROOT/sm2.env")" = launcher-restart-value-C2 ] && pass "C: restarted secondmate sees the fresh launcher value" || fail "C: restart not fresh"
  [ "$(field FM_LAB_EMPTY "$TMP_ROOT/sm2.env")" = '<unset>' ] && pass "C: name now unset in launcher is unset in the restarted secondmate (no stale carry-over)" || fail "C: stale empty carried"
else fail "C: restarted secondmate never ran"; fi

# ---- Scenario E: restart with nothing captured deletes a stale leftover snapshot ----
P3=$(field herdr_pane_id "$PRIMARY_HOME/state/lenvsm.meta")
fm_backend_herdr_kill "$SESSION:$P3"; sleep 1
( umask 077; printf 'export FM_LAB_ALLOWED=%s\n' "'old-leftover-credential'" > "$PRIMARY_HOME/state/lenvsm.launch-env" )
spawn -u FM_LAB_ALLOWED -u FM_LAB_EMPTY -u FM_LAB_UNSET -- \
  lenvsm "$SM_HOME" "/bin/sh $PROBE $TMP_ROOT/sm3.env" --secondmate --backend herdr \
  > "$EVID/E-respawn.log" 2>&1 || fail "E: secondmate respawn failed ($(tail -3 "$EVID/E-respawn.log"))"
if wait_file "$TMP_ROOT/sm3.env"; then
  cp "$TMP_ROOT/sm3.env" "$EVID/E-secondmate-env.txt"; echo "--- E secondmate env ---"; cat "$TMP_ROOT/sm3.env"
  [ "$(field FM_LAB_ALLOWED "$TMP_ROOT/sm3.env")" = '<unset>' ] && pass "E: leftover credential was not loaded into the restarted secondmate" || fail "E: leftover credential loaded"
else fail "E: secondmate never ran"; fi
[ ! -e "$PRIMARY_HOME/state/lenvsm.launch-env" ] && pass "E: stale leftover snapshot deleted when nothing was captured" || fail "E: stale snapshot retained"

# ---- Scenario D: dedicated TRACEPARENT carrier vs an allowlisted launcher TRACEPARENT ----
printf '%s\n' "$$" > "$PRIMARY_HOME/state/.lock"
printf '%s on\n' "$$" > "$PRIMARY_HOME/state/.trace-context-effective"
LAUNCHER_TP='00-eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee-ffffffffffffffff-01'
SM2_HOME="$TMP_ROOT/secondmate-home-tp"
mkdir -p "$SM2_HOME/state" "$SM2_HOME/data" "$SM2_HOME/config" "$SM2_HOME/projects" "$SM2_HOME/bin"
printf 'off\n' > "$SM2_HOME/config/herdr-presentation-spaces"
printf '# agents\n' > "$SM2_HOME/AGENTS.md"; printf 'lenvtp\n' > "$SM2_HOME/.fm-secondmate-home"
printf 'charter\n' > "$SM2_HOME/data/charter.md"
spawn TRACEPARENT="$LAUNCHER_TP" FM_LAB_ALLOWED=launcher-tp-value -- \
  lenvtp "$SM2_HOME" "/bin/sh $PROBE $TMP_ROOT/tp.env" --secondmate --backend herdr \
  > "$EVID/D-secondmate-spawn.log" 2>&1 || fail "D: traced secondmate spawn failed ($(tail -3 "$EVID/D-secondmate-spawn.log"))"
META_TP=$(field traceparent "$PRIMARY_HOME/state/lenvtp.meta")
echo "D secondmate meta traceparent=$META_TP launcher TRACEPARENT=$LAUNCHER_TP"
if wait_file "$TMP_ROOT/tp.env"; then
  cp "$TMP_ROOT/tp.env" "$EVID/D-secondmate-env.txt"; echo "--- D secondmate env ---"; cat "$TMP_ROOT/tp.env"
  W_TP=$(field TRACEPARENT "$TMP_ROOT/tp.env")
  [ -n "$META_TP" ] && [ "$W_TP" = "$META_TP" ] && [ "$W_TP" != "$LAUNCHER_TP" ] \
    && pass "D: local secondmate receives the recorded carrier, not the launcher's allowlisted TRACEPARENT" \
    || fail "D: secondmate TRACEPARENT=$W_TP meta=$META_TP"
  [ "$(field FM_LAB_ALLOWED "$TMP_ROOT/tp.env")" = launcher-tp-value ] && pass "D: other allowlisted launcher value still delivered" || fail "D: allowlisted value lost"
else fail "D: traced secondmate never ran"; fi
mkdir -p "$PRIMARY_HOME/data/lenvcm2"; { printf '# Task\n## Captain'"'"'s intent\nlab\n\n## Firstmate spec\nlab\n' ; } > "$PRIMARY_HOME/data/lenvcm2/brief.md"
spawn TRACEPARENT="$LAUNCHER_TP" -- \
  lenvcm2 "$PROJ" "/bin/sh $PROBE $TMP_ROOT/tpcm.env" --mode no-mistakes --yolo off --backend herdr \
  > "$EVID/D-ordinary-spawn.log" 2>&1 || fail "D: traced ordinary spawn failed ($(tail -3 "$EVID/D-ordinary-spawn.log"))"
WT2=$(field worktree "$PRIMARY_HOME/state/lenvcm2.meta")
META_TP2=$(field traceparent "$PRIMARY_HOME/state/lenvcm2.meta")
if wait_file "$TMP_ROOT/tpcm.env"; then
  cp "$TMP_ROOT/tpcm.env" "$EVID/D-ordinary-env.txt"; echo "--- D ordinary env ---"; cat "$TMP_ROOT/tpcm.env"
  W_TP2=$(field TRACEPARENT "$TMP_ROOT/tpcm.env")
  [ -n "$META_TP2" ] && [ "$W_TP2" = "$META_TP2" ] && [ "$W_TP2" != "$LAUNCHER_TP" ] \
    && pass "D: ordinary worker receives its recorded carrier with TRACEPARENT allowlisted" \
    || fail "D: ordinary TRACEPARENT=$W_TP2 meta=$META_TP2"
  [ "$(field FM_LAB_ALLOWED "$TMP_ROOT/tpcm.env")" = stale-pane-value ] && pass "D: ordinary worker still expands other allowlisted names from the pane" || fail "D: ordinary allowlisted value not from pane"
else fail "D: traced ordinary worker never ran"; fi

echo "RESULT failed=$FAILED"
