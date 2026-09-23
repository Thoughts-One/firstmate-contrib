=== --herdr-retire-session mbk: generated Herdr section
# Herdr retirement - HARD SAFETY CONTRACT
This brief was explicitly scaffolded with `--herdr-retire-session mbk` because the task's only Herdr lifecycle action is guardedly stopping one explicitly named, pre-existing session Firstmate did not provision.

1. Run only `'/home/kai/.no-mistakes/worktrees/7605832e1988/01M37B0RQQNJCETNMN3JNG4954/bin/fm-herdr-session-retire.sh' 'mbk'` to stop it.
   It refuses the target unless it is empty, refuses `default`, `fm-remote`, and every `fm-lab-*` name, snapshots and re-verifies every other session before and after the call, and never deletes, restarts, or force-stops anything.
2. If it refuses, stop and report the exact refusal; do not fall back to a direct `herdr session stop` or any other bypass.
3. Forbidden commands: direct `herdr server stop` or any other server-global operation, direct `herdr session stop`, direct `herdr session delete`, and any Herdr call scoped only by ambient or inline `HERDR_SESSION`.
4. This is a different helper from `bin/fm-herdr-lab.sh`: it only ever operates on the one pre-existing session named above, never on a generated verification session.

Never bypass the helper, even for a read-only lifecycle probe or cleanup after failure.
The captain fleet uses the running `default` session.


=== unguarded brief: generated Herdr section
# Herdr lifecycle declaration - NOT ENABLED
**HARD SAFETY GATE:** this scaffold cannot inspect the task text filled in above.
If the task will start, stop, delete, restart, profile, or otherwise drive Herdr lifecycle behavior, stop and regenerate the brief with `--herdr-lab` before dispatch.
If the task's only Herdr lifecycle action is stopping one explicitly named, pre-existing session Firstmate did not provision, stop and regenerate the brief with `--herdr-retire-session <name>` before dispatch instead.
Do not add Herdr lifecycle commands to this unguarded brief by hand.

