# Flox project auto-activation for interactive shells.
#
# Activates the project's Flox environment so its packages, hooks, and prompt
# indicator are available. Targets $FLOX_AUTOACTIVATE_DIR (the devcontainer
# sets this to the workspace folder) and falls back to the current directory
# for plain `docker run`. Only activates if <dir>/.flox/env/manifest.toml
# exists; otherwise the shell starts normally.
#
# Activation is *deferred* to just before the first prompt via PROMPT_COMMAND.
# This matters for the prompt: bash sources /etc/bash.bashrc (where this is
# wired in) BEFORE ~/.bashrc, and flox shows its `flox [env]` indicator by
# setting PS1 during activation. If we activated immediately, ~/.bashrc would
# run afterward and overwrite PS1, dropping the indicator. Running at the first
# prompt means PS1 is already final, so flox's indicator sticks.
#
# Guarded by $FLOX_ENV so it runs once per shell and won't recurse into the
# sub-processes activation spawns. Lives in /etc (sourced from /etc/bash.bashrc
# and /etc/profile.d) rather than ~/.bashrc because the devcontainer mounts a
# persistent volume over /home/flox that would mask the home directory.

if [ -n "${PS1:-}" ] && [ -z "${FLOX_ENV:-}" ] && command -v flox >/dev/null 2>&1; then
  _flox_dir="${FLOX_AUTOACTIVATE_DIR:-$PWD}"
  if [ -f "$_flox_dir/.flox/env/manifest.toml" ]; then
    _FLOX_AUTOACTIVATE_DIR_PENDING="$_flox_dir"
    _flox_autoactivate() {
      # Single-shot: activate the first time the prompt is about to render.
      [ -n "${_FLOX_AUTOACTIVATE_DONE:-}" ] && return
      _FLOX_AUTOACTIVATE_DONE=1
      eval "$(flox activate -d "$_FLOX_AUTOACTIVATE_DIR_PENDING")"
    }
    PROMPT_COMMAND="_flox_autoactivate${PROMPT_COMMAND:+;$PROMPT_COMMAND}"
  fi
  unset _flox_dir
fi
