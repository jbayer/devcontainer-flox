# Use Ubuntu 26.04 as the LTS base
FROM ubuntu:26.04

# Avoid interactive prompts
ENV DEBIAN_FRONTEND=noninteractive

# 1. Install minimum requirements for the installer
#    procps provides pgrep, used to detect a running nix-daemon.
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    ca-certificates \
    sudo \
    xz-utils \
    openssh-client \
    git \
    procps \
    && rm -rf /var/lib/apt/lists/*

# 2. Run the official Flox installer script
# This script detects your CPU architecture and installs the correct .deb automatically.
# The .deb lays down a root-owned /nix store and a multi-user nix.conf, but in a
# container build it does NOT create the nixbld build users (see step 3).
RUN curl https://downloads.flox.dev/by-env/stable/deb/flox-1.15.0.aarch64-linux.deb \
    -o flox.aarch64-linux.deb && \
    dpkg -i flox.aarch64-linux.deb && \
    rm flox.aarch64-linux.deb

# 3. Create the nixbld build-user pool.
#    On a normal host the flox .deb creates nixbld1..32 and sets
#    build-users-group=nixbld. Inside a container *build* it cannot create
#    users, so it leaves build-users-group empty — which would make the root
#    daemon run builds AS ROOT, defeating multi-user isolation. Recreate the
#    standard pool (gid/uid 30000+, matching the Nix installer) and point nix
#    at it, then give the store the conventional root:nixbld 1775 ownership.
RUN groupadd -g 30000 nixbld && \
    for i in $(seq 1 32); do \
      useradd -u $((30000 + i)) -g nixbld -G nixbld \
        -d /var/empty -s /usr/sbin/nologin -c "Nix build user $i" "nixbld$i"; \
    done && \
    sed -i 's/^build-users-group =.*/build-users-group = nixbld/' /etc/nix/nix.conf && \
    chown -R root:nixbld /nix/store /nix/var/nix && \
    chmod 1775 /nix/store

# 4. Setup the non-root user. In multi-user mode this user is just a daemon
#    *client*; it does NOT own /nix. NOPASSWD sudo lets the devcontainer
#    postStartCommand start the root daemon and heal home-dir ownership.
#
#    Pin flox to a fixed uid/gid (1000) so it never drifts: the home directory
#    is a persistent volume, and if flox's uid changes between image versions
#    (e.g. because the nixbld pool above shifts the next auto-assigned uid) the
#    user loses access to its own home. We claim 1000 (the conventional dev
#    uid, friendly to host bind mounts) by removing the base image's default
#    `ubuntu` user that otherwise holds it.
RUN userdel -r ubuntu 2>/dev/null || true; groupdel ubuntu 2>/dev/null || true; \
    groupadd -g 1000 flox && \
    useradd -m -u 1000 -g 1000 -s /bin/bash flox && \
    echo "flox ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

# 5. Multi-user Nix instead of the daemon-less single-user workaround.
#    - NIX_REMOTE=daemon: clients talk to the root daemon over its socket.
#    - NIX_SSL_CERT_FILE: give the daemon a CA bundle for fetching from caches.
#    - trusted-users: let the flox client use the configured substituters.
#    (Note: we deliberately do NOT chown /nix to flox — the store stays
#     root-owned, which is the whole point of multi-user mode.)
ENV NIX_REMOTE=daemon
ENV NIX_SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt
RUN printf '\ntrusted-users = root flox\n' >> /etc/nix/nix.conf

# 6. Install the daemon-start and entrypoint scripts.
COPY start-nix-daemon.sh /usr/local/bin/start-nix-daemon.sh
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
COPY fix-home-perms.sh /usr/local/bin/fix-home-perms.sh
RUN chmod +x /usr/local/bin/start-nix-daemon.sh /usr/local/bin/entrypoint.sh \
      /usr/local/bin/fix-home-perms.sh

WORKDIR /home/flox

# 7. Auto-activate the project's Flox environment in interactive shells.
#    Installed in /etc (not ~/.bashrc) because the devcontainer mounts a
#    persistent volume over /home/flox that would mask the home directory.
#    Sourced from both /etc/bash.bashrc (interactive non-login shells, e.g.
#    the VS Code terminal and `docker exec -it`) and /etc/profile.d (login
#    shells). The devcontainer points it at the workspace via
#    FLOX_AUTOACTIVATE_DIR; otherwise it falls back to $PWD.
COPY flox-autoactivate.sh /etc/profile.d/flox-autoactivate.sh
RUN printf '\n# Flox project auto-activation\n. /etc/profile.d/flox-autoactivate.sh\n' \
      >> /etc/bash.bashrc

# 7b. Pre-trust the default base environment (jbayer/default) that step 7 layers
#     into every shell. flox refuses to activate a *remote* environment until it
#     is trusted, because activation hooks run arbitrary code; on a host that
#     prompt is interactive. In a headless container (acdev `container exec`,
#     devcontainer terminal) there is no one to answer it, so the first
#     activation would fail. Set the trust system-wide in /etc/flox.toml (the
#     flox .deb's system config) rather than the flox user's ~/.config: the
#     system file applies to every user and is not masked by the persistent
#     /home/flox volume the devcontainer mounts over the home directory.
RUN printf '\n[trusted_environments]\n"jbayer/default" = "trust"\n' >> /etc/flox.toml

# Verify the installation (runs as root at build time; no daemon needed for --version)
RUN flox --version

# Container runs as root so the entrypoint can start the root daemon; the
# devcontainer connects as the unprivileged `flox` user via remoteUser.
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["/bin/bash"]
