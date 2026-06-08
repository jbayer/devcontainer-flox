#!/usr/bin/env bash
# Start the multi-user Nix daemon without systemd.
#
# Multi-user Nix runs `nix-daemon` as root; it owns /nix/store and drops to the
# unprivileged nixbld* build users for each build. Containers don't run systemd
# as PID 1, so the packaged nix-daemon.service never starts. This script
# reproduces what that unit does (ExecStart=/usr/sbin/nix-daemon --daemon) so it
# can be invoked from a container entrypoint or a devcontainer postStartCommand.
#
# It MUST run as root. It is idempotent: if a daemon is already running it is a
# no-op, and it removes a stale socket left over on a persistent /nix volume.
set -euo pipefail

SOCKET=/nix/var/nix/daemon-socket/socket
DAEMON=/usr/sbin/nix-daemon
LOG=/var/log/nix-daemon.log

# The daemon needs a CA bundle to fetch from substituters (caches). The systemd
# unit points NIX_SSL_CERT_FILE at a store path; in a container the system
# bundle from the ca-certificates package is more robust.
export NIX_SSL_CERT_FILE="${NIX_SSL_CERT_FILE:-/etc/ssl/certs/ca-certificates.crt}"

if [ "$(id -u)" -ne 0 ]; then
  echo "start-nix-daemon: must run as root (try: sudo $0)" >&2
  exit 1
fi

if pgrep -x nix-daemon >/dev/null 2>&1; then
  echo "start-nix-daemon: nix-daemon already running"
  exit 0
fi

# No live daemon: clear any stale socket persisted on the /nix volume.
rm -f "$SOCKET"
mkdir -p "$(dirname "$SOCKET")"

# Match the resource limits the systemd unit sets (LimitNOFILE=1048576).
ulimit -n 1048576 2>/dev/null || true

echo "start-nix-daemon: launching $DAEMON --daemon"
# The daemon must access the *local* store directly. We set NIX_REMOTE=daemon
# image-wide for clients, but the daemon must NOT inherit it or it tries to
# proxy to itself ("cannot open connection to remote store 'daemon'"). Unset it
# only for the daemon process; client shells keep NIX_REMOTE=daemon.
setsid env -u NIX_REMOTE "$DAEMON" --daemon >>"$LOG" 2>&1 </dev/null &

# Wait for the socket to accept connections before returning, so the first
# flox/nix command doesn't race the daemon's startup.
for _ in $(seq 1 100); do
  if [ -S "$SOCKET" ]; then
    echo "start-nix-daemon: ready ($SOCKET)"
    exit 0
  fi
  sleep 0.1
done

echo "start-nix-daemon: timed out waiting for $SOCKET (see $LOG)" >&2
exit 1
