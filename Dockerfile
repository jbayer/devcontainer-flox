# Use Ubuntu 26.04 as the LTS base
FROM ubuntu:26.04

# Avoid interactive prompts
ENV DEBIAN_FRONTEND=noninteractive

# 1. Install minimum requirements for the installer
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    ca-certificates \
    sudo \
    xz-utils \
    openssh-client \
    && rm -rf /var/lib/apt/lists/*

# 2. Run the official Flox installer script
# This script detects your CPU architecture and installs the correct .deb automatically
RUN curl -O https://downloads.flox.dev/by-env/stable/deb/flox.aarch64-linux.deb && \
    dpkg -i flox.aarch64-linux.deb && \
    rm flox.aarch64-linux.deb

# 3. Setup a non-root user (Flox requires this for certain Nix features)
RUN useradd -ms /bin/bash floxuser && \
    echo "floxuser ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers && \
    chown -R floxuser:floxuser /nix

# 4. Bypass nix-daemon (systemd is not PID 1 in containers)
ENV NIX_REMOTE=auto

USER floxuser
WORKDIR /home/floxuser

# 5. Auto-activate Flox environment if present in the working directory
RUN echo 'if [ -f .flox/env/manifest.toml ]; then eval "$(flox activate)"; fi' >> /home/floxuser/.bashrc

# Verify the installation
RUN flox --version

CMD ["/bin/bash"]