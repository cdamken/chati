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

# --- STABLE, CHECKOUT-INDEPENDENT DATA HOME ---
# Persistent user DATA — saved sessions, the active-session pointer, the model
# choice, per-instance live buffers, the default system prompt — must survive a
# re-clone or a move of the checkout. Before 1.10 it lived under $BASE_DIR
# (inside the checkout), so cloning chati to a NEW path — e.g. re-cloning to
# ~/chat when an older install had lived elsewhere — left every saved session
# behind in the old directory. To the user they looked deleted (#7). It now
# lives in a stable per-user location instead. Override with CHATI_DATA_HOME.
# Existing in-checkout data is moved here once, on first run, by
# migrate_legacy_state (called from the chati/ailocal entrypoints).
export CHATI_DATA_HOME="${CHATI_DATA_HOME:-${XDG_DATA_HOME:-$HOME/.local/share}/chati}"
mkdir -p "$CHATI_DATA_HOME" 2>/dev/null

if [[ -n "$CHATI_INSTANCE" ]]; then
    _chati_inst=$(printf '%s' "$CHATI_INSTANCE" | tr -c 'A-Za-z0-9_-' '_')
    export STATE_DIR="$CHATI_DATA_HOME/instances/$_chati_inst"
else
    export STATE_DIR="$CHATI_DATA_HOME"
fi
mkdir -p "$STATE_DIR" 2>/dev/null

export ACTIVE_MODEL_FILE="${ACTIVE_MODEL_FILE:-$CHATI_DATA_HOME/.active_ollama_model.txt}"
export MESSAGES_FILE="${MESSAGES_FILE:-$STATE_DIR/.messages.active.ola.txt}"
export ACTIVE_FILE="${ACTIVE_FILE:-$MESSAGES_FILE}"
export HISTORY_DIR="${HISTORY_DIR:-$CHATI_DATA_HOME/conversation_histories}"
export PREVIOUS_FILE="${PREVIOUS_FILE:-$STATE_DIR/.ola_previous.txt}"
# Name of the session that was active before the current one. Used by /back.
export BACK_FILE="${BACK_FILE:-$STATE_DIR/.ola_back.txt}"

# --- SESSION-SPECIFIC COMPANIONS ---
# Each session has its own prompt and summary file under $HISTORY_DIR.
# These exports capture the *initial* session at sourcing time; consumers
# that need the live session (e.g. chati after /switch) should call
# current_session_prompt_file instead.
export DEFAULT_SYSTEM_PROMPT="${DEFAULT_SYSTEM_PROMPT:-$CHATI_DATA_HOME/.system_prompt.txt}"
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
export DEFAULT_MODEL="${DEFAULT_MODEL:-gemma4:26b}"

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

