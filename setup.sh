#!/bin/bash
#==============================================================================
# setup.sh — one-command, do-everything installer for chati
#==============================================================================
# Run this ONCE after cloning the repo. It brings a fresh Mac from
# "just cloned" to a FULLY WORKING system — CLI chat, the OpenWebUI browser
# app, AND local web search (SearXNG) — and is safe to re-run any time.
#
# Design goals (why this file exists):
#   * DO EVERYTHING by default — one command, no follow-up steps to remember.
#   * PATH-INDEPENDENT — resolved relative to this script; works from any dir.
#   * IDEMPOTENT — each step checks before acting; re-running is safe.
#   * FAIL-LOUD, FAIL-CLEAR — prerequisites checked with actionable messages.
#   * NEVER HANG — a slow OpenWebUI first boot is tolerated, not fatal.
#   * REVERSIBLE — `--remove-all` tears the whole install back down.
#
# It does NOT clone the repo or run `gh auth login` — those must happen first
# (you need the code before you can run this). See README "Quick Start".
#==============================================================================
set -euo pipefail

# ---- Configuration -----------------------------------------------------------
# The repo root is wherever THIS script lives — never assume ~/chat.
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BREWFILE="$REPO_ROOT/installer/Brewfile"

# The chat model the installer pulls by default. Override with --model NAME.
DEFAULT_CHAT_MODEL="gemma4:26b"
SEARXNG_LOCAL_URL="http://127.0.0.1:8890"

# Install everything by default; flags only subtract or tweak.
WANT_WEBUI=1
WANT_SEARXNG=1
WANT_PULL=1
REMOVE_ALL=0
ASSUME_YES=0
CHAT_MODEL="$DEFAULT_CHAT_MODEL"

# ---- Pretty output helpers ---------------------------------------------------
step() { printf '\n\033[1;36m==> %s\033[0m\n' "$1"; }
ok()   { printf '   \033[32m✅ %s\033[0m\n' "$1"; }
warn() { printf '   \033[33m⚠️  %s\033[0m\n' "$1"; }
die()  { printf '\n\033[31m❌ %s\033[0m\n' "$1" >&2; exit 1; }

usage() {
    cat <<'USAGE'
setup.sh — one-command, do-everything installer for chati

By default it installs EVERYTHING: Homebrew deps, Ollama + a chat model,
the OpenWebUI browser app, and a local SearXNG for /web — all started.

  ./setup.sh                brew deps + Ollama + model + OpenWebUI + SearXNG
  ./setup.sh --minimal      CLI only — skip OpenWebUI and SearXNG
  ./setup.sh --no-webui     skip OpenWebUI only
  ./setup.sh --no-searxng   skip SearXNG only
  ./setup.sh --model NAME    use a different chat model (default: gemma4:26b)
  ./setup.sh --no-pull       do not pull a model (assume one already exists)
  ./setup.sh --remove-all    UNINSTALL everything this script set up (asks first)
  ./setup.sh --remove-all --yes   same, without the confirmation prompt
  ./setup.sh --help          show this help

--remove-all keeps Homebrew and its packages (shared with other tools); it
removes OpenWebUI, SearXNG, the `chati` PATH link, logs, pulled Ollama
models, and this repo's local state (.env, sessions, active-model file).
USAGE
    exit 0
}

# ---- Argument parsing --------------------------------------------------------
while [[ $# -gt 0 ]]; do
    case "$1" in
        --minimal)   WANT_WEBUI=0; WANT_SEARXNG=0 ;;
        --no-webui)  WANT_WEBUI=0 ;;
        --no-searxng) WANT_SEARXNG=0 ;;
        --webui)     WANT_WEBUI=1 ;;     # accepted for compatibility (now default)
        --searxng)   WANT_SEARXNG=1 ;;   # accepted for compatibility (now default)
        --no-pull)   WANT_PULL=0 ;;
        --model)     CHAT_MODEL="${2:?--model needs a model name}"; shift ;;
        --remove-all) REMOVE_ALL=1 ;;
        --yes|-y)    ASSUME_YES=1 ;;
        -v|--version) echo "chati $(cat "$REPO_ROOT/VERSION" 2>/dev/null || echo unknown)"; exit 0 ;;
        -h|--help)   usage ;;
        *)           die "Unknown option: $1 (try --help)" ;;
    esac
    shift
done

