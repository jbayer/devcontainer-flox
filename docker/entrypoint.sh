#!/usr/bin/env bash
# Container entrypoint: initialize multi-user Nix on every boot, then hand off
# to the container's command so that command becomes PID 1.
#
# Two of the three launchers for this image come through here:
#
#   * Plain `docker run` / `container run` (Apple Container, via the `acdev`
#     wrapper). This entrypoint runs: it heals /home/flox ownership, starts the
#     root nix-daemon, then execs the requested command.
#       - `docker run` starts as root (the image's default user); with no
#         command (or a bare `/bin/bash`) we drop to the unprivileged `flox`
#         user for an interactive login shell.
#       - acdev launches `--user flox ... sleep infinity`, so this script runs
#         AS flox: it uses the passwordless sudo the image grants flox to start
#         the root daemon, then execs the `sleep infinity` keepalive as PID 1.
#         acdev later opens interactive shells with `container exec`, which are
#         separate processes that do NOT re-run this entrypoint — but they reach
#         the daemon over the socket this boot leaves on the shared filesystem.
#
#   * Dev Containers override the image ENTRYPOINT and manage their own
#     keep-alive, so this script does not run there; that path starts the daemon
#     from devcontainer.json's postStartCommand instead.
#
# Re-runs cleanly on every boot. `container stop` kills the daemon, so init must
# happen again on `container start`: start-nix-daemon.sh is idempotent and
# blocks until the socket is ready before returning, so the first flox/nix
# command in a later exec session never races the daemon's startup.
set -euo pipefail

# fix-home-perms.sh and start-nix-daemon.sh must run as root. When this
# entrypoint itself starts as root (docker run) we invoke them directly; when it
# starts as the flox user (acdev's `--user flox`) we go through sudo.
if [ "$(id -u)" -eq 0 ]; then
  as_root() { "$@"; }
else
  as_root() { sudo "$@"; }
fi

as_root /usr/local/bin/fix-home-perms.sh   || echo "entrypoint: fix-home-perms failed" >&2
as_root /usr/local/bin/start-nix-daemon.sh || echo "entrypoint: nix-daemon failed to start" >&2

# Started as root with no command (or just a bare shell): drop to the
# unprivileged flox user for an interactive login shell. (acdev runs as flox and
# passes `sleep infinity`, so it falls through to the exec below.)
if [ "$(id -u)" -eq 0 ]; then
  if [ "$#" -eq 0 ] || { [ "$#" -eq 1 ] && [ "$1" = "/bin/bash" ]; }; then
    exec runuser -u flox -- /bin/bash -l
  fi
fi

exec "$@"
