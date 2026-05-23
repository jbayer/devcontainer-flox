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
    git \
    && rm -rf /var/lib/apt/lists/*

# 2. Run the official Flox installer script
# This script detects your CPU architecture and installs the correct .deb automatically
RUN curl https://downloads.flox.dev/by-env/stable/deb/flox-1.12.1.aarch64-linux.deb \
    -o flox.aarch64-linux.deb && \
    dpkg -i flox.aarch64-linux.deb && \
    rm flox.aarch64-linux.deb

# 3. Setup a non-root user (Flox requires this for certain Nix features)
RUN useradd -ms /bin/bash flox && \
    echo "flox ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers && \
    chown -R flox:flox /nix

# 4. Bypass nix-daemon (systemd is not PID 1 in containers)
ENV NIX_REMOTE=auto

USER flox
WORKDIR /home/flox

# 5. Auto-activate FloxHub default environment, then layer local environment if present
RUN echo 'eval "$(flox activate -r jbayer/default)"' >> /home/flox/.bashrc && \
    echo 'if [ -f .flox/env/manifest.toml ]; then eval "$(flox activate)"; fi' >> /home/flox/.bashrc

# Verify the installation
RUN flox --version

CMD ["/bin/bash"]