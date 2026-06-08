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
RUN curl https://downloads.flox.dev/by-env/stable/deb/flox-1.12.2.aarch64-linux.deb \
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

# 4. Setup a non-root user. In multi-user mode this user is just a daemon
#    *client*; it does NOT own /nix. NOPASSWD sudo lets the devcontainer
#    postStartCommand start the root daemon.
RUN useradd -ms /bin/bash flox && \
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
RUN chmod +x /usr/local/bin/start-nix-daemon.sh /usr/local/bin/entrypoint.sh

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

# Verify the installation (runs as root at build time; no daemon needed for --version)
RUN flox --version

# Container runs as root so the entrypoint can start the root daemon; the
# devcontainer connects as the unprivileged `flox` user via remoteUser.
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["/bin/bash"]
