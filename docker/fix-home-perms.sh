#!/usr/bin/env bash
# Ensure /home/flox is owned by the flox user.
#
# The devcontainer mounts a persistent named volume over /home/flox. If that
# volume was created by an older image where the flox user had a different uid
# (e.g. before flox's uid was pinned), the flox user can no longer access its
# own home — it can't read ~/.bashrc or create ~/.config. Heal that here.
#
# Must run as root (via the devcontainer postStartCommand's sudo). Read-only
# bind mounts inside the home dir (.gitconfig, .ssh) can't be chowned and are
# left to the host; those errors are expected and ignored.
set -euo pipefail

flox_uid="$(id -u flox)"
if [ "$(stat -c %u /home/flox)" != "$flox_uid" ]; then
  echo "fix-home-perms: chowning /home/flox to flox ($flox_uid)"
  chown -R flox:flox /home/flox 2>/dev/null || true
fi
