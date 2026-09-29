# shared setup for the live Herdr lab drivers (sourced)
ROOT=/home/kai/.no-mistakes/worktrees/7605832e1988/01M3NV6RPFZHAGKKAQPHXE80HQ
EV=/home/kai/.no-mistakes/evidence/01M3NV6RPFZHAGKKAQPHXE80HQ
LAB_HELPER=$ROOT/bin/fm-herdr-lab.sh
ORIGINAL_PATH=$PATH
setup_lab() { # <label>
  SESSION=$("$LAB_HELPER" name "$1")
  TMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/fm-lab-live.XXXXXX")
  FAKEBIN=$TMP_ROOT/fakebin; CLAUDEBIN=$TMP_ROOT/claudebin; mkdir -p "$FAKEBIN" "$CLAUDEBIN"
  # herdr shim: route every adapter herdr call through the lab helper
  cat > "$FAKEBIN/herdr" <<EOS
#!/usr/bin/env bash
set -euo pipefail
helper='$LAB_HELPER'; session='$SESSION'; real_path='$ORIGINAL_PATH'
args=("\$@"); n=\${#args[@]}
if [ "\$n" -ge 2 ] && [ "\${args[\$((n-2))]}" = --session ]; then
  [ "\${args[\$((n-1))]}" = "\$session" ] || { echo "wrapper refused foreign session" >&2; exit 97; }
  args=("\${args[@]:0:\$((n-2))}")
else
  [ "\${HERDR_SESSION:-}" = "\$session" ] || { echo "wrapper requires lab session" >&2; exit 98; }
fi
PATH="\$real_path" exec "\$helper" run "\$session" "\${args[@]}"
EOS
  chmod +x "$FAKEBIN/herdr"
  # fake harness: records its own environment then exits (pane returns to a shell)
  cat > "$CLAUDEBIN/claude" <<'EOS'
#!/bin/sh
out=${FM_LAB_DUMP:-/tmp/fm-lab-claude-dump}
{ echo "--- launch $(date +%s)"; env | grep -E '^(FM_LAB_|MODEL=|EFFORT=|MODE=|TRACEPARENT=)' | sort; } >> "$out"
exit 0
EOS
  chmod +x "$CLAUDEBIN/claude"
}