# --- OUTPUT PRETTIFIER (LaTeX-ish math → Unicode) ---
# Models often emit inline TeX ("$\rightarrow$", "\alpha", "x^{2}") which reads
# as noise in a terminal (#8). prettify_stream is a line-buffered filter that
# rewrites the common commands to their Unicode glyphs as the answer streams.
# It is deliberately conservative: fenced ``` code blocks and inline `code`
# spans pass through untouched, and "$…$" is only unwrapped when it actually
# contains a backslash command (so "$5" / "$PATH" are safe). Disable with
# CHATI_PRETTY=0. Line-buffered (not word-buffered) so code-fence state is
# tracked cleanly; output still appears line-by-line as the model streams.
IFS= read -r -d '' CHATI_PRETTY_PROG <<'PRETTY_PROG'
use strict; use warnings;
binmode(STDIN,  ":encoding(UTF-8)");
binmode(STDOUT, ":encoding(UTF-8)");
$| = 1;
my %M = (
  'rightarrow'=>"\x{2192}", 'to'=>"\x{2192}", 'longrightarrow'=>"\x{27F6}",
  'leftarrow'=>"\x{2190}", 'gets'=>"\x{2190}", 'longleftarrow'=>"\x{27F5}",
  'leftrightarrow'=>"\x{2194}", 'mapsto'=>"\x{21A6}",
  'Rightarrow'=>"\x{21D2}", 'implies'=>"\x{21D2}", 'Leftarrow'=>"\x{21D0}",
  'Leftrightarrow'=>"\x{21D4}", 'iff'=>"\x{21D4}",
  'uparrow'=>"\x{2191}", 'downarrow'=>"\x{2193}",
  'times'=>"\x{00D7}", 'div'=>"\x{00F7}", 'cdot'=>"\x{00B7}", 'ast'=>"\x{2217}",
  'pm'=>"\x{00B1}", 'mp'=>"\x{2213}", 'leq'=>"\x{2264}", 'le'=>"\x{2264}",
  'geq'=>"\x{2265}", 'ge'=>"\x{2265}", 'neq'=>"\x{2260}", 'ne'=>"\x{2260}",
  'approx'=>"\x{2248}", 'equiv'=>"\x{2261}", 'sim'=>"\x{223C}", 'cong'=>"\x{2245}",
  'propto'=>"\x{221D}", 'infty'=>"\x{221E}", 'nabla'=>"\x{2207}", 'partial'=>"\x{2202}",
  'sum'=>"\x{2211}", 'prod'=>"\x{220F}", 'int'=>"\x{222B}", 'sqrt'=>"\x{221A}",
  'forall'=>"\x{2200}", 'exists'=>"\x{2203}", 'in'=>"\x{2208}", 'notin'=>"\x{2209}",
  'subset'=>"\x{2282}", 'supset'=>"\x{2283}", 'subseteq'=>"\x{2286}", 'supseteq'=>"\x{2287}",
  'cup'=>"\x{222A}", 'cap'=>"\x{2229}", 'emptyset'=>"\x{2205}", 'varnothing'=>"\x{2205}",
  'angle'=>"\x{2220}", 'land'=>"\x{2227}", 'lor'=>"\x{2228}", 'lnot'=>"\x{00AC}", 'neg'=>"\x{00AC}",
  'ldots'=>"\x{2026}", 'dots'=>"\x{2026}", 'cdots'=>"\x{22EF}", 'deg'=>"\x{00B0}",
  'prime'=>"\x{2032}", 'star'=>"\x{2605}", 'bullet'=>"\x{2022}", 'circ'=>"\x{2218}",
  'oplus'=>"\x{2295}", 'otimes'=>"\x{2297}", 'perp'=>"\x{22A5}", 'parallel'=>"\x{2225}",
  'alpha'=>"\x{03B1}",'beta'=>"\x{03B2}",'gamma'=>"\x{03B3}",'delta'=>"\x{03B4}",
  'epsilon'=>"\x{03B5}",'varepsilon'=>"\x{03B5}",'zeta'=>"\x{03B6}",'eta'=>"\x{03B7}",
  'theta'=>"\x{03B8}",'vartheta'=>"\x{03B8}",'iota'=>"\x{03B9}",'kappa'=>"\x{03BA}",
  'lambda'=>"\x{03BB}",'mu'=>"\x{03BC}",'nu'=>"\x{03BD}",'xi'=>"\x{03BE}",
  'pi'=>"\x{03C0}",'rho'=>"\x{03C1}",'sigma'=>"\x{03C3}",'tau'=>"\x{03C4}",
  'upsilon'=>"\x{03C5}",'phi'=>"\x{03C6}",'varphi'=>"\x{03C6}",'chi'=>"\x{03C7}",
  'psi'=>"\x{03C8}",'omega'=>"\x{03C9}",
  'Gamma'=>"\x{0393}",'Delta'=>"\x{0394}",'Theta'=>"\x{0398}",'Lambda'=>"\x{039B}",
  'Xi'=>"\x{039E}",'Pi'=>"\x{03A0}",'Sigma'=>"\x{03A3}",'Phi'=>"\x{03A6}",
  'Psi'=>"\x{03A8}",'Omega'=>"\x{03A9}",
);
my %SUP = ("0"=>"\x{2070}","1"=>"\x{00B9}","2"=>"\x{00B2}","3"=>"\x{00B3}","4"=>"\x{2074}",
  "5"=>"\x{2075}","6"=>"\x{2076}","7"=>"\x{2077}","8"=>"\x{2078}","9"=>"\x{2079}",
  "+"=>"\x{207A}","-"=>"\x{207B}","n"=>"\x{207F}","i"=>"\x{2071}");
my %SUB = ("0"=>"\x{2080}","1"=>"\x{2081}","2"=>"\x{2082}","3"=>"\x{2083}","4"=>"\x{2084}",
  "5"=>"\x{2085}","6"=>"\x{2086}","7"=>"\x{2087}","8"=>"\x{2088}","9"=>"\x{2089}",
  "+"=>"\x{208A}","-"=>"\x{208B}");
