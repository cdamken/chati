#!/bin/bash
#==============================================================================
# chati-common.sh — shared helpers for chati and its libexec/ subcommands.
#==============================================================================
# Sourceable with NO side effects: it only defines functions. Each subcommand
# script (libexec/chati-<sub>) sources this to reuse the same env/config/probe
# helpers, so a subcommand stays small and there is no monolith. The main chati
# REPL also sources it for the dispatcher.
#
# Expects CHATI_DIR to be set by the caller (the real repo dir). If it is not,
# we derive it from this file's own location.
#==============================================================================

if [[ -z "${CHATI_DIR:-}" ]]; then
    CHATI_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fi

# Words the REPL's own flag `case` still owns (bareword subcommands handled
# inline, e.g. `chati search`). The dispatcher runs BEFORE that case, so a
# libexec/chati-<word> with one of these names would silently steal the word.
# A reserved name never resolves to libexec; it stays with the case until the
# inline code is migrated out (then drop it from here — a bareword lives in ONE
# place). Space-separated so bash 3.2 can match it without an array.
CHATI_RESERVED_WORDS="${CHATI_RESERVED_WORDS:-search}"

# Git-style dispatch: given a subcommand name, echo the path of its executable
# libexec script if it exists, else nothing. A leading-dash arg (a flag), an
# empty name, or a reserved word (owned by the REPL case) never resolves. This
# is the single rule the dispatcher uses.
chati_resolve_subcommand() {
    local name="${1:-}" w
    [[ -n "$name" && "$name" != -* ]] || return 0
    for w in $CHATI_RESERVED_WORDS; do
        [[ "$name" == "$w" ]] && return 0
    done
    [[ -x "$CHATI_DIR/libexec/chati-$name" ]] \
        && printf '%s\n' "$CHATI_DIR/libexec/chati-$name"
}

# List the available subcommand names (from libexec/chati-*), one per line.
chati_list_subcommands() {
    local f n
    for f in "$CHATI_DIR"/libexec/chati-*; do
        [[ -x "$f" ]] || continue
        n="${f##*/chati-}"
        printf '%s\n' "$n"
    done
}

# Load the repo .env into the environment (for OLLAMA_API, SEARXNG_URLS, etc.).
# Safe no-op if there is no .env. Only call this from a subcommand process, not
# from a test that sources this file.
chati_load_env() {
    [[ -f "$CHATI_DIR/.env" ]] || return 0
    set -a
    # shellcheck disable=SC1091
    source "$CHATI_DIR/.env"
    set +a
}

# The configured Ollama base URL (default local).
chati_ollama_api() { printf '%s' "${OLLAMA_API:-http://localhost:11434}"; }

# Pass a start/stop/restart/status action through to ai_local/ailocal for one
# service target (webui|searxng|ollama). Powers the thin chati-<service>
# wrappers, so the start/stop logic stays in ailocal (not rewritten) behind the
# single `chati` front door. `exec`s ailocal on a valid action.
chati_service_cmd() {
    local target="$1"; shift
    local action="${1:-status}"; [[ $# -gt 0 ]] && shift
    local ail="$CHATI_DIR/ai_local/ailocal"
    [[ -x "$ail" ]] || { echo "ailocal no encontrado en $ail" >&2; return 3; }
    # Reject trailing args instead of dropping them (e.g. `chati webui start --port 9999`
    # must not silently start on the default port).
    if [[ $# -gt 0 && "$action" != -h && "$action" != --help ]]; then
        echo "uso: chati $target start|stop|restart|status (argumento extra: $1)" >&2; return 2
    fi
    case "$action" in
        start|stop|restart) exec "$ail" "$action" "$target" ;;
        status)             exec "$ail" status ;;
        -h|--help)          echo "uso: chati $target start|stop|restart|status"; return 0 ;;
        *) echo "uso: chati $target start|stop|restart|status" >&2; return 2 ;;
    esac
}

# --- Local service lifecycle (powers `chati status` and `chati stop`) ---------
# chati keeps the local AI services simple: Ollama starts on demand when you
# launch chati, SearXNG starts on demand when you use /web, and OpenWebUI is the
# one you start explicitly (`chati webui`). There is NO manual start/restart for
# Ollama or SearXNG by design. `chati stop` frees the machine; `chati status`
# shows what's up. These constants + two helpers are the shared core they build
# on (and fold the three near-identical stop loops ailocal carried into one).
# These constants are consumed by the libexec service scripts that source this
# file (chati status / chati stop), so shellcheck can't see the use here.
CHATI_LOG_DIR="${CHATI_LOG_DIR:-$HOME/logs}"
# Match "ollama serve" only at a word boundary, so "myollama serve" isn't hit.
# shellcheck disable=SC2034  # used by libexec/chati-status and chati-stop
CHATI_OLLAMA_PROC='(^|[/ ])ollama serve'
# Match OpenWebUI by its FULL venv binary path (not the bare "open-webui serve"
# substring), so pkill -f can't hit an unrelated process whose args contain it.
CHATI_WEBUI_VENV="${OPENWEBUI_VENV:-$HOME/openwebui/.venv}"
# shellcheck disable=SC2034  # used by libexec/chati-status and chati-stop
CHATI_WEBUI_PROC="$CHATI_WEBUI_VENV/bin/open-webui serve"
# shellcheck disable=SC2034  # used by libexec/chati-status and chati-stop
CHATI_SEARXNG_PROC='granian.*searx\.webapp'

# --- SearXNG local instance paths (optional 2nd web-search endpoint) ---
CHATI_SEARXNG_DIR="${SEARXNG_DIR:-$HOME/searxng}"
CHATI_SEARXNG_VENV="$CHATI_SEARXNG_DIR/.venv"
CHATI_SEARXNG_SRC="$CHATI_SEARXNG_DIR/src"
CHATI_SEARXNG_SETTINGS="$CHATI_SEARXNG_DIR/settings.yml"
CHATI_SEARXNG_HOST="${SEARXNG_LOCAL_HOST:-127.0.0.1}"
CHATI_SEARXNG_PORT="${SEARXNG_LOCAL_PORT:-8890}"

# Is a service running? $1 = its `pgrep -f` pattern.
chati_svc_running() { pgrep -f "$1" >/dev/null 2>&1; }

# Start the Ollama engine if it isn't already up. Ollama has no standalone
# start command by design (it comes up when you launch chati); this is the one
# place that logic lives, shared by chati's own startup and `chati webui`.
# Waits for the HTTP API (not just the process) so callers can use it right away.
chati_start_ollama() {
    if chati_svc_running "$CHATI_OLLAMA_PROC"; then echo "Ollama is already running"; return 0; fi
    command -v ollama >/dev/null 2>&1 || { echo "ollama not found in PATH (brew install ollama)" >&2; return 1; }
    mkdir -p "$CHATI_LOG_DIR"
    # Apple Silicon perf tuning (Homebrew ollama's recommended flags): flash
    # attention + q8 KV cache. Override by exporting these first.
    export OLLAMA_FLASH_ATTENTION="${OLLAMA_FLASH_ATTENTION:-1}"
    export OLLAMA_KV_CACHE_TYPE="${OLLAMA_KV_CACHE_TYPE:-q8_0}"
    # </dev/null so a piped/non-interactive caller doesn't hold stdin open.
    nohup ollama serve </dev/null >"$CHATI_LOG_DIR/ollama.log" 2>&1 &
    local i
    for (( i = 0; i < 10; i++ )); do
        sleep 1
        curl -fsS --max-time 2 "$(chati_ollama_api)/api/version" >/dev/null 2>&1 \
            && { echo "Ollama started"; return 0; }
    done
    echo "Ollama didn't become ready in 10s (see $CHATI_LOG_DIR/ollama.log)" >&2
    return 1
}

# Is a local SearXNG installed (venv + settings present)?
chati_searxng_installed() { [[ -x "$CHATI_SEARXNG_VENV/bin/granian" && -f "$CHATI_SEARXNG_SETTINGS" ]]; }

# Start the local SearXNG (granian) if installed and not already up. Optional:
# a no-op (returns 0) when SearXNG isn't installed locally.
chati_start_searxng() {
    chati_searxng_installed || { echo "SearXNG not installed locally (installer/install_searxng.sh)"; return 0; }
    if chati_svc_running "$CHATI_SEARXNG_PROC"; then echo "SearXNG is already running"; return 0; fi
    mkdir -p "$CHATI_LOG_DIR"
    ( cd "$CHATI_SEARXNG_SRC" && \
      SEARXNG_SETTINGS_PATH="$CHATI_SEARXNG_SETTINGS" PYTHONPATH="$CHATI_SEARXNG_SRC" \
      nohup "$CHATI_SEARXNG_VENV/bin/granian" --interface wsgi \
          --host "$CHATI_SEARXNG_HOST" --port "$CHATI_SEARXNG_PORT" \
          searx.webapp:app </dev/null >"$CHATI_LOG_DIR/searxng.log" 2>&1 & )
    local i
    for (( i = 0; i < 20; i++ )); do
        curl -s --max-time 2 -o /dev/null "http://$CHATI_SEARXNG_HOST:$CHATI_SEARXNG_PORT/healthz" \
            && { echo "SearXNG started at http://$CHATI_SEARXNG_HOST:$CHATI_SEARXNG_PORT"; return 0; }
        sleep 1
    done
    echo "SearXNG health check timed out (see $CHATI_LOG_DIR/searxng.log)" >&2
    return 1
}

# Stop a service: SIGTERM, wait up to grace seconds for it to actually exit
# (OpenWebUI/uvicorn and SearXNG/granian take a few seconds, and touching their
# SQLite before the process is gone can corrupt it), then SIGKILL as a last
# resort. One copy of the loop ailocal repeated per service.
#   $1 = proc pattern   $2 = label   $3 = grace seconds (default 15)
chati_svc_stop() {
    local pat="$1" label="$2" grace="${3:-15}" i
    chati_svc_running "$pat" || { echo "$label was not running"; return 0; }
    pkill -f "$pat"
    for (( i = 0; i < grace; i++ )); do
        chati_svc_running "$pat" || { echo "$label stopped"; return 0; }
        sleep 1
    done
    pkill -9 -f "$pat"; sleep 1
    echo "$label stopped (forced)"
}

# SEARXNG endpoints, one per line (comma- or newline-separated in the env),
# trailing slashes stripped. Empty if none configured.
chati_searxng_urls() {
    local raw="${SEARXNG_URLS:-${SEARXNG_URL:-}}" u
    printf '%s' "$raw" | tr ',' '\n' | while IFS= read -r u || [[ -n "$u" ]]; do
        u="${u#"${u%%[![:space:]]*}"}"; u="${u%"${u##*[![:space:]]}"}"  # trim
        u="${u%/}"
        [[ -n "$u" ]] && printf '%s\n' "$u"
    done
}
