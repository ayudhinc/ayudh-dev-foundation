#!/usr/bin/env bash
set -euo pipefail

# ------------------------------------------------------------
# macOS Dev Setup (Interactive)
# - Asks before EACH install step; you can skip any step.
# - Docker option via flag: --docker=desktop|colima|orbstack|skip
# - Installs are mostly idempotent (skips if already present).
#
# Usage:
#   chmod +x dev-setup-mac.sh
#   ./dev-setup-mac.sh
#   ./dev-setup-mac.sh --docker=orbstack
# ------------------------------------------------------------

# ---------- styling ----------
GREEN="\033[1;32m"
YELLOW="\033[1;33m"
RED="\033[1;31m"
RESET="\033[0m"

log()  { printf "\n${GREEN}==> %s${RESET}\n" "$*"; }
warn() { printf "\n${YELLOW}!! %s${RESET}\n" "$*"; }
err()  { printf "\n${RED}ERROR: %s${RESET}\n" "$*"; }

need_cmd() { command -v "$1" >/dev/null 2>&1; }

confirm() {
  local prompt="$1"
  local ans=""
  read -r -p "$prompt [y/N]: " ans
  [[ "${ans:-}" =~ ^[Yy]$ ]]
}

append_if_missing() {
  local line="$1"
  local file="$2"
  touch "$file"
  grep -Fqs "$line" "$file" || echo "$line" >> "$file"
}

is_apple_silicon() { [[ "$(uname -m)" == "arm64" ]]; }

# ---------- Homebrew bootstrap (robust) ----------
# Why this exists:
# - On a fresh Mac, brew may be installed but NOT on PATH for non-login shells.
# - Using `command -v brew` can incorrectly report "missing".
# This block finds brew in standard locations and fixes PATH for this script process.
BREW_BIN=""

detect_brew() {
  if command -v brew >/dev/null 2>&1; then
    BREW_BIN="$(command -v brew)"
    return 0
  fi
  if [[ -x "/opt/homebrew/bin/brew" ]]; then
    BREW_BIN="/opt/homebrew/bin/brew"
    return 0
  fi
  if [[ -x "/usr/local/bin/brew" ]]; then
    BREW_BIN="/usr/local/bin/brew"
    return 0
  fi
  return 1
}

have_brew() { [[ -n "${BREW_BIN:-}" && -x "${BREW_BIN:-}" ]]; }

brew_eval_shellenv() {
  # shellcheck disable=SC2046
  eval "$("${BREW_BIN}" shellenv)"
}

brew_cmd() {
  "${BREW_BIN}" "$@"
}

brew_has_cask() {
  have_brew || return 1
  brew_cmd list --cask 2>/dev/null | grep -qx "$1"
}

# ---------- args ----------
DOCKER_MODE="" # desktop|colima|orbstack|skip|"" (prompt)
for arg in "$@"; do
  case "$arg" in
    --docker=*) DOCKER_MODE="${arg#*=}" ;;
    --help|-h)
      cat <<EOF
Usage: $0 [--docker=desktop|colima|orbstack|skip]

This script interactively installs dev tooling. It prompts before each step.
EOF
      exit 0
      ;;
    *)
      err "Unknown arg: $arg"
      exit 1
      ;;
  esac
done

# ---------- preflight ----------
if [[ "$(uname)" != "Darwin" ]]; then
  err "This script is for macOS only."
  exit 1
fi

# IMPORTANT: Detect brew early (if present) and fix PATH for THIS script run.
if detect_brew; then
  brew_eval_shellenv
fi

log "Interactive macOS frontend + backend dev setup"

# Guardrail: running entire script with sudo breaks PATH/home assumptions.
if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
  warn "You are running this script as root (sudo). This can hide Homebrew and confuse installs."
  warn "Recommended: run as your normal user (no sudo), and only enter sudo when prompted."
fi

# ---------- step: Xcode CLT ----------
log "Step: Xcode Command Line Tools"
if xcode-select -p >/dev/null 2>&1; then
  log "Xcode Command Line Tools already installed."
else
  warn "Xcode Command Line Tools not found."
  if confirm "Install Xcode Command Line Tools now?"; then
    xcode-select --install || true
    warn "A dialog may appear. Complete install, then re-run this script if needed."
  else
    warn "Skipping Xcode Command Line Tools. Some installs may fail without it."
  fi
fi

# ---------- step: Homebrew ----------
log "Step: Homebrew"
if have_brew; then
  log "Homebrew already installed at: ${BREW_BIN}"
else
  warn "Homebrew not found."
  if confirm "Install Homebrew?"; then
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    # Re-detect and init PATH
    if ! detect_brew; then
      err "Homebrew install completed but brew not found in expected locations."
      exit 1
    fi
    brew_eval_shellenv

    # Persist PATH for future terminals
    if is_apple_silicon; then
      append_if_missing 'eval "$(/opt/homebrew/bin/brew shellenv)"' "$HOME/.zprofile"
    else
      append_if_missing 'eval "$(/usr/local/bin/brew shellenv)"' "$HOME/.zprofile"
    fi
  else
    warn "Skipping Homebrew. Most steps require it."
  fi
fi

# Refresh PATH once more (covers cases where brew was installed mid-run)
if have_brew; then
  brew_eval_shellenv
  if confirm "Run 'brew update'?"; then
    brew_cmd update
  else
    warn "Skipping brew update."
  fi
fi

# ---------- step: core packages ----------
log "Step: Core CLI packages (git, jq, ripgrep, fd, fzf, direnv, etc.)"
if have_brew; then
  if confirm "Install core CLI packages via Homebrew?"; then
    brew_cmd install \
      git curl wget jq openssl readline sqlite \
      gnu-sed coreutils ca-certificates \
      ripgrep fd fzf tmux tree watch htop \
      direnv shellcheck

    # Optional fzf completion/keybinds
    if [[ -f "$(brew_cmd --prefix)/opt/fzf/install" ]]; then
      if confirm "Enable fzf key bindings + shell completion?"; then
        "$(brew_cmd --prefix)/opt/fzf/install" --key-bindings --completion --no-update-rc >/dev/null 2>&1 || true
      fi
    fi
  else
    warn "Skipping core CLI packages."
  fi
else
  warn "Homebrew missing; skipping core packages."
fi

# ---------- step: Git config ----------
log "Step: Git configuration"
# Ensure PATH includes brew bins for this script; if brew exists but PATH was missing earlier, git may now be found.
if need_cmd git; then
  if confirm "Set global git defaults (main branch, pull behavior, autocrlf)?"; then
    git config --global init.defaultBranch main
    git config --global pull.rebase false
    git config --global core.autocrlf input
  fi
  if confirm "Set global git user.name and user.email now?"; then
    read -r -p "Git user.name: " GIT_NAME
    read -r -p "Git user.email: " GIT_EMAIL
    git config --global user.name "$GIT_NAME"
    git config --global user.email "$GIT_EMAIL"
  fi
else
  warn "git not found on PATH; skipping git config."
  warn "If you installed git via brew above, open a NEW terminal or re-run this script."
fi

# ---------- step: SSH key ----------
log "Step: SSH key (GitHub/GitLab)"
if confirm "Generate an SSH key (ed25519) for Git hosting?"; then
  read -r -p "Email label for SSH key: " SSH_EMAIL
  KEY_PATH="$HOME/.ssh/id_ed25519"
  if [[ -f "$KEY_PATH" ]]; then
    warn "SSH key already exists at $KEY_PATH (skipping)."
  else
    mkdir -p "$HOME/.ssh"
    ssh-keygen -t ed25519 -C "$SSH_EMAIL" -f "$KEY_PATH"
    eval "$(ssh-agent -s)" >/dev/null 2>&1 || true
    ssh-add "$KEY_PATH" >/dev/null 2>&1 || true
    log "Public key (add to GitHub/GitLab):"
    cat "${KEY_PATH}.pub"
  fi
else
  warn "Skipping SSH key generation."
fi

# ---------- step: Node via nvm ----------
log "Step: Node.js via nvm"
if confirm "Install nvm + Node LTS + Corepack (pnpm/yarn)?"; then
  # Install nvm if missing
  if [[ ! -d "$HOME/.nvm" ]]; then
    curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash
  else
    log "nvm directory already exists."
  fi

  # Load nvm for this script session
  export NVM_DIR="$HOME/.nvm"
  # shellcheck disable=SC1091
  [[ -s "$NVM_DIR/nvm.sh" ]] && . "$NVM_DIR/nvm.sh"

  if need_cmd nvm; then
    nvm install --lts
    nvm alias default 'lts/*'
    log "Node: $(node -v) | npm: $(npm -v)"

    if confirm "Enable Corepack (recommended) and activate pnpm/yarn?"; then
      corepack enable || true
      corepack prepare pnpm@latest --activate || npm i -g pnpm
      corepack prepare yarn@stable --activate || npm i -g yarn
      log "pnpm: $(pnpm -v 2>/dev/null || echo 'not found') | yarn: $(yarn -v 2>/dev/null || echo 'not found')"
    else
      warn "Skipping Corepack/pnpm/yarn activation."
    fi
  else
    warn "nvm didn't load in this session. Open a new terminal and run: nvm install --lts"
  fi
