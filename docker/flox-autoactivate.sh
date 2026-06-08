# Flox project auto-activation for interactive shells.
#
# When an interactive shell starts, activate the project's Flox environment in
# place so the env's packages and hooks are available immediately. Targets
# $FLOX_AUTOACTIVATE_DIR (the devcontainer sets this to the workspace folder)
# and falls back to the current directory for plain `docker run`.
#
# Guarded by $FLOX_ENV so it runs once per shell and won't recurse into the
# sub-processes the activation spawns. This lives in /etc (sourced from
# /etc/bash.bashrc and /etc/profile.d) rather than ~/.bashrc because the
# devcontainer mounts a persistent volume over /home/flox, which would mask
# anything baked into the home directory after the first build.

if [ -n "${PS1:-}" ] && [ -z "${FLOX_ENV:-}" ] && command -v flox >/dev/null 2>&1; then
  _flox_dir="${FLOX_AUTOACTIVATE_DIR:-$PWD}"
  if [ -f "$_flox_dir/.flox/env/manifest.toml" ]; then
    eval "$(flox activate -d "$_flox_dir")"
  fi
  unset _flox_dir
fi
