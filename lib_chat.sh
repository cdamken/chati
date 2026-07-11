#!/bin/bash
#==============================================================================
# LIB_CHAT.SH - Shared Configuration & Helper Functions
#==============================================================================

# --- PATHS ---
# All paths use ${VAR:-default} so a caller (e.g. the test harness) can
# pre-export an override BEFORE sourcing this file and sandbox the whole
# session into a temp dir. Without this, sourcing the lib would clobber
# the caller's overrides and any subprocess (mola/ola/...) would write
# back into the real ~/chat tree.
#
# BASE_DIR defaults to the directory this file lives in — i.e. wherever
# the repo was checked out — NOT a hardcoded $HOME/chat. This is what lets
# the folder be named/placed however you like (a clone left as
# ~/chat-system-cli, a worktree, etc.) and still find its sub-tools
# (ola/mola/lib_web.sh all live beside this file). When the checkout IS
# at ~/chat the value is identical to before.
export BASE_DIR="${BASE_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"

# --- PER-MACHINE CONFIG (.env) ---
# Personal, machine-specific config — your SearXNG endpoint and its
# credentials — lives in $BASE_DIR/.env, which is gitignored. It is NOT
# baked into the repo, so the project ships neutral: someone else cloning
# it points /web at THEIR own SearXNG (cloud or local), not yours. Sourced
# here, before the defaults below, so .env values win and anything it
# doesn't set falls back to the defaults. Copy .env.example to .env to
# start. Honored as an override: AILOCAL_ENV/ CHAT_ENV can relocate it.
CHAT_ENV="${CHAT_ENV:-$BASE_DIR/.env}"
[[ -f "$CHAT_ENV" ]] && source "$CHAT_ENV"
export OLA_DIR="${OLA_DIR:-$BASE_DIR/ola_chat}"
export DOCR_DIR="${DOCR_DIR:-$BASE_DIR/docr}"
export LOG_FILE="${LOG_FILE:-$HOME/logs/chati.log}"

# --- PER-INSTANCE ACTIVE STATE (concurrent terminals) ---
# The "active" state (which session is current, its live buffer, the last
# response, the /back pointer, command history) is a single shared set by
# default — so two chati in two terminals would clobber each other. Set
# CHATI_INSTANCE to give a terminal its OWN active state, isolated under
# $OLA_DIR/instances/<name>, and run independent chats side by side:
#     CHATI_INSTANCE=work    chati
#     CHATI_INSTANCE=research chati
# Unset = the classic single shared instance (backward compatible). Saved
# sessions (HISTORY_DIR) and the model choice stay SHARED across instances.
export CHATI_INSTANCE="${CHATI_INSTANCE:-}"
if [[ -n "$CHATI_INSTANCE" ]]; then
    _chati_inst=$(printf '%s' "$CHATI_INSTANCE" | tr -c 'A-Za-z0-9_-' '_')
    export STATE_DIR="$OLA_DIR/instances/$_chati_inst"
else
    export STATE_DIR="$OLA_DIR"
fi
mkdir -p "$STATE_DIR" 2>/dev/null

export ACTIVE_MODEL_FILE="${ACTIVE_MODEL_FILE:-$BASE_DIR/.active_ollama_model.txt}"
export MESSAGES_FILE="${MESSAGES_FILE:-$STATE_DIR/.messages.active.ola.txt}"
export ACTIVE_FILE="${ACTIVE_FILE:-$MESSAGES_FILE}"
export HISTORY_DIR="${HISTORY_DIR:-$BASE_DIR/conversation_histories}"
export PREVIOUS_FILE="${PREVIOUS_FILE:-$STATE_DIR/.ola_previous.txt}"
# Name of the session that was active before the current one. Used by /back.
export BACK_FILE="${BACK_FILE:-$STATE_DIR/.ola_back.txt}"

