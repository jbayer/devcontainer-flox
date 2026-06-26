# Dev Container for Flox

 **Goal:** frictionless local development using Linux container isolation for untrusted scenarios including package manager commands and using AI agents like Claude Code.

This project includes a Dockerfile for an Ubuntu 26.04 container image to be used as a [Dev Container](https://containers.dev/) base image with [Flox](https://flox.dev) pre-installed. The flox environment in this repository includes Claude Code to demonstrate using AI agents inside the container.

## Why a dev container with Flox?

Running code directly on your host OS means every dependency you install — npm packages, PyPI wheels, Homebrew formulas, `curl | bash` installers, VS Code extensions, even the AI coding agents themselves — executes with full access to your host operating system. That includes your SSH keys, browser cookies, cloud credentials in `~/.aws` and `~/.config`, password manager state, and everything else in your home directory. Modern development stacks pull in hundreds or thousands of transitive dependencies from package managers (npm, pip, cargo, go modules, RubyGems) that have repeatedly been the target of real-world supply chain attacks: typosquatting, maintainer account takeovers, malicious post-install scripts, and dependency confusion. A single compromised package in a deep dependency tree can exfiltrate secrets or install a backdoor before you ever run the code yourself.

A dev container puts a meaningful isolation boundary between unstrusted code and your primary workstation:

- **Blast radius containment** — Malicious post-install scripts, compromised build tools, or a rogue AI agent running `rm -rf` only see the container's filesystem, not your host home directory.
- **No ambient credentials** — Your host's cloud tokens, browser sessions, and keychains aren't visible inside the container. SSH keys are mounted read-only and only when you opt in.
- **Disposable and reproducible** — If something goes wrong (or you just want to be sure), you can rebuild the container from scratch in seconds. Your host stays clean.
- **Flox on top of that** — Flox (built on Nix) gives you pinned, reproducible versions of language runtimes and tools *inside* the container, so you're not layering `curl | bash` installs on top of an isolation boundary you just created. The same `manifest.toml` produces the same environment for every teammate, with a full audit trail of what's installed.

The combination — container isolation for blast radius, Flox for reproducible declarative dependencies — means you can try new tools, run untrusted code, and let coding agents operate more autonomously without putting your workstation at risk.

## Quick start

1. Open this repository in a devcontainer compatible IDE like VS Code.
2. Run **"Dev Containers: Reopen in Container"** from the command palette.
3. The terminal in VS Code should be flox activated by default:

```sh
flox --version

flox list
# should see hello as a package

hello
# should print-out the greeting from the flox package hello
```

To shell into the container while in the project directory 
```sh
# substitute your project directory path
 devcontainer exec --workspace-folder . bash
```

I use `devcontainer` as a package with [my default flox environment](https://hub.flox.dev/jbayer/default) on my host OS.

### Auto-start and shell in on `cd`

For a low-friction workflow, you can have your shell automatically start the dev container and drop you into it whenever you `cd` into a project directory that contains a `.devcontainer/` folder.

**Zsh** (`~/.zshrc`) — uses the built-in `chpwd` hook that fires on every directory change:

```sh
# automatically start a devcontainer via directory navigation
chpwd() {
  if [ -d ".devcontainer" ] && [ -z "$INSIDE_DEVCONTAINER" ]; then
    echo "🐳 Starting devcontainer and connecting..."
    devcontainer up --workspace-folder . && \
    INSIDE_DEVCONTAINER=1 devcontainer exec --workspace-folder . bash
  fi
}
```

**Bash** (`~/.bashrc` or `~/.bash_profile`) — bash has no native `chpwd`, so wrap `cd` in a function:

```sh
# automatically start a devcontainer via directory navigation
cd() {
  builtin cd "$@" || return
  if [ -d ".devcontainer" ] && [ -z "$INSIDE_DEVCONTAINER" ]; then
    echo "🐳 Starting devcontainer and connecting..."
    devcontainer up --workspace-folder . && \
      INSIDE_DEVCONTAINER=1 devcontainer exec --workspace-folder . bash
  fi
}
```

**Fish** (`~/.config/fish/config.fish`) — fish emits a `PWD` variable event you can hook:

```fish
# automatically start a devcontainer via directory navigation
function __devcontainer_autostart --on-variable PWD
    if test -d .devcontainer; and test -z "$INSIDE_DEVCONTAINER"
        echo "🐳 Starting devcontainer and connecting..."
        devcontainer up --workspace-folder .
        and INSIDE_DEVCONTAINER=1 devcontainer exec --workspace-folder . bash
    end
end
```

How it works (applies to all three):

- The hook runs every time the working directory changes: `chpwd` in zsh, a `cd` wrapper in bash, and a `PWD` variable listener in fish.
- The `.devcontainer` check scopes the behavior to project directories that actually define a dev container.
- `INSIDE_DEVCONTAINER` guards against recursive activation — once you're inside the container shell, `cd`-ing around won't trigger another `devcontainer up`.
- `devcontainer up` is idempotent: if the container is already running, it reuses it; otherwise it starts one. Then `devcontainer exec ... bash` drops you into an interactive shell (which, combined with the automatic `flox activate` in `.bashrc`, lands you in a fully activated Flox environment).

When you `exit` the container shell, you're back on your host in the same directory.

### Claude Code

The flox environment for this project includes Claude Code. 

The first time you start claude, it needs to setup global 
settings and authentication. Subsequent restarts will use 
the settings from the docker volume and should persist unless the 
docker volume is reset.

```sh
# launch claude code from a shell in the container that has been flox activated
claude
```

With Claude running in a container, there risk is lower to skip frequent permissions checks.

```sh
# launch claude code from a shell in the container that has been flox activated
claude --dangerously-skip-permissions
```

## What's included

- **`docker/`** — Self-contained image build directory: the `Dockerfile` (builds an Ubuntu 26.04 image with Flox installed via the official `.deb`, with the multi-user Nix workarounds below) plus the `start-nix-daemon.sh` and `entrypoint.sh` scripts it bakes in.
- **`.devcontainer/devcontainer.json`** — Dev Container configuration tuned for Flox and Nix compatibility.
- **`.flox`** - Example flox environment with several packages.

## Nix and container workarounds

Flox uses Nix under the hood, and Nix normally relies on a daemon (`nix-daemon`) managed by systemd. Containers don't run systemd as PID 1, so the packaged `nix-daemon.service` never starts.

This image runs Nix in **multi-user mode** (the daemon model), not single-user mode. In multi-user mode `nix-daemon` runs as **root**, owns the (root-owned) `/nix/store`, and drops privileges to the unprivileged `nixbld*` build users for each build. The `flox` user is only a *client* that talks to the daemon over its socket. This is the safer model inside a container, where users can switch identities: store integrity is enforced by the root daemon over the socket rather than by filesystem ownership, so an unprivileged user can't tamper with the store.

The Flox `.deb` lays down a root-owned `/nix` and a multi-user `nix.conf`, but inside a container **build** it does *not* create the `nixbld` build users (it leaves `build-users-group` empty, which would make the root daemon run builds as root). The Dockerfile therefore creates the standard `nixbld1..32` pool and sets `build-users-group = nixbld`. The remaining piece is *starting the daemon without systemd*, which this repo handles as follows:

- **`docker/start-nix-daemon.sh`** — Reproduces the systemd unit's `ExecStart=/usr/sbin/nix-daemon --daemon`. It must run as root, is idempotent (no-op if a daemon is already running), clears a stale socket left on the persistent `/nix` volume, and waits for the socket before returning. It launches the daemon with `env -u NIX_REMOTE` so the daemon accesses the local store directly — otherwise it inherits the image-wide `NIX_REMOTE=daemon` and tries to proxy to *itself* (`cannot open connection to remote store 'daemon'`).
- **`postStartCommand: "sudo /usr/local/bin/start-nix-daemon.sh"`** — In the dev container, the daemon is started this way on every container start (the `flox` user has `NOPASSWD` sudo). Dev Containers manage their own keep-alive process and override the image `ENTRYPOINT`, so a lifecycle hook is the reliable place to start the daemon.
- **`docker/entrypoint.sh`** — Covers any launcher that does *not* override the image `ENTRYPOINT` (plain `docker run`, and Apple Container via the `acdev` wrapper). On every boot it heals `/home/flox` ownership and starts the root daemon, then `exec`s the container command. It works whether it starts as root (`docker run`'s default user — runs the helpers directly, then drops to `flox` for a bare shell) or as the `flox` user (acdev launches with `--user flox … sleep infinity` — runs the helpers via `NOPASSWD` sudo, then `exec`s `sleep infinity` as PID 1). Because `start-nix-daemon.sh` blocks until the socket is ready, later `container exec` shells — which do *not* re-run the entrypoint — reach the daemon over the shared socket with no startup race.
- **`NIX_REMOTE=daemon`** — Set in the Dockerfile so clients talk to the daemon over its socket.
- **`NIX_SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt`** — Gives the daemon a CA bundle so it can fetch from substituters (caches).

> **Migrating from a single-user setup:** the `/nix` volume was renamed to `devcontainer-nix-store-multiuser` so a fresh, correctly-owned (root) store is seeded from the image. An old single-user `/nix` volume is `flox`-owned and incompatible with the daemon. Remove it with `docker volume rm devcontainer-nix-store` if it lingers.

## Dev Container configuration details

The `devcontainer.json` includes several settings for a smooth experience:

- **Named Docker volume for `/nix`** — A persistent volume (`nix-store`) is mounted at `/nix` so that packages installed via `flox install` survive container rebuilds. Without this, every rebuild would require re-downloading all Nix store paths.
- **Named Docker volume for `/home/flox`** — The entire home directory is persisted so that shell history, Claude Code authentication, and other user-level configuration survive container rebuilds. Because the home dir is a persistent volume, the `flox` user is pinned to a fixed **uid/gid 1000** (claimed by removing the base image's default `ubuntu` user) so it never drifts between image versions and lose access to its own home. As a safety net, the `postStartCommand` runs `fix-home-perms.sh`, which re-`chown`s `/home/flox` to `flox` if a volume created by an older image has stale ownership.
- **SSH key forwarding** — Your host `~/.ssh` directory is bind-mounted (read-only) into the container so that Git commit signing and SSH-based remotes work transparently.
- **Git feature** — The Dev Container `git` feature is included to manage the Git version independently of the base image.
- **Non-root user** — The container runs as `flox` rather than root, following security best practices.

## Automatic Flox activation

When you open the dev container, any interactive shell automatically runs `flox activate` against the project's Flox environment — so the env's packages and hooks are available immediately, with no manual step. This works in the VS Code integrated terminal, `devcontainer exec`, and `docker exec -it`.

How it works:

- The image ships `/etc/profile.d/flox-autoactivate.sh`, sourced from both `/etc/bash.bashrc` (interactive non-login shells) and `/etc/profile.d` (login shells).
- `devcontainer.json` sets `FLOX_AUTOACTIVATE_DIR=${containerWorkspaceFolder}`, so activation targets the **project workspace** specifically. For plain `docker run` (no devcontainer), it falls back to the current directory.
- It activates only if `<dir>/.flox/env/manifest.toml` exists; otherwise the shell starts normally.
- It's guarded by `$FLOX_ENV`, so it activates once per shell and won't recurse into sub-processes.
- Activation is deferred to just before the first prompt (via `PROMPT_COMMAND`) so it runs *after* `~/.bashrc` finalizes `PS1`. Otherwise flox's `flox [env]` prompt indicator — which it applies by setting `PS1` during activation — would be overwritten by `~/.bashrc` (bash sources it after `/etc/bash.bashrc`).

The snippet lives in `/etc` rather than `~/.bashrc` on purpose: the dev container mounts a persistent volume over `/home/flox`, which would mask anything baked into the home directory after the first build (the same reason the Nix store setup lives outside the home dir).

> First activation in a fresh environment may pull or build the env's packages via the daemon, so the very first shell can take a moment; subsequent shells are instant.

## Building the Docker image

To rebuild the image after making changes to the Dockerfile:

```bash
docker buildx build -t jbayer/devcontainer-flox:1.13.0 -t jbayer/devcontainer-flox:latest docker/
docker push  --all-tags jbayer/devcontainer-flox
```

The build context is the `docker/` directory, which contains everything the image needs and nothing else.

After pushing, rebuild the dev container in VS Code via **"Dev Containers: Rebuild Container"** from the command palette to pick up the new image.

> **Note:** The persistent volumes for `/nix` and `/home/flox` will retain their existing contents across image updates. If you need a clean slate (e.g., after a Flox version upgrade in the Dockerfile), delete the volumes manually:
> ```bash
> docker volume rm devcontainer-nix-store-multiuser <basename>-flox-home
> ```

## Using the pre-built image

The image is published on Docker Hub:

```
jbayer/devcontainer-flox:latest
```

To use it, open this repository in VS Code and run **"Dev Containers: Reopen in Container"** from the command palette. The dev container configuration will pull the image automatically.

## Customizing for your project

This repository is a starting point. You can modify it to fit your needs:

- **Dockerfile** — Add system packages, change the base image, or pin a specific Flox version.
- **`devcontainer.json`** — Add VS Code extensions, change the `postCreateCommand` to run project setup (e.g., `flox install` from a checked-in `manifest.toml`), or add additional mounts and environment variables.
- **Flox environment** — Run `flox init` and `flox install <package>` inside the container to build up your environment, then commit the `.flox/` directory so teammates get the same dependencies automatically.
- Easily add a devcontainer to new projects: `ln -s ~/workspaces/devcontainers/.devcontainer ~/workspaces/some-project/.devcontainer`

