#!/usr/bin/env bash
# Container entrypoint for plain `docker run` usage.
#
# Dev Containers manage their own keep-alive process and override the image
# ENTRYPOINT, so for that path the daemon is started via postStartCommand
# instead (see devcontainer.json). This entrypoint covers `docker run`: it
# starts the root nix-daemon, then drops to the unprivileged `flox` user.
set -euo pipefail

if [ "$(id -u)" -eq 0 ]; then
  /usr/local/bin/start-nix-daemon.sh || echo "entrypoint: nix-daemon failed to start" >&2

  # Default (no command, or a bare shell) -> run as the non-root flox user.
  if [ "$#" -eq 0 ] || { [ "$#" -eq 1 ] && [ "$1" = "/bin/bash" ]; }; then
    exec runuser -u flox -- /bin/bash -l
  fi
fi

exec "$@"
