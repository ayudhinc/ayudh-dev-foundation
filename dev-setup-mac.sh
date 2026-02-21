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
#   ./dev-setup-mac.sh --docker=colima
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

choose_one() {
  local prompt="$1"
  shift
  local options=("$@")
  local i=1
  echo "$prompt"
  for opt in "${options[@]}"; do
    echo "  $i) $opt"
    i=$((i+1))
  done
  local choice=""
  while true; do
    read -r -p "Select [1-${#options[@]}] (or press Enter to skip): " choice
    if [[ -z "${choice:-}" ]]; then
      echo ""
      return 1
    fi
    if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice>=1 && choice<=${#options[@]} )); then
      echo "${options[choice-1]}"
      return 0
    fi
    echo "Invalid choice."
  done
}

append_if_missing() {
  local line="$1"
  local file="$2"
  touch "$file"
  grep -Fqs "$line" "$file" || echo "$line" >> "$file"
}

is_apple_silicon() { [[ "$(uname -m)" == "arm64" ]]; }

brew_shellenv_eval() {
  if is_apple_silicon; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
  else
    eval "$(/usr/local/bin/brew shellenv)"
  fi
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

log "Interactive macOS frontend + backend dev setup"

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
if need_cmd brew; then
  log "Homebrew already installed."
  brew_shellenv_eval || true
else
  warn "Homebrew not found."
  if confirm "Install Homebrew?"; then
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    if is_apple_silicon; then
      append_if_missing 'eval "$(/opt/homebrew/bin/brew shellenv)"' "$HOME/.zprofile"
    else
      append_if_missing 'eval "$(/usr/local/bin/brew shellenv)"' "$HOME/.zprofile"
    fi
    brew_shellenv_eval
  else
    warn "Skipping Homebrew. Most steps require it."
  fi
fi

if need_cmd brew; then
  if confirm "Run 'brew update'?"; then
    brew update
  else
    warn "Skipping brew update."
  fi
fi

# ---------- step: core packages ----------
log "Step: Core CLI packages (git, jq, ripgrep, fd, fzf, direnv, etc.)"
if need_cmd brew; then
  if confirm "Install core CLI packages via Homebrew?"; then
    brew install \
      git curl wget jq openssl readline sqlite \
      gnu-sed coreutils ca-certificates \
      ripgrep fd fzf tmux tree watch htop \
      direnv shellcheck
    # Optional fzf completion/keybinds
    if [[ -f "$(brew --prefix)/opt/fzf/install" ]]; then
      if confirm "Enable fzf key bindings + shell completion?"; then
        "$(brew --prefix)/opt/fzf/install" --key-bindings --completion --no-update-rc >/dev/null 2>&1 || true
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
  warn "git not found; skipping git config."
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
  if ! need_cmd brew; then
    warn "Homebrew missing; will still try nvm installer directly."
  fi

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
  if need_cmd brew; then
    brew install pyenv xz
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
      if pyenv versions --bare | grep -q "^${PY_VER}$"; then
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
if need_cmd brew; then
  if confirm "Install Postgres 16 + Redis via Homebrew?"; then
    brew install postgresql@16 redis

    if confirm "Start Postgres + Redis now using brew services (runs in background)?"; then
      brew services start postgresql@16 || true
      brew services start redis || true
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
log "Step: Docker runtime (choose one)"

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
    # prompt user choice
    if choice="$(choose_one "Pick a Docker runtime to install:" "Docker Desktop" "Colima (headless, lightweight)" "OrbStack (alternative app) ")" ; then
      case "$choice" in
        "Docker Desktop") DOCKER_MODE="desktop" ;;
        "Colima (headless, lightweight)") DOCKER_MODE="colima" ;;
        "OrbStack (alternative app)") DOCKER_MODE="orbstack" ;;
      esac
    else
      DOCKER_MODE="skip"
      warn "Docker runtime not selected; skipping."
    fi
  fi

  if [[ "${DOCKER_MODE}" == "desktop" ]]; then
    if need_cmd brew; then
      if confirm "Install Docker Desktop (cask: docker-desktop)?"; then
        brew install --cask docker-desktop
        warn "After install: open Docker Desktop once to finish permissions/setup."
      else
        warn "Skipped Docker Desktop."
      fi
    else
      warn "Homebrew missing; cannot install Docker Desktop via brew."
    fi
  elif [[ "${DOCKER_MODE}" == "colima" ]]; then
    if need_cmd brew; then
      if confirm "Install Colima + Docker CLI (recommended lightweight setup)?"; then
        brew install colima docker docker-compose
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
    if need_cmd brew; then
      if confirm "Install OrbStack (cask)?"; then
        brew install --cask orbstack
        warn "After install: open OrbStack once to initialize."
      else
        warn "Skipped OrbStack."
      fi
    else
      warn "Homebrew missing; cannot install OrbStack."
    fi
  fi
fi

# ---------- step: VS Code ----------
log "Step: VS Code"
if need_cmd brew; then
  if confirm "Install Visual Studio Code (cask)?"; then
    brew install --cask visual-studio-code
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
