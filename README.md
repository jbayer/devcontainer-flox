# Dev Container for Flox

**Goal:** frictionless local development inside a Linux container, so untrusted code (package manager installs, AI agents like Claude Code) runs isolated from your workstation.

This repo builds an Ubuntu 26.04 [Dev Container](https://containers.dev/) image with [Flox](https://flox.dev) pre-installed, plus an example project that uses it.

## Why a dev container with Flox?

Every dependency you install on your host (npm/PyPI/cargo packages, `curl | bash` installers, editor extensions, coding agents) runs with access to your SSH keys, cloud credentials and home directory. Supply-chain attacks (typosquatting, hijacked maintainer accounts, malicious post-install scripts) make that a real risk.

- **Contained blast radius:** a rogue script or agent only sees the container's filesystem.
- **No ambient credentials:** host tokens, browser sessions and keychains aren't visible; `~/.ssh` is mounted read-only.
- **Disposable:** rebuild the container from scratch whenever you like.
- **Reproducible tooling:** Flox gives pinned, declarative packages inside the container instead of ad-hoc installs.

## Layout

| Path | Purpose |
| --- | --- |
| `docker/` | Image build context: `Dockerfile` and the scripts it bakes in |
| `example/.devcontainer/devcontainer.json` | Dev Container config that uses the published image |
| `example/.flox/` | Example project environment (`jbayer/example`, installs `hello`) |
| `.flox/` | Host-side environment (`jbayer/devcontainers`, macOS only): provides the `devcontainer` CLI and the auto-start hook |

## Quick start

**VS Code:** open the `example/` folder and run **Dev Containers: Reopen in Container**.

**Terminal (macOS, zsh):**

```sh
cd ~/workspaces/devcontainers
flox activate          # provides the devcontainer CLI + auto-start hook
cd example             # starts the container and drops you into a shell
```

Inside the container the shell is already Flox-activated:

```sh
flox list   # hello: hello (2.12.3)
hello       # Hello, world!
```

To connect manually instead: `devcontainer up --workspace-folder example && devcontainer exec --workspace-folder example bash`.

### Using it in another project

From an activated root environment, run `devc` (symlinks `example/.devcontainer` into the current directory) or `devc-cp` (copies it). Also commit a `.flox/` environment for the project.

### Auto-start on `cd`

The root environment's zsh profile defines a `chpwd` hook: when you `cd` into a directory containing `.devcontainer/`, it runs `devcontainer up` and then `devcontainer exec ... bash`. `INSIDE_DEVCONTAINER` prevents recursion, and `exit` returns you to the host. For bash, wrap `cd` the same way:

```sh
cd() {
  builtin cd "$@" || return
  if [ -d .devcontainer ] && [ -z "$INSIDE_DEVCONTAINER" ]; then
    devcontainer up --workspace-folder . &&
      INSIDE_DEVCONTAINER=1 devcontainer exec --workspace-folder . bash
  fi
}
```

## Automatic Flox activation in the container

`/etc/profile.d/flox-autoactivate.sh` (sourced from `/etc/bash.bashrc` and login shells) activates two layers just before the first prompt:

1. **`jbayer/default`** from FloxHub (`-m run`), shared tools and the prompt. Override it with `FLOX_AUTOACTIVATE_DEFAULT`, or set it empty to skip. It's marked trusted in `/etc/flox.toml`.
2. **The project environment** at `$FLOX_AUTOACTIVATE_DIR` (set to the workspace folder by `devcontainer.json`, otherwise `$PWD`), if `.flox/env/manifest.toml` exists.

The prompt looks like `flox [example] 🐧 <hostname>:example$`. `FLOX_HIDE_DEFAULT_PROMPT=true` (in `remoteEnv`) hides `default` from the label. The script lives in `/etc` because `/home/flox` is a persistent volume that would mask anything baked into the home directory.

## Dev Container configuration

- **`/nix` volume** (`devcontainer-nix-store-multiuser`): the Nix store survives rebuilds.
- **`/home/flox` volume** (`<folder>-flox-home`): shell history, Flox config and agent logins survive rebuilds. The `flox` user is pinned to uid/gid 1000, and `fix-home-perms.sh` repairs ownership on start.
- **Read-only mounts:** `~/.ssh` and `~/.gitconfig`, plus the SSH agent socket.
- **Non-root:** runs as `flox` (with `NOPASSWD` sudo for the startup helpers).

## Nix without systemd

Nix runs in **multi-user mode**: a root `nix-daemon` owns `/nix/store` and builds as the `nixbld*` users; `flox` is just a client. Containers have no systemd, so:

- The Dockerfile creates the `nixbld1..32` pool and sets `build-users-group = nixbld`, which the Flox `.deb` skips in container builds.
- `start-nix-daemon.sh` (run by `postStartCommand`) starts the daemon idempotently, clears a stale socket, and waits until it's ready. It unsets `NIX_REMOTE` so the daemon doesn't try to proxy to itself.
- `entrypoint.sh` does the same for launchers that keep the image `ENTRYPOINT` (plain `docker run`, Apple Container).
- `NIX_REMOTE=daemon` and `NIX_SSL_CERT_FILE` are set image-wide.

## Claude Code

None of the environments include Claude Code by default. Add it to the project (or `jbayer/default`) with `flox install claude-code`. The login persists in the `/home/flox` volume, and because the container is the sandbox, `claude --dangerously-skip-permissions` is a reasonable trade-off.

## Troubleshooting

- **"The environment lockfile refers to a version of the environment that does not exist locally"**: an `env.lock` was committed with a `local_rev` that was never pushed. Run `flox push` on the machine that made the change, and only commit `env.lock` when `local_rev` is `null`. If `push` reports no changes but `local_rev` is still set, set `rev` to the `local_rev` value and `local_rev` to `null`.
- **"This environment is not yet compatible with your system (aarch64-linux)"**: the whole repo is mounted at `/workspaces/devcontainers`, so flox's auto-activation can find the macOS-only root `.flox`. Answer **deny** when the container asks to auto-activate `/workspaces/devcontainers`, or set it to `"deny"` under `[auto_activate_environments]` in `~/.config/flox/flox.toml` inside the container.
- **Changes to `jbayer/default` don't show up in the container**: the cached copy stays pinned. Run `flox pull -r jbayer/default` inside the container.

## Building the image

```sh
docker buildx build -t jbayer/devcontainer-flox:1.17.0 -t jbayer/devcontainer-flox:latest docker/
docker push --all-tags jbayer/devcontainer-flox
```

Then update the image tag/digest in `example/.devcontainer/devcontainer.json` and rebuild the container (**Dev Containers: Rebuild Container**). Volumes keep their contents across image updates. For a clean slate, run `docker volume rm devcontainer-nix-store-multiuser <folder>-flox-home`. If you're upgrading from an old single-user setup, also remove the old `devcontainer-nix-store` volume.
