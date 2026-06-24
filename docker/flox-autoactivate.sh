# Flox auto-activation for interactive shells.
#
# Activates two layers so their packages, hooks, and prompt indicator are
# available:
#   1. The default base environment on FloxHub (jbayer/default), pulled and
#      activated with `-m run`. Attempted for every shell. Overridable per
#      container via $FLOX_AUTOACTIVATE_DEFAULT; set it empty to skip the base.
#   2. An additional *project* environment layered on top: $FLOX_AUTOACTIVATE_DIR
#      (the devcontainer sets this to the workspace folder), falling back to the
#      current directory for plain `docker run`. Only layered if
#      <dir>/.flox/env/manifest.toml exists; otherwise just the base is active.
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
#
# Both activations are best-effort: `flox activate` only emits its eval script
# on success, so a failed pull (e.g. offline) yields an empty eval and the
# shell still starts.

# Default base environment on FloxHub, activated for every shell unless
# overridden (set FLOX_AUTOACTIVATE_DEFAULT empty to disable).
FLOX_AUTOACTIVATE_DEFAULT="${FLOX_AUTOACTIVATE_DEFAULT-jbayer/default}"

if [ -n "${PS1:-}" ] && [ -z "${FLOX_ENV:-}" ] && command -v flox >/dev/null 2>&1; then
  _flox_dir="${FLOX_AUTOACTIVATE_DIR:-$PWD}"
  _FLOX_AUTOACTIVATE_DEFAULT_PENDING="$FLOX_AUTOACTIVATE_DEFAULT"
  [ -f "$_flox_dir/.flox/env/manifest.toml" ] && _FLOX_AUTOACTIVATE_DIR_PENDING="$_flox_dir"
  _flox_autoactivate() {
    # Single-shot: activate the first time the prompt is about to render.
    [ -n "${_FLOX_AUTOACTIVATE_DONE:-}" ] && return
    _FLOX_AUTOACTIVATE_DONE=1
    # Default base layer first, then the project layer on top of it.
    [ -n "${_FLOX_AUTOACTIVATE_DEFAULT_PENDING:-}" ] && \
      eval "$(flox activate -r "$_FLOX_AUTOACTIVATE_DEFAULT_PENDING" -m run)"
    [ -n "${_FLOX_AUTOACTIVATE_DIR_PENDING:-}" ] && \
      eval "$(flox activate -d "$_FLOX_AUTOACTIVATE_DIR_PENDING")"
  }
  PROMPT_COMMAND="_flox_autoactivate${PROMPT_COMMAND:+;$PROMPT_COMMAND}"
  unset _flox_dir
fi
