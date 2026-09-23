#!/usr/bin/env bash
# Live proof of the spawn-time Treehouse pool-slot owner guard, driven through
# the real bin/fm-spawn.sh, a real Treehouse pool (in-project, under a temp
# dir), and an isolated fm-lab-* Herdr session via bin/fm-herdr-lab.sh.
set -u
ROOT=${ROOT:?set ROOT to the checkout}
HELPER="$ROOT/bin/fm-herdr-lab.sh"
SESSION=$("$HELPER" name fm-slot-guard) || exit 1
export HERDR_SESSION="$SESSION"
TMP=$(mktemp -d "$(cd /tmp && pwd -P)/fm-slot-guard-live.XXXXXX")
SLOTS=()
say() { printf '\n=== %s\n' "$*"; }
cleanup() {
  local wt
  for wt in ${SLOTS[@]+"${SLOTS[@]}"}; do treehouse return --force "$wt" >/dev/null 2>&1; done
  "$HELPER" teardown "$SESSION"; echo "teardown rc=$?"
  rm -rf "$TMP"
}
trap cleanup EXIT
unset HERDR_ENV HERDR_PANE_ID HERDR_SOCKET_PATH
"$HELPER" provision "$SESSION" || { echo "provision failed"; exit 1; }
echo "lab session: $SESSION"
lab() { "$HELPER" run "$SESSION" "$@"; }

PROJ="$TMP/project"
mkdir -p "$PROJ"; git -C "$PROJ" init -q -b main
printf '# scratch\n' > "$PROJ/README.md"
printf '.treehouse/\n' > "$PROJ/.gitignore"
printf 'max_trees = 4\nroot = "."\n' > "$PROJ/treehouse.toml"
git -C "$PROJ" add -A
git -C "$PROJ" -c user.name=t -c user.email=t@example.invalid commit -qm initial
git clone -q --bare "$PROJ" "$PROJ.origin.git"
git -C "$PROJ" remote add origin "file://$PROJ.origin.git"
git -C "$PROJ" fetch -q origin

HOME_DIR="$TMP/home"
mkdir -p "$HOME_DIR/state" "$HOME_DIR/config"
printf 'off\n' > "$HOME_DIR/config/herdr-presentation-spaces"
for id in slotA slotB slotC; do
  mkdir -p "$HOME_DIR/data/$id"
  printf '# Task\n## Captain'"'"'s intent\nLive slot guard %s.\n\n## Firstmate spec\nNothing.\n' "$id" > "$HOME_DIR/data/$id/brief.md"
done

spawn() { # <id>
  env FM_GATE_REFUSE_BYPASS=1 HERDR_SESSION="$SESSION" FM_SPAWN_NO_GUARD=1 FM_HOME="$HOME_DIR" FM_ROOT_OVERRIDE="$ROOT" \
    "$ROOT/bin/fm-spawn.sh" "$1" "$PROJ" "sh -c 'echo slot-guard-ok'" \
    --mode no-mistakes --yolo off --backend herdr > "$TMP/$1.out" 2>&1
  local rc=$?
  echo "\$ fm-spawn.sh $1 ... --backend herdr  -> exit $rc"
  sed 's/^/  | /' "$TMP/$1.out" | grep -E 'spawned|error|warning' | head -5
  return $rc
}
meta_field() { grep "^$2=" "$HOME_DIR/state/$1.meta" 2>/dev/null | head -1 | cut -d= -f2-; }
claim_of() { cat "$(dirname "$1")/.fm-slot-owner" 2>/dev/null || echo '<no claim file>'; }

say "S1: fresh spawn of slotA claims its pool slot"
spawn slotA; RC_A=$?
WT_A=$(meta_field slotA worktree); PANE_A=$(meta_field slotA herdr_pane_id)
[ -n "$WT_A" ] && SLOTS+=("$WT_A")
echo "slotA worktree=$WT_A pane=$PANE_A"
echo "claim on slot:"; claim_of "$WT_A" | sed 's/^/  /'
[ "$RC_A" = 0 ] && grep -qx "task=slotA" "$(dirname "$WT_A")/.fm-slot-owner" && echo "S1 RESULT: PASS" || echo "S1 RESULT: FAIL"

say "Park slotA: close its pane so Treehouse sees the slot free, but keep state/slotA.meta"
lab pane close "$PANE_A" >/dev/null 2>&1; echo "pane close rc=$?"
sleep 2
(cd "$PROJ" && treehouse status 2>&1 | sed "s/^/  /")
ls "$HOME_DIR/state/slotA.meta"

say "S2 (adversarial): spawn slotB; Treehouse hands back slotA's slot; spawn must refuse"
CLAIM_BEFORE=$(claim_of "$WT_A")
spawn slotB; RC_B=$?
WT_B_GUESS=$(grep -o "pool slot [^,]*" "$TMP/slotB.out" | head -1 | sed 's/^pool slot //')
echo "refused slot: $WT_B_GUESS"
echo "claim after:"; claim_of "$WT_A" | sed 's/^/  /'
echo "state/slotB.meta exists? $( [ -e "$HOME_DIR/state/slotB.meta" ] && echo yes || echo no)"
if [ "$RC_B" -ne 0 ] && [ "$WT_B_GUESS" = "$WT_A" ] && [ "$(claim_of "$WT_A")" = "$CLAIM_BEFORE" ] \
   && [ ! -e "$HOME_DIR/state/slotB.meta" ] && grep -q "still names task slotA" "$TMP/slotB.out"; then
  echo "S2 RESULT: PASS"
else echo "S2 RESULT: FAIL"; cat "$TMP/slotB.out"; fi

say "Close slotB's leftover refusal pane (named in the error) and drop slotA's record (claim now stale)"
PANE_B=$(grep -o 'inspect window [^ ]*' "$TMP/slotB.out" | tail -1 | awk '{print $3}')
PANE_B=${PANE_B#"$SESSION:"}
echo "leftover pane named by refusal: $PANE_B"
[ -n "$PANE_B" ] && { lab pane close "$PANE_B" >/dev/null 2>&1; echo "pane close rc=$?"; }
rm -f "$HOME_DIR/state/slotA.meta"
(cd "$PROJ" && treehouse status 2>&1 | sed "s/^/  /")
sleep 2

say "S3: spawn slotC; slot claim names recordless slotA -> stale, spawn proceeds and overwrites"
spawn slotC; RC_C=$?
WT_C=$(meta_field slotC worktree); [ -n "$WT_C" ] && SLOTS+=("$WT_C")
echo "slotC worktree=$WT_C"
echo "claim after:"; claim_of "$WT_C" | sed 's/^/  /'
if [ "$RC_C" = 0 ] && [ "$WT_C" = "$WT_A" ] && grep -qx "task=slotC" "$(dirname "$WT_C")/.fm-slot-owner"; then
  echo "S3 RESULT: PASS"
else echo "S3 RESULT: FAIL"; cat "$TMP/slotC.out"; fi

PANE_C=$(meta_field slotC herdr_pane_id)
[ -n "$PANE_C" ] && lab pane close "$PANE_C" >/dev/null 2>&1
