# mac-dev-bootstrap

Interactive bootstrap script to set up a modern macOS development machine for:
- Frontend (Node, pnpm/yarn)
- Backend (Python + Poetry)
- Local infra (Postgres/Redis via Homebrew)
- Containers (Docker runtime: OrbStack / Docker Desktop / Colima)
- Essentials (git, jq, ripgrep, fd, fzf, tmux, direnv, etc.)

Designed to be:
- **Interactive** (asks before each install step)
- **Idempotent-ish** (skips/handles many already-installed items)
- **Mac-friendly** (Apple Silicon aware; robust Homebrew detection)

---

## Quick start

```bash
git clone <your-repo-url>
cd mac-dev-bootstrap
chmod +x scripts/dev-setup-mac.sh
./scripts/dev-setup-mac.sh
```

> Tip: Run as your normal user (not with `sudo`).

---

## Docker runtime options

The script supports Docker runtime selection:

- **OrbStack** (fast Docker Desktop alternative)
- **Docker Desktop** (most standard “it just works”)
- **Colima** (lightweight, CLI-first)

### Force Docker mode via flag

```bash
./scripts/dev-setup-mac.sh --docker=orbstack
./scripts/dev-setup-mac.sh --docker=desktop
./scripts/dev-setup-mac.sh --docker=colima
./scripts/dev-setup-mac.sh --docker=skip
```

### After installing OrbStack / Docker Desktop

Open the app once to initialize:

```bash
open -a OrbStack
# or
open -a "Docker Desktop"
```

Verify Docker:

```bash
docker version
docker ps
```

---

## What it can install

### Core CLI
- git, curl, wget, jq
- ripgrep, fd, fzf, tmux, tree, watch, htop
- direnv, shellcheck

### Node (frontend)
- nvm
- Node LTS
- corepack + pnpm/yarn

### Python (backend)
- pyenv
- Python 3.12.x
- Poetry (+ in-project `.venv`)

### Databases
- postgresql@16
- redis

### Apps (optional)
- VS Code
- Oh My Zsh
- Docker runtime

---

## Common issues

### Don’t run with sudo
Running the script with `sudo` can hide Homebrew and user-installed tools due to PATH differences.

### PATH / brew issues
If brew isn't detected, open a new Terminal window (login shell).

Apple Silicon users should have:

```bash
eval "$(/opt/homebrew/bin/brew shellenv)"
```

in `~/.zprofile`.

---

## License

Choose a permissive license like MIT or Apache-2.0.