# ---- Uninstall path (--remove-all) ------------------------------------------
# Tears down everything setup.sh creates, so an install can be tested and
# then cleanly removed. Deliberately does NOT touch Homebrew or its packages
# (jq, curl, ollama, …) — those are shared with the rest of your system and
# removing them is out of scope for this project's installer.
remove_all() {
    # Make brew visible so `brew --prefix` works (for the chati symlink path).
    if [[ -x /opt/homebrew/bin/brew ]]; then eval "$(/opt/homebrew/bin/brew shellenv)"
    elif [[ -x /usr/local/bin/brew ]]; then eval "$(/usr/local/bin/brew shellenv)"; fi
    local brew_bin=""; command -v brew >/dev/null 2>&1 && brew_bin="$(brew --prefix)/bin"

    local models=""
    command -v ollama >/dev/null 2>&1 && models="$(ollama list 2>/dev/null | tail -n +2 | awk '{print $1}')"

    echo "🧹 --remove-all will DELETE the following (Homebrew & its packages are kept):"
    echo "     • OpenWebUI:        ~/openwebui"
    echo "     • Local SearXNG:    ~/searxng"
    echo "     • Logs:             ~/logs"
    echo "     • PATH links:       ${brew_bin:-<brew bin>}/{chati,ailocal}"
    echo "     • Repo state:       .env, .active_ollama_model.txt, .web_cache,"
    echo "                         conversation_histories/, ola_chat/instances/"
    echo "     • Ollama models:    all pulled models${models:+ ($(printf '%s' "$models" | paste -sd, -))}"
    echo "   (The repo code and Homebrew packages are NOT removed.)"

    if [[ "$ASSUME_YES" -ne 1 ]]; then
        printf '\nProceed? [y/N] '
        local reply; read -r reply
        [[ "$reply" == [yY] || "$reply" == [yY][eE][sS] ]] || die "Aborted — nothing removed."
    fi

    # Remove models FIRST, while Ollama can still answer: `ollama rm` talks to
    # the running server, so stopping services before this would make every
    # removal silently fail. Start the server if it isn't up.
    step "Removing Ollama models"
    if command -v ollama >/dev/null 2>&1; then
        if ! curl -fsS --max-time 2 http://localhost:11434/api/tags >/dev/null 2>&1; then
            nohup ollama serve >/dev/null 2>&1 &
            for _ in {1..10}; do
                curl -fsS --max-time 2 http://localhost:11434/api/tags >/dev/null 2>&1 && break
                sleep 1
            done
        fi
        local to_rm; to_rm="$(ollama list 2>/dev/null | tail -n +2 | awk '{print $1}')"
        if [[ -n "$to_rm" ]]; then
            printf '%s\n' "$to_rm" | while read -r m; do [[ -n "$m" ]] && ollama rm "$m" >/dev/null 2>&1 || true; done
            ok "Models removed ($(printf '%s' "$to_rm" | paste -sd, -))"
        else
            ok "No models to remove"
        fi
    else
        ok "Ollama not installed — no models to remove"
    fi

    step "Stopping services"
    [[ -x "$REPO_ROOT/ai_local/ailocal" ]] && "$REPO_ROOT/ai_local/ailocal" stop >/dev/null 2>&1 || true
    pkill -f 'granian.*searx\.webapp' >/dev/null 2>&1 || true
    ok "Services stopped"

    step "Removing the 'chati' and 'ailocal' PATH links"
    if [[ -n "$brew_bin" ]]; then
        [[ -L "$brew_bin/chati" ]] && rm -f "$brew_bin/chati"
        [[ -L "$brew_bin/ailocal" ]] && rm -f "$brew_bin/ailocal"
    fi
    ok "Links removed"

    step "Removing installed apps and state"
    rm -rf "$HOME/openwebui" "$HOME/searxng" "$HOME/logs"
    rm -rf "$REPO_ROOT/.env" "$REPO_ROOT/.active_ollama_model.txt" \
           "$REPO_ROOT/.web_cache" "$REPO_ROOT/ola_chat/instances"
    rm -rf "$REPO_ROOT/conversation_histories"/* 2>/dev/null || true
    ok "Apps and local state removed"

    printf '\n\033[1;32m✅ Removed. Homebrew and its packages were left intact.\033[0m\n'
    echo "Re-install anytime with: ./setup.sh"
    exit 0
}

if [[ "$REMOVE_ALL" -eq 1 ]]; then remove_all; fi

echo "🚀 chati setup — repo at: $REPO_ROOT"

# ---- 1. Platform check -------------------------------------------------------
step "Checking platform"
[[ "$OSTYPE" == darwin* ]] || die "This installer targets macOS. Detected: $OSTYPE"
ok "macOS detected"

# ---- 2. Homebrew -------------------------------------------------------------
step "Ensuring Homebrew is installed"
if ! command -v brew >/dev/null 2>&1; then
    warn "Homebrew not found — installing (you may be prompted for your password)…"
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
fi
# Make brew usable in THIS shell whether it's Apple-silicon or Intel.
if [[ -x /opt/homebrew/bin/brew ]]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
elif [[ -x /usr/local/bin/brew ]]; then
    eval "$(/usr/local/bin/brew shellenv)"
fi
command -v brew >/dev/null 2>&1 || die "Homebrew still not on PATH. Open a new terminal and re-run ./setup.sh"
ok "Homebrew ready ($(brew --version | head -1))"

# ---- 3. Homebrew packages ----------------------------------------------------
# Single source of truth = installer/Brewfile. No second package list to drift.
step "Installing Homebrew packages (from installer/Brewfile)"
[[ -f "$BREWFILE" ]] || die "Brewfile missing at $BREWFILE — is the checkout complete?"
brew bundle --file="$BREWFILE"
ok "Packages installed / up to date"

# ---- 4. Directories ----------------------------------------------------------
step "Creating local directories"
mkdir -p "$HOME/logs" "$REPO_ROOT/conversation_histories"
ok "logs/ and conversation_histories/ ready"

# ---- 5. Executable permissions ----------------------------------------------
# Only the real entry points — a stale name here would abort under set -e.
step "Setting executable permissions"
chmod +x "$REPO_ROOT/chati" \
         "$REPO_ROOT/ai_local/ailocal" \
         "$REPO_ROOT/docr/docr" \
         "$REPO_ROOT/ola_chat/ola" "$REPO_ROOT/ola_chat/mola" "$REPO_ROOT/ola_chat/ola_model" \
         "$REPO_ROOT/tests/run_tests.sh" \
         "$REPO_ROOT/installer/install_searxng.sh" 2>/dev/null || true
ok "Scripts are executable"

# ---- 5b. Make `chati` and `ailocal` runnable from anywhere ------------------
# Symlink both into Homebrew's bin (already on PATH and user-writable). chati
# resolves symlinks to locate its repo; ailocal uses $HOME-based paths and
# doesn't care where it's invoked from — so both work from any directory.
step "Linking 'chati' and 'ailocal' onto your PATH"
BREW_BIN="$(brew --prefix)/bin"
if ln -sf "$REPO_ROOT/chati" "$BREW_BIN/chati" 2>/dev/null \
   && ln -sf "$REPO_ROOT/ai_local/ailocal" "$BREW_BIN/ailocal" 2>/dev/null; then
    ok "You can now run 'chati' and 'ailocal' from anywhere"
else
    warn "Couldn't link into $BREW_BIN — run them as ./chati and ./ai_local/ailocal, or add the repo to your PATH."
fi

# ---- 6. Start Ollama ---------------------------------------------------------
# A model pull (and chati itself) needs the server up. Start it in the
# background and wait until the API answers, so nothing downstream fails with
# "could not connect to ollama server".
step "Starting Ollama service"
ollama_up() { curl -fsS --max-time 2 http://localhost:11434/api/tags >/dev/null 2>&1; }
if ollama_up; then
    ok "Ollama already running"
else
    # Apple Silicon perf tuning (Homebrew ollama formula's recommended flags):
    # flash attention + q8 KV cache. GPU/MLX acceleration is automatic.
    export OLLAMA_FLASH_ATTENTION="${OLLAMA_FLASH_ATTENTION:-1}"
    export OLLAMA_KV_CACHE_TYPE="${OLLAMA_KV_CACHE_TYPE:-q8_0}"
    nohup ollama serve >"$HOME/logs/ollama.log" 2>&1 &
    for _ in {1..15}; do ollama_up && break; sleep 1; done
    ollama_up && ok "Ollama is ready" || die "Ollama didn't come up. Check ~/logs/ollama.log"
fi

# ---- 7. Ensure a chat model --------------------------------------------------
step "Ensuring a chat model is available"
installed_models() { ollama list 2>/dev/null | tail -n +2 | awk '{print $1}'; }
have_any_model() { [[ -n "$(installed_models)" ]]; }

if [[ "$WANT_PULL" -eq 0 ]]; then
    have_any_model \
        && ok "Using existing model(s): $(installed_models | paste -sd, -)" \
        || warn "--no-pull set but no model installed. Run: ollama pull $CHAT_MODEL"
else
    if installed_models | grep -qxF "$CHAT_MODEL"; then
        ok "Model '$CHAT_MODEL' already present"
    else
        warn "Pulling '$CHAT_MODEL' (first download can take a few minutes)…"
        ollama pull "$CHAT_MODEL"
        ok "Pulled '$CHAT_MODEL'"
    fi
    # Point chati at a model we know exists (only if unset or stale).
    active_file="$REPO_ROOT/.active_ollama_model.txt"
    current="$(cat "$active_file" 2>/dev/null || true)"
    if ! installed_models | grep -qxF "$current"; then
        printf '%s\n' "$CHAT_MODEL" > "$active_file"
        ok "Set active model → $CHAT_MODEL"
    fi
fi

# ---- 8. SearXNG web search (default; skip with --no-searxng/--minimal) -------
# Installed BEFORE OpenWebUI on purpose: OpenWebUI reads its web-search config
# from the environment at boot, so SearXNG must already be present when the UI
# starts for its "search via SearXNG" toggle to come up enabled. Wires chati's
# /web too. NON-FATAL throughout — web search is a bonus, never fails setup.
SEARXNG_STARTED=0
if [[ "$WANT_SEARXNG" -eq 1 ]]; then
    step "Installing local SearXNG (powers /web)"
    if "$REPO_ROOT/installer/install_searxng.sh"; then
        ok "SearXNG installed"
        # Point /web at the local instance — but never clobber an endpoint the
        # user already configured (e.g. a cloud SearXNG in .env).
        env_file="$REPO_ROOT/.env"
        if [[ ! -f "$env_file" ]]; then
            [[ -f "$REPO_ROOT/.env.example" ]] && cp "$REPO_ROOT/.env.example" "$env_file" || touch "$env_file"
        fi
        if grep -qE '^[[:space:]]*(export[[:space:]]+)?SEARXNG_URLS?=' "$env_file"; then
            ok "SearXNG endpoint already set in .env (left as-is)"
        else
            printf '\nexport SEARXNG_URLS="%s"\n' "$SEARXNG_LOCAL_URL" >> "$env_file"
            ok "Wired /web to $SEARXNG_LOCAL_URL in .env"
        fi
        step "Starting SearXNG"
        if "$REPO_ROOT/ai_local/ailocal" start searxng >/dev/null 2>&1 \
           && curl -fsS --max-time 5 "$SEARXNG_LOCAL_URL/healthz" >/dev/null 2>&1; then
            SEARXNG_STARTED=1
            ok "SearXNG running at $SEARXNG_LOCAL_URL — toggle it in chati with /web"
        else
            warn "SearXNG didn't confirm startup — check ~/logs/searxng.log, then: ./ai_local/ailocal start searxng"
        fi
    else
        warn "SearXNG install failed (see output above) — /web stays off. Chat and OpenWebUI are unaffected."
    fi
fi

# ---- 9. OpenWebUI (default; skip with --minimal) ----------------------------
# Install the venv, then start it (with SearXNG already up from step 8, so its
# web search comes up enabled). The start is NON-FATAL: OpenWebUI's first boot
# migrates its DB and can be slow, so a timeout must not abort setup.
WEBUI_STARTED=0
if [[ "$WANT_WEBUI" -eq 1 ]]; then
    step "Installing OpenWebUI (browser UI)"
    "$REPO_ROOT/ai_local/ailocal" upgrade webui --force
    ok "OpenWebUI installed"
    step "Starting OpenWebUI (first boot can take a minute)"
    if "$REPO_ROOT/ai_local/ailocal" start webui; then
        WEBUI_STARTED=1
        ok "OpenWebUI running at http://127.0.0.1:8888"
    else
        warn "OpenWebUI didn't confirm startup in time (it may still be booting)."
        warn "Check ~/logs/webui.log, or just run: ./ai_local/ailocal start webui"
    fi
fi

# ---- 10. Done ----------------------------------------------------------------
# Descriptions go BEFORE the command so every trailing token is a clean,
# copy-pasteable command (no trailing "# ..." to trip up zsh).
cat <<EOF

$(printf '\033[1;32m')✅ Setup complete!$(printf '\033[0m')
────────────────────────────────────────────
Start the CLI chat:      chati
EOF
if [[ "$WANT_WEBUI" -eq 1 ]]; then
    if [[ "$WEBUI_STARTED" -eq 1 ]]; then
        echo "Browser UI (running):    open http://127.0.0.1:8888"
    else
        echo "Browser UI (start it):   ailocal start webui"
    fi
fi
if [[ "$WANT_SEARXNG" -eq 1 && "$SEARXNG_STARTED" -eq 1 ]]; then
    echo "Web search (/web):       ready — toggle with /web inside chati"
fi
cat <<EOF
Service status:          ailocal status
Faster /web routing:     ollama pull llama3.2:3b
Uninstall everything:    ./setup.sh --remove-all
EOF
echo