# --- SESSION-SPECIFIC COMPANIONS ---
# Each session has its own prompt and summary file under $HISTORY_DIR.
# These exports capture the *initial* session at sourcing time; consumers
# that need the live session (e.g. chati after /switch) should call
# current_session_prompt_file instead.
export DEFAULT_SYSTEM_PROMPT="${DEFAULT_SYSTEM_PROMPT:-$OLA_DIR/.system_prompt.txt}"
CURRENT_SESS_NAME=$(cat "$PREVIOUS_FILE" 2>/dev/null)
if [[ -n "$CURRENT_SESS_NAME" ]]; then
    export SESSION_PROMPT="$HISTORY_DIR/${CURRENT_SESS_NAME}_prompt"
    export SESSION_SUMMARY="$HISTORY_DIR/${CURRENT_SESS_NAME}_summary"
else
    export SESSION_PROMPT="$DEFAULT_SYSTEM_PROMPT"
    export SESSION_SUMMARY=""
fi

# Sub-tool entry points. Use these instead of literal "$OLA_DIR/foo" in
# callers so swapping a binary (or wrapping it for tests) is one edit.
export CHAT_CMD="${CHAT_CMD:-$OLA_DIR/ola}"
export MOLA_CMD="${MOLA_CMD:-$OLA_DIR/mola}"
export OLA_MODEL_CMD="${OLA_MODEL_CMD:-$OLA_DIR/ola_model}"
export DOCR_CMD="${DOCR_CMD:-$DOCR_DIR/docr}"

# --- OLLAMA ---
export OLLAMA_API="${OLLAMA_API:-http://localhost:11434}"
# Single source of truth for the default model. Override via the env if
# you want a different fallback when no $ACTIVE_MODEL_FILE exists yet.
export DEFAULT_MODEL="${DEFAULT_MODEL:-llama3.2:1b}"

# --- BACKEND INTEROP ---
# Where ola writes the final response so chati can read it without
# capturing stdout (necessary for streaming to be visible to the user).
export LAST_RESPONSE_FILE="${LAST_RESPONSE_FILE:-$STATE_DIR/.last_response.txt}"

# --- TUNABLES (override via env) ---
# Compress conversation memory every N new messages.
export COMPRESS_EVERY="${COMPRESS_EVERY:-20}"
# Number of recent messages kept verbatim in each Ollama call.
export SLIDING_WINDOW="${SLIDING_WINDOW:-20}"
# Max characters fed to the model from auxiliary sources.
export MAX_WEB_CHARS="${MAX_WEB_CHARS:-6000}"
export MAX_URL_CHARS="${MAX_URL_CHARS:-15000}"
export MAX_COMPRESS_CHARS="${MAX_COMPRESS_CHARS:-10000}"
# curl timeouts in seconds. Long for streaming chat, short for meta calls.
export OLA_CURL_TIMEOUT="${OLA_CURL_TIMEOUT:-600}"
export OLA_CURL_META_TIMEOUT="${OLA_CURL_META_TIMEOUT:-60}"
# Web search scratch dir. chati's do_web_research creates a fresh
# `turn.XXXXXX` subdir here per turn (mktemp -d) and wipes it after the
# answer lands. Nothing else persists, so there's no TTL knob anymore.
export WEB_CACHE_DIR="${WEB_CACHE_DIR:-$BASE_DIR/.web_cache}"

# SearXNG backend for /web. Intentionally has NO default — it's a
# per-person endpoint, not shared config, so it lives in your .env (see
# .env.example), never baked into the repo. Empty here means the /web
# preflight reports "not configured" instead of pointing a stranger's
# clone at someone else's server. Point it at your own instance — cloud
# or a local SearXNG (see SEARXNG_SETUP.md).
export SEARXNG_URL="${SEARXNG_URL:-}"
# SEARXNG_USER / SEARXNG_PASS (if your instance needs auth) also come
# from .env — never hardcode credentials in the repo.

# --- HELPERS ---

# Print "Error: $*" to stderr and exit 1. Same definition used to live
# in ola, mola and ola_model — kept here so callers stay one line.
error_exit() {
    echo "Error: $*" >&2
    exit 1
}

