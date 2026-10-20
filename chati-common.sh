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

# Git-style dispatch: given a subcommand name, echo the path of its executable
# libexec script if it exists, else nothing. A leading-dash arg (a flag) or an
# empty name never resolves. This is the single rule the dispatcher uses.
chati_resolve_subcommand() {
    local name="${1:-}"
    [[ -n "$name" && "$name" != -* && -x "$CHATI_DIR/libexec/chati-$name" ]] \
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
    local action="${1:-status}"
    local ail="$CHATI_DIR/ai_local/ailocal"
    [[ -x "$ail" ]] || { echo "ailocal no encontrado en $ail" >&2; return 3; }
    case "$action" in
        start|stop|restart) exec "$ail" "$action" "$target" ;;
        status)             exec "$ail" status ;;
        -h|--help)          echo "uso: chati $target start|stop|restart|status"; return 0 ;;
        *) echo "uso: chati $target start|stop|restart|status" >&2; return 2 ;;
    esac
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