else
  warn "Skipping Node/nvm setup."
fi

# ---------- step: Python via pyenv + Poetry ----------
log "Step: Python via pyenv + Poetry"
if confirm "Install pyenv + Python 3.12 + Poetry (project .venv)?"; then
  if have_brew; then
    brew_cmd install pyenv xz
  else
    warn "Homebrew missing; skipping pyenv install."
  fi

  # Add pyenv init (safe, idempotent)
  append_if_missing 'export PYENV_ROOT="$HOME/.pyenv"' "$HOME/.zprofile"
  append_if_missing 'command -v pyenv >/dev/null || export PATH="$PYENV_ROOT/bin:$PATH"' "$HOME/.zprofile"
  append_if_missing 'eval "$(pyenv init -)"' "$HOME/.zprofile"

  export PYENV_ROOT="$HOME/.pyenv"
  export PATH="$PYENV_ROOT/bin:$PATH"

  if need_cmd pyenv; then
    eval "$(pyenv init -)" || true
    PY_VER="3.12.8"

    if confirm "Install Python ${PY_VER} via pyenv (can take time)?"; then
      if pyenv versions --bare | grep -qx "${PY_VER}"; then
        log "Python ${PY_VER} already installed in pyenv."
      else
        pyenv install "${PY_VER}"
      fi
      pyenv global "${PY_VER}"
      log "Python: $(python -V)"
      python -m pip install --upgrade pip setuptools wheel
    else
      warn "Skipping Python install via pyenv."
    fi

    if confirm "Install Poetry?"; then
      if need_cmd poetry; then
        log "Poetry already installed: $(poetry --version)"
      else
        curl -fsSL https://install.python-poetry.org | python3 -
        append_if_missing 'export PATH="$HOME/.local/bin:$PATH"' "$HOME/.zprofile"
        export PATH="$HOME/.local/bin:$PATH"
      fi

      if need_cmd poetry; then
        poetry config virtualenvs.in-project true
        log "Poetry: $(poetry --version)"
        log "Configured: Poetry venvs in-project (.venv)"
      else
        warn "Poetry not found after install (open a new terminal)."
      fi
    else
      warn "Skipping Poetry."
    fi
  else
    warn "pyenv not found in this session. Open a new terminal and try again."
  fi
else
  warn "Skipping Python/Poetry setup."
fi

# ---------- step: Databases (brew) ----------
log "Step: Postgres + Redis (Brew services)"
if have_brew; then
  if confirm "Install Postgres 16 + Redis via Homebrew?"; then
    brew_cmd install postgresql@16 redis

    if confirm "Start Postgres + Redis now using brew services (runs in background)?"; then
      brew_cmd services start postgresql@16 || true
      brew_cmd services start redis || true
      log "Started Postgres + Redis (brew services)."
    else
      warn "Skipping starting services. You can start later with:"
      echo "  brew services start postgresql@16"
      echo "  brew services start redis"
    fi
  else
    warn "Skipping Postgres/Redis."
  fi
else
  warn "Homebrew missing; skipping Postgres/Redis."
fi

# ---------- step: Docker runtime selection ----------
log "Step: Docker runtime"

# Validate flag if provided
if [[ -n "${DOCKER_MODE:-}" ]]; then
  case "$DOCKER_MODE" in
    desktop|colima|orbstack|skip) ;;
    *)
      err "--docker must be one of: desktop|colima|orbstack|skip"
      exit 1
      ;;
  esac
fi

if [[ "${DOCKER_MODE:-}" == "skip" ]]; then
  warn "Docker step skipped due to --docker=skip."