# Trim leading + trailing ASCII whitespace from $1 and print to stdout.
trim_ws() {
    local s="$1"
    s="${s#"${s%%[![:space:]]*}"}"
    s="${s%"${s##*[![:space:]]}"}"
    printf '%s' "$s"
}

# Expand tilde (~) and handle backslashes in paths
expand_path() {
    local path="$1"
    path="${path/#\~/$HOME}"
    path="${path//\\ / }"
    echo "$path"
}

# Path to the prompt file for the currently-active session. Re-read from
# disk on every call so commands like /switch take effect immediately.
current_session_prompt_file() {
    local sess
    sess=$(cat "$PREVIOUS_FILE" 2>/dev/null)
    if [[ -n "$sess" ]]; then
        echo "$HISTORY_DIR/${sess}_prompt"
    else
        echo "$DEFAULT_SYSTEM_PROMPT"
    fi
}

# Log messages with timestamps to $LOG_FILE. Stays quiet on success so it
# can be sprinkled anywhere without polluting output.
log_chat() {
    mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null
    echo "$(date '+%Y-%m-%d %H:%M:%S') $1" >> "$LOG_FILE"
}

# True if there's a process listening on the Ollama port. Intentionally
# a TCP-level probe rather than an HTTP call to /api/version: with
# large models (e.g. 26B), the HTTP server can be momentarily
# unresponsive between requests while the runner is loading/unloading
# weights, which would make an HTTP healthcheck spuriously fail even
# though Ollama is healthy. The real chat call downstream will report
# any deeper failure with a meaningful message.
ollama_running() {
    local hp="${OLLAMA_API#http://}"
    hp="${hp#https://}"
    hp="${hp%/}"
    local host="${hp%:*}"
    local port="${hp##*:}"
    [[ "$host" == "$port" ]] && port=11434
    # Prefer `nc -z` with a 2s timeout. Use -w (both BSD/macOS and GNU
    # netcat support it) rather than -G, which is macOS-only and makes
    # this probe fail outright on Linux → nothing would start. Fall back
    # to bash's /dev/tcp built-in if nc isn't installed.
    if command -v nc >/dev/null 2>&1; then
        nc -z -w 2 "$host" "$port" >/dev/null 2>&1
    else
        (exec 3<>"/dev/tcp/$host/$port") 2>/dev/null && exec 3<&- 3>&-
    fi
}

# Return the active model name.
#   1. An explicit selection ($ACTIVE_MODEL_FILE) always wins — cheap path,
#      no shell-out. This is trusted: ola_model verified it at set time.
#   2. No selection yet (fresh machine): prefer $DEFAULT_MODEL, but ONLY if
#      it is actually installed. Otherwise fall back to the first installed
#      model. Without this, a fresh machine whose models differ from
#      DEFAULT_MODEL fails the first send with a cryptic "model 'X' not
#      found" (mirrors router_model, which already does this).
#   3. Nothing installed / ollama down: return the configured default name
#      so any resulting error at least names a model.
active_model() {
    if [[ -s "$ACTIVE_MODEL_FILE" ]]; then
        local m
        m=$(cat "$ACTIVE_MODEL_FILE" 2>/dev/null)
        if [[ -n "$m" ]]; then
            printf '%s\n' "$m"
            return 0
        fi
    fi
    local installed
    installed=$(ollama list 2>/dev/null | tail -n +2 | awk 'NF{print $1}')
    if [[ -n "$installed" ]]; then
        if printf '%s\n' "$installed" | grep -qxF "$DEFAULT_MODEL"; then
            printf '%s\n' "$DEFAULT_MODEL"
            return 0
        fi
        # First installed model that can actually chat. Skip embedding
        # models (bge-*/nomic-embed/*-embed) — they'd return an empty/garbage
        # response and reproduce the very failure we're avoiding.
        local first_chat
        first_chat=$(printf '%s\n' "$installed" | grep -viE 'embed|^bge-' | head -n1)
        printf '%s\n' "${first_chat:-$(printf '%s\n' "$installed" | head -n1)}"
        return 0
    fi
    printf '%s\n' "$DEFAULT_MODEL"
}

# Preferred lightweight models for quick triage decisions (the /web
# search-or-not router). Baked in here — not ~/.zshrc — so the preference
# travels with the repo to any machine. The list is matched against what
# is ACTUALLY installed, so naming a model that isn't present is harmless.
# Order = preference (smallest/fastest first). To pin a specific router
# model instead, set WEB_ROUTER_MODEL (router_model honors it first).
WEB_ROUTER_PREFERENCES=("llama3.2:3b" "llama3.2:1b" "qwen2.5:3b" "gemma2:2b" "phi3:mini")

# Pick a small fast model for triage, with no machine-specific config:
#   1. $WEB_ROUTER_MODEL if the user set an explicit override
#   2. else the first WEB_ROUTER_PREFERENCES entry that is installed
#   3. else the active model (always works, just slower)
# Never fails — worst case it returns the active model. The point is a
# snappy yes/no decision without paying for the big answer model.
router_model() {
    if [[ -n "${WEB_ROUTER_MODEL:-}" ]]; then
        printf '%s\n' "$WEB_ROUTER_MODEL"
        return 0
    fi
    local installed pref
    installed=$(ollama list 2>/dev/null | tail -n +2 | awk '{print $1}')
    if [[ -n "$installed" ]]; then
        for pref in "${WEB_ROUTER_PREFERENCES[@]}"; do
            if printf '%s\n' "$installed" | grep -qxF "$pref"; then
                printf '%s\n' "$pref"
                return 0
            fi
        done
    fi
    active_model
}

# Count user/assistant turns in a session file. Handles both the legacy
# "role: content" lines and the current JSONL format. Returns 0 on
# missing/empty file (never errors).
session_msg_count() {
    local f="$1"
    [[ -f "$f" ]] || { echo 0; return 0; }
    local c
    c=$(grep -cE '^(user|assistant):|^\{"role":' "$f" 2>/dev/null) || c=0
    [[ -z "$c" ]] && c=0
    echo "$c"
}

# Companion file suffixes that travel with a session file. Update this
# list and every site that manages sessions (rename/delete/autorename
# cleanup) picks up the change automatically.
SESSION_COMPANION_SUFFIXES=(_prompt _summary _compressed_at)

# Remove a session file and all its companions. Safe to call on a
# nonexistent base file.
remove_session_files() {
    local base="$1"
    [[ -z "$base" ]] && return 0
    rm -f "$base"
    local s
    for s in "${SESSION_COMPANION_SUFFIXES[@]}"; do
        rm -f "${base}${s}"
    done
}

# Rename a session file together with its companions. Only the files
# that exist are moved — missing companions don't trigger errors.
move_session_files() {
    local src="$1" dst="$2"
    [[ -z "$src" || -z "$dst" || "$src" == "$dst" ]] && return 0
    [[ -f "$src" ]] && mv "$src" "$dst"
    local s
    for s in "${SESSION_COMPANION_SUFFIXES[@]}"; do
        [[ -f "${src}${s}" ]] && mv "${src}${s}" "${dst}${s}"
    done
    return 0
}

# Send one user prompt to Ollama's /api/chat with stream=false and print
# the assistant's content on stdout. $3 (optional) overrides the timeout;
# defaults to the meta timeout. Returns 1 on any transport or JSON
# failure; the caller decides how to react.
#
# Centralizes the curl + jq dance shared by mola (autorename, compress)
# and lib_web.sh (decompose_query).
ollama_chat_oneshot() {
    local model="$1" prompt="$2" timeout="${3:-${OLA_CURL_META_TIMEOUT:-60}}"
    [[ -z "$model" || -z "$prompt" ]] && return 1
    local payload
    payload=$(jq -n --arg m "$model" --arg p "$prompt" \
        '{model:$m, messages:[{role:"user", content:$p}], stream:false}') || return 1
    local response rc
    response=$(curl -s --max-time "$timeout" \
        -X POST "$OLLAMA_API/api/chat" \
        -H "Content-Type: application/json" \
        -d "$payload")
    rc=$?
    # Distinguish a transport failure (curl non-zero: unreachable,
    # timeout) from a reachable server that returned no usable content —
    # both still return 1 to the caller, but the log says which, instead
    # of `curl -s` swallowing the difference silently.
    if (( rc != 0 )); then
        log_chat "ollama_chat_oneshot: curl transport failure (exit $rc, model=$model)"
        return 1
    fi
    local content
    content=$(printf '%s' "$response" | jq -r '.message.content // empty' 2>/dev/null)
    if [[ -z "$content" ]]; then
        log_chat "ollama_chat_oneshot: empty content (model=$model)"
        return 1
    fi
    printf '%s' "$content"
}

# --- VOICE DETECTION ---
# Statistical language detection for macOS `say`. Used to live in
# python/detect_voice.sh as a standalone script; folded in here so the
# whole detection path is one sourced function with no subprocess.

# Count case-insensitive regex matches in $2 (one match per output line).
count_lang_matches() {
    local pattern="$1" text="$2"
    printf '%s' "$text" | grep -oiE "$pattern" | wc -l | tr -d ' '
}

# Pick the best `say` voice for the text. Script detection first
# (Cyrillic → Milena, Arabic → Maged), then statistical scoring of
# Latin-script languages by stopwords + diacritics. Low-confidence
# (score < 2) falls back to Samantha (English).
get_voice() {
    local text="$*"
    [[ -z "$text" ]] && { echo "Samantha"; return 0; }

    # Script detection via UTF-8 lead bytes (LC_ALL=C). Bash 3.2's =~
    # degrades multibyte bracket ranges like [؀-ۿ] to single bytes, which
    # made Spanish accents (0xC2/0xC3 lead) match the Arabic "range" and
    # come out as Maged. Lead bytes are unambiguous: Cyrillic U+0400-04FF
    # encodes with 0xD0-0xD1, Arabic U+0600-06FF with 0xD8-0xDB, and
    # Latin-1 accents with 0xC2-0xC3 — no overlap.
    # Cyrillic (Russian) — only if it outweighs the Latin characters.
    if printf '%s' "$text" | LC_ALL=C grep -q $'[\xd0\xd1]'; then
        local cyr lat
        cyr=$(printf '%s' "$text" | LC_ALL=C grep -o $'[\xd0\xd1]' | wc -l | tr -d ' ')
        lat=$(printf '%s' "$text" | LC_ALL=C grep -o "[a-zA-Z]" | wc -l | tr -d ' ')
        (( cyr > lat )) && { echo "Milena"; return 0; }
    fi
    # Arabic script.
    if printf '%s' "$text" | LC_ALL=C grep -q $'[\xd8-\xdb]'; then
        echo "Maged"
        return 0
    fi

    local es de fr pt it en
    es=$(count_lang_matches "\b(el|la|los|las|un|una|con|para|por|en|si|no|gracias|está|están|como)\b|[¿¡áéíóúñ]" "$text")
    de=$(count_lang_matches "\b(der|die|das|ein|eine|und|ist|mit|für|von|zu|nicht|danke|bitte)\b|[äöüßÄÖÜ]" "$text")
    fr=$(count_lang_matches "\b(le|la|les|un|une|et|est|avec|pour|par|dans|mais|merci|vous)\b|[éèêëàâîïôûùç]" "$text")
    pt=$(count_lang_matches "\b(o|a|os|as|um|uma|com|para|por|em|não|obrigado|está)\b|[ãõçêí]" "$text")
    it=$(count_lang_matches "\b(il|lo|la|i|gli|le|un|una|ed|con|per|non|grazie|bene)\b|[àèéìòù]" "$text")
    en=$(count_lang_matches "\b(the|and|for|with|that|this|have|from|your|please|thanks)\b" "$text")

    local max=0 winner="Samantha"
    (( es > max )) && { max=$es; winner="Paulina"; }
    (( de > max )) && { max=$de; winner="Anna"; }
    (( fr > max )) && { max=$fr; winner="Thomas"; }
    (( pt > max )) && { max=$pt; winner="Luciana"; }
    (( it > max )) && { max=$it; winner="Alice"; }
    (( en > max )) && { max=$en; winner="Samantha"; }

    if (( max < 2 )); then
        echo "Samantha"
    else
        echo "$winner"
    fi
}

# Web research helpers (fetch_url, web_search, decompose_query) live in
# their own file to keep this one focused on config + core helpers.
# Sourcing it here keeps a single entry point: consumers only ever
# `source lib_chat.sh`.
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib_web.sh"