sub supize { my ($t)=@_; my $o=""; for my $c (split //,$t){ return undef unless exists $SUP{$c}; $o.=$SUP{$c}; } return $o; }
sub subize { my ($t)=@_; my $o=""; for my $c (split //,$t){ return undef unless exists $SUB{$c}; $o.=$SUB{$c}; } return $o; }
sub convert {
  my ($s)=@_;
  $s =~ s/\\(?:text|mathrm|mathbf|mathit|mathsf|mathcal|operatorname)\s*\{([^{}]*)\}/$1/g;
  $s =~ s{\\frac\s*\{([^{}]*)\}\s*\{([^{}]*)\}}{$1/$2}g;
  $s =~ s/\\\[\s*(.*?)\s*\\\]/$1/gs;
  $s =~ s/\\\(\s*(.*?)\s*\\\)/$1/gs;
  $s =~ s/\$\$(?=[^\$]*\\)(.+?)\$\$/$1/gs;
  $s =~ s/\$(?=[^\$]*\\)([^\$]+)\$/$1/g;
  $s =~ s/\\([A-Za-z]+)/exists $M{$1} ? $M{$1} : "\\$1"/ge;
  $s =~ s/\\([%\$&_#{}])/$1/g;
  $s =~ s/\^\{([^{}]+)\}/my $r=supize($1); defined $r ? $r : "^{$1}"/ge;
  $s =~ s/\^([0-9+\-])/my $r=supize($1); defined $r ? $r : "^$1"/ge;
  $s =~ s/_\{([^{}]+)\}/my $r=subize($1); defined $r ? $r : "_{$1}"/ge;
  $s =~ s/_([0-9+\-])/my $r=subize($1); defined $r ? $r : "_$1"/ge;
  return $s;
}
sub process_line {
  my ($line)=@_;
  my @parts = split /(`[^`]*`)/, $line;
  for my $p (@parts) { $p = convert($p) unless $p =~ /\A`.*`\z/s; }
  return join("", @parts);
}
my $in_fence = 0;
while (my $line = <STDIN>) {
  if ($line =~ /^\s*```/) { $in_fence = !$in_fence; print $line; next; }
  if ($in_fence) { print $line; next; }
  print process_line($line);
}
PRETTY_PROG

# Filter stdin→stdout, rewriting inline TeX to Unicode (see CHATI_PRETTY_PROG).
# Falls back to a transparent `cat` when disabled or perl is unavailable, so it
# can be dropped into any pipeline without risk of eating the stream.
prettify_stream() {
    if [[ "${CHATI_PRETTY:-1}" == "0" ]] || ! command -v perl >/dev/null 2>&1; then
        cat
        return
    fi
    perl -CSAD -e "$CHATI_PRETTY_PROG"
}

# Log messages with timestamps to $LOG_FILE. Stays quiet on success so it
# can be sprinkled anywhere without polluting output.
log_chat() {
    mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null
    echo "$(date '+%Y-%m-%d %H:%M:%S') $1" >> "$LOG_FILE"
}

# One-time migration (chati ≤1.9.x → 1.10+). Move persistent DATA that used to
# live INSIDE the checkout ($BASE_DIR) into the stable $CHATI_DATA_HOME, so a
# future upgrade or re-clone never orphans saved sessions again (#7). It is
# non-destructive (each item moves only when its destination doesn't already
# exist, so it can't clobber newer data) and idempotent (a sentinel stops it
# re-scanning). Call it ONCE from an entrypoint (chati / ailocal) — never at
# source time: that would disturb the test sandbox and race the ola/mola
# subprocesses that re-source this lib on every turn.
migrate_legacy_state() {
    local sentinel="$CHATI_DATA_HOME/.migrated"
    [[ -f "$sentinel" ]] && return 0

    local legacy_state="$BASE_DIR/ola_chat"   # pre-1.10 default STATE_DIR
    local moved=0 f base

    # Saved sessions and their per-session prompt/summary companion files.
    if [[ -d "$BASE_DIR/conversation_histories" ]]; then
        mkdir -p "$HISTORY_DIR" 2>/dev/null
        for f in "$BASE_DIR/conversation_histories"/*; do
            [[ -e "$f" ]] || continue
            base=$(basename "$f")
            [[ -e "$HISTORY_DIR/$base" ]] && continue
            mv "$f" "$HISTORY_DIR/" 2>/dev/null && moved=1
        done
    fi

    # Shared-instance active state, the model pointer and the default prompt.
    local pair src dst
    for pair in \
        "$legacy_state/.ola_previous.txt=>$CHATI_DATA_HOME/.ola_previous.txt" \
        "$legacy_state/.ola_back.txt=>$CHATI_DATA_HOME/.ola_back.txt" \
        "$legacy_state/.messages.active.ola.txt=>$CHATI_DATA_HOME/.messages.active.ola.txt" \
        "$legacy_state/.last_response.txt=>$CHATI_DATA_HOME/.last_response.txt" \
        "$legacy_state/.system_prompt.txt=>$CHATI_DATA_HOME/.system_prompt.txt" \
        "$BASE_DIR/.active_ollama_model.txt=>$CHATI_DATA_HOME/.active_ollama_model.txt"
    do
        src="${pair%%=>*}"; dst="${pair##*=>}"
        [[ -f "$src" && ! -e "$dst" ]] && mv "$src" "$dst" 2>/dev/null && moved=1
    done

    # Per-instance (CHATI_INSTANCE=…) active-state directories.
    if [[ -d "$legacy_state/instances" ]]; then
        mkdir -p "$CHATI_DATA_HOME/instances" 2>/dev/null
        for f in "$legacy_state/instances"/*; do
            [[ -e "$f" ]] || continue
            base=$(basename "$f")
            [[ -e "$CHATI_DATA_HOME/instances/$base" ]] && continue
            mv "$f" "$CHATI_DATA_HOME/instances/" 2>/dev/null && moved=1
        done
    fi

    : > "$sentinel" 2>/dev/null
    [[ "$moved" -eq 1 ]] && \
        echo "✅ chati: moved your saved sessions & settings to $CHATI_DATA_HOME (they now survive upgrades)." >&2
    return 0
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