else
  if [[ -z "${DOCKER_MODE:-}" ]]; then
    echo ""
    echo "Pick a Docker runtime to install:"
    echo "  1) Docker Desktop  (most compatible / common default)"
    echo "  2) Colima          (lightweight, CLI-only runtime)"
    echo "  3) OrbStack        (fast Docker Desktop alternative)"
    echo "  Enter) Skip Docker"
    echo ""
    read -r -p "Select [1-3] (or press Enter to skip): " choice
    case "${choice:-}" in
      1) DOCKER_MODE="desktop" ;;
      2) DOCKER_MODE="colima" ;;
      3) DOCKER_MODE="orbstack" ;;
      "") DOCKER_MODE="skip" ;;
      *) warn "Invalid choice; skipping Docker."; DOCKER_MODE="skip" ;;
    esac
  fi

  if [[ "${DOCKER_MODE}" == "desktop" ]]; then
    if have_brew; then
      if confirm "Install Docker Desktop (cask: docker-desktop)?"; then
        if brew_has_cask docker-desktop; then
          log "Docker Desktop already installed."
        else
          brew_cmd install --cask docker-desktop
        fi
        warn "After install: open Docker Desktop once to finish permissions/setup."
      else
        warn "Skipped Docker Desktop."
      fi
    else
      warn "Homebrew missing; cannot install Docker Desktop via brew."
    fi
  elif [[ "${DOCKER_MODE}" == "colima" ]]; then
    if have_brew; then
      if confirm "Install Colima + Docker CLI + docker-compose (lightweight setup)?"; then
        brew_cmd install colima docker docker-compose
        if confirm "Start Colima now? (colima start)"; then
          colima start
          log "Colima started. Docker should work now."
        else
          warn "You can start later: colima start"
        fi
      else
        warn "Skipped Colima."
      fi
    else
      warn "Homebrew missing; cannot install Colima."
    fi
  elif [[ "${DOCKER_MODE}" == "orbstack" ]]; then
    if have_brew; then
      if confirm "Install OrbStack (cask: orbstack)?"; then
        if brew_has_cask orbstack; then
          log "OrbStack already installed."
        else
          brew_cmd install --cask orbstack
        fi
        # Verify .app presence (brew can install into /Applications)
        if [[ -d "/Applications/OrbStack.app" ]] || [[ -d "$HOME/Applications/OrbStack.app" ]]; then
          log "OrbStack app detected."
        else
          warn "OrbStack installed via brew, but OrbStack.app not found in /Applications. If needed: brew reinstall --cask orbstack"
        fi
        warn "After install: open OrbStack once to initialize (then: docker version)."
      else
        warn "Skipped OrbStack."
      fi
    else
      warn "Homebrew missing; cannot install OrbStack."
    fi
  fi

  # Non-fatal quick check
  echo ""
  log "Docker quick check (non-fatal)"
  if need_cmd docker; then
    docker version >/dev/null 2>&1 && log "docker CLI works (docker version succeeded)" || warn "docker CLI present but runtime not initialized yet (open OrbStack/Desktop or start Colima)"
  else
    warn "docker command not found yet. This is normal until you install Desktop/Colima or OrbStack provides it."
  fi
fi

# ---------- step: VS Code ----------
log "Step: VS Code"
if have_brew; then
  if confirm "Install Visual Studio Code (cask)?"; then
    if brew_has_cask visual-studio-code; then
      log "VS Code already installed."
    else
      brew_cmd install --cask visual-studio-code
    fi
    warn "To enable 'code' command: VS Code → Cmd+Shift+P → Install 'code' command in PATH"
  else
    warn "Skipping VS Code."
  fi
else
  warn "Homebrew missing; skipping VS Code."
fi

# ---------- step: Oh My Zsh ----------
log "Step: Oh My Zsh (shell UX)"
if confirm "Install Oh My Zsh? (optional)"; then
  if [[ -d "$HOME/.oh-my-zsh" ]]; then
    warn "Oh My Zsh already installed; skipping."
  else
    sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
    warn "Oh My Zsh installed. Customize ~/.zshrc as needed."
  fi
else
  warn "Skipping Oh My Zsh."
fi

# ---------- step: Workspace folders ----------
log "Step: Workspace folders"
if confirm "Create ~/dev/{frontend,backend,scripts} folders?"; then
  mkdir -p "$HOME/dev/frontend" "$HOME/dev/backend" "$HOME/dev/scripts"
  log "Created: $HOME/dev/{frontend,backend,scripts}"
else
  warn "Skipping workspace folders."
fi

# ---------- finish ----------
log "All done ✅"
warn "Open a NEW terminal so any ~/.zprofile changes take effect."
echo ""
echo "Suggested quick checks:"
echo "  node -v && npm -v"
echo "  pnpm -v  (if enabled)"
echo "  python -V"
echo "  poetry --version"
echo "  docker version  (if installed)"
echo "  psql --version  (if installed)"
echo "  redis-cli ping  (if installed)"
