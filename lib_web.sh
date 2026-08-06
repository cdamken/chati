#!/bin/bash
#==============================================================================
# LIB_WEB.SH - Web research helpers: URL fetch, SearXNG search, decomposition
#==============================================================================
# Pure bash + curl + jq. These used to be the python/ helpers
# (url_fetch.py, web_search.py, decompose.py); the ports keep the exact
# output contracts — chati pattern-matches the "Error: ..." strings.
#
# Requires lib_chat.sh to be sourced first (active_model, trim_ws,
# ollama_chat_oneshot, tunables). lib_chat.sh sources this file itself,
# so consumers only ever source lib_chat.sh.

# --- URL fetch (/url) --------------------------------------------------------

# Truncate stdin to $1 bytes, then drop any partial trailing UTF-8 char.
# head -c cuts on a byte boundary and can split a multibyte character,
# which then reaches the LLM as a mojibake byte; iconv -c strips the
# incomplete tail. Falls back to plain byte truncation if iconv is absent.
utf8_truncate() {
    if command -v iconv >/dev/null 2>&1; then
        head -c "$1" | iconv -f UTF-8 -t UTF-8 -c 2>/dev/null
    else
        head -c "$1"
    fi
}

# Render a webpage to readable text via lynx. Prints the text capped at
# MAX_URL_CHARS, or an "Error: ..." line the caller can pattern-match.
# Always returns 0 — errors travel in the output string, same as the old
# python helper.
fetch_url() {
    local url="$1"
    local max_chars="${MAX_URL_CHARS:-15000}"
    local timeout="${URL_FETCH_TIMEOUT:-30}"

    local lynx_bin
    lynx_bin=$(command -v lynx)
    [[ -z "$lynx_bin" && -x /opt/homebrew/bin/lynx ]] && lynx_bin=/opt/homebrew/bin/lynx
    if [[ -z "$lynx_bin" ]]; then
        echo 'Error: lynx is not installed. Run `brew install lynx`.'
        return 0
    fi

    # Bash-only timeout: macOS has no `timeout` command, so run lynx in
    # the background and let a watchdog kill it after $timeout seconds.
    local out_file
    out_file=$(mktemp)
    "$lynx_bin" -dump -nolist -display_charset=utf-8 "$url" >"$out_file" 2>/dev/null &
    local pid=$!
    ( sleep "$timeout"; kill "$pid" 2>/dev/null ) &
    local watchdog=$!
    local rc=0
    wait "$pid" 2>/dev/null || rc=$?
    kill "$watchdog" 2>/dev/null
    wait "$watchdog" 2>/dev/null

    if (( rc == 143 )); then
        # Exactly the watchdog's SIGTERM → a real timeout. Other signals
        # (e.g. 130 = user Ctrl-C) are NOT timeouts and shouldn't claim to
        # be — they fall through to the generic branch below.
        rm -f "$out_file"
        echo "Error: fetch timed out."
        return 0
    elif (( rc != 0 )); then
        rm -f "$out_file"
        echo "Error: could not fetch URL."
        return 0
    fi
    if ! grep -q '[^[:space:]]' "$out_file" 2>/dev/null; then
        rm -f "$out_file"
        echo "Could not extract text from this page."
        return 0
    fi
    utf8_truncate "$max_chars" < "$out_file"
    rm -f "$out_file"
}

# --- SearXNG search (/w) -----------------------------------------------------

# Format a SearXNG JSON response (stdin) into the compact text block the
# LLM consumes: one block per hit (title / snippet / [engine] url), plus
# up to 2 infoboxes and 2 direct answers. Split out from web_search so it
# can be unit-tested against a fixture. Empty output = nothing usable.
format_search_results() {
    local max_results="${SEARXNG_MAX_RESULTS:-10}"
    jq -r --argjson max "$max_results" '
        def clean: gsub("^\\s+|\\s+$"; "");
        [ ((.results // [])[:$max][]
            | [ ((.title // "") | clean),
                ((.content // "") | clean),
                (if ((.url // "") | length) > 0
                 then (if ((.engine // "") | length) > 0
                       then "[\(.engine)] \(.url | clean)"
                       else (.url | clean) end)
                 else "" end) ]
            | map(select(length > 0)) | join("\n")),
          ((.infoboxes // [])[:2][]
            | select(((.content // "") | length) > 0)
            | "[infobox] \(.infobox // "")\n\(.content | clean)"),
          ((.answers // [])[:2][] | "[answer] \(.)")
        ] | map(select(length > 0)) | join("\n\n")
    ' 2>/dev/null
}

# Build a curl config file carrying the SearXNG credentials, so they are
# NOT exposed on the command line. `curl -u user:pass` is visible to any
# local user via `ps`; a --config file (600 perms) keeps them off the
# argv. Prints the temp file path when creds are set (caller passes
# --config "$f" and rm's it right after the request), else nothing.
searxng_auth_config() {
    [[ -n "${SEARXNG_USER:-}" && -n "${SEARXNG_PASS:-}" ]] || return 0
    local f
    f=$(mktemp) || return 0
    chmod 600 "$f"
    # curl reads the value as a double-quoted string, so a literal " or \
    # in the password would end the string early / eat the next char →
    # wrong credentials → silent 401. Escape backslash first, then quote.
    local u="$SEARXNG_USER" p="$SEARXNG_PASS"
    u=${u//\\/\\\\}; u=${u//\"/\\\"}
    p=${p//\\/\\\\}; p=${p//\"/\\\"}
    printf 'user = "%s:%s"\n' "$u" "$p" > "$f"
    printf '%s' "$f"
}

# Print the configured SearXNG endpoints, one per line. Prefers the
# SEARXNG_URLS list (comma- or newline-separated, for round-robin over
# several instances/IPs); falls back to the single SEARXNG_URL. Each
# entry is trimmed and its trailing slash stripped. Adding a server
# later is just one more entry in SEARXNG_URLS — no code change.
searxng_endpoints() {
    local raw="${SEARXNG_URLS:-${SEARXNG_URL:-}}"
    # `|| [[ -n "$u" ]]` so the LAST entry is processed even with no
    # trailing newline — otherwise a single SEARXNG_URL (no comma → no
    # newline) would be silently dropped.
    printf '%s' "$raw" | tr ',' '\n' | while IFS= read -r u || [[ -n "$u" ]]; do
        u=$(trim_ws "$u"); u="${u%/}"
        [[ -n "$u" ]] && printf '%s\n' "$u"
    done
}

# --- Rate-limit cooldown (per endpoint) ---
# After a 429/503 from an endpoint, skip it for SEARXNG_COOLDOWN seconds
# so sustained load (e.g. a 400-call batch) flows to the healthy IPs
# instead of hammering the throttled one. State = a tiny file per URL.
_searxng_cooldown_file() {
    printf '%s/.rl_%s' "${WEB_CACHE_DIR:-/tmp}" "$(printf '%s' "$1" | cksum | cut -d' ' -f1)"
}
searxng_in_cooldown() {   # $1=url → 0 if still cooling down
    local f; f=$(_searxng_cooldown_file "$1")
    [[ -f "$f" ]] || return 1
    local until; until=$(cat "$f" 2>/dev/null); until=${until:-0}
    (( $(date +%s) < until ))
}
searxng_mark_cooldown() { # $1=url
    mkdir -p "${WEB_CACHE_DIR:-/tmp}" 2>/dev/null
    printf '%s' "$(( $(date +%s) + ${SEARXNG_COOLDOWN:-60} ))" > "$(_searxng_cooldown_file "$1")"
}

# Query ONE SearXNG endpoint. stdout = formatted results (or "No results
# found."); return: 0 ok · 1 rate-limited (429/503) · 2 transport/other
# error (stdout = the "Error: ..." message).
_searxng_query_one() {
    local base="$1" query="$2"
    local timeout="${SEARXNG_TIMEOUT:-30}" max_chars="${MAX_WEB_CHARS:-6000}"
    local auth_cfg; auth_cfg=$(searxng_auth_config)
    local -a auth=(); [[ -n "$auth_cfg" ]] && auth=(--config "$auth_cfg")
    local body http_code curl_rc
    body=$(mktemp) || { echo "Error: mktemp failed."; return 2; }
    http_code=$(curl -sS -G --max-time "$timeout" --connect-timeout "${SEARXNG_CONNECT_TIMEOUT:-3}" "${auth[@]}" \
        -H "Accept: application/json" \
        --data-urlencode "q=$query" --data-urlencode "format=json" \
        -o "$body" -w '%{http_code}' "$base/search" 2>/dev/null)
    curl_rc=$?
    [[ -n "$auth_cfg" ]] && rm -f "$auth_cfg"
    if (( curl_rc != 0 )); then
        rm -f "$body"
        (( curl_rc == 28 )) && echo "Error: search timed out at $base." || echo "Error: cannot reach SearXNG at $base."
        return 2
    fi
    case "$http_code" in
        429|503) rm -f "$body"; return 1 ;;
        2*)      : ;;
        401)     rm -f "$body"; echo "Error: SearXNG rejected the credentials (HTTP 401). Check SEARXNG_USER / SEARXNG_PASS."; return 2 ;;
        *)       rm -f "$body"; echo "Error: SearXNG HTTP $http_code at $base."; return 2 ;;
    esac
    if ! jq -e . "$body" >/dev/null 2>&1; then
        rm -f "$body"; echo "Error: SearXNG returned non-JSON (auth challenge?)."; return 2
    fi
    local text; text=$(format_search_results < "$body"); rm -f "$body"
    [[ -z "$text" ]] && { echo "No results found."; return 0; }
    printf '%s' "$text" | utf8_truncate "$max_chars"
    return 0
}

# Preflight: is the web-search backend usable RIGHT NOW? SearXNG is an
# external service we don't control, so this lets /web be honest — say
# "no web available" up front instead of enabling the mode and silently
# returning N/A for every query. Checks EACH configured endpoint, prints
# a per-endpoint ✓/✗ line to stderr, and returns 0 if ANY is up.
web_search_available() {
    local -a urls=(); local u
    while IFS= read -r u; do urls+=("$u"); done < <(searxng_endpoints)
    if [[ ${#urls[@]} -eq 0 ]]; then
        echo "SEARXNG_URLS / SEARXNG_URL is not set." >&2
        return 1
    fi
    local timeout="${SEARXNG_PREFLIGHT_TIMEOUT:-5}"
    local ok=0 code rc auth_cfg
    local -a auth
    for u in "${urls[@]}"; do
        auth_cfg=$(searxng_auth_config)
        auth=(); [[ -n "$auth_cfg" ]] && auth=(--config "$auth_cfg")
        code=$(curl -s -o /dev/null --max-time "$timeout" --connect-timeout "${SEARXNG_CONNECT_TIMEOUT:-3}" "${auth[@]}" -G \
            --data-urlencode "q=ping" --data-urlencode "format=json" \
            -w '%{http_code}' "$u/search" 2>/dev/null)
        rc=$?
        [[ -n "$auth_cfg" ]] && rm -f "$auth_cfg"
        if (( rc != 0 )); then echo "  ✗ $u (offline/unreachable)" >&2; continue; fi
        case "$code" in
            2*)      echo "  ✓ $u" >&2; ok=1 ;;
            429|503) echo "  ✓ $u (up, currently rate-limited)" >&2; ok=1 ;;
            401)     echo "  ✗ $u (HTTP 401 — check SEARXNG_USER/PASS)" >&2 ;;
            *)       echo "  ✗ $u (HTTP $code)" >&2 ;;
        esac
    done
    (( ok == 1 )) && return 0
    return 1
}

# Query SearXNG across the configured endpoints with RANDOM round-robin +
# failover + per-endpoint rate-limit cooldown. Prints formatted results,
# "No results found.", or an "Error: ..." line. Always returns 0 —
# chati's do_web_research dispatches on the string prefix. Spreads load
# over several IPs (~1/N each) so a heavy batch multiplies the rate-limit
# ceiling; a 429'd endpoint is parked (cooldown) so traffic flows to the
# healthy ones instead of bouncing off the limited one.
web_search() {
    local query="$1"
    local -a urls=(); local u
    while IFS= read -r u; do urls+=("$u"); done < <(searxng_endpoints)
    if [[ ${#urls[@]} -eq 0 ]]; then
        echo "Error: SEARXNG_URLS / SEARXNG_URL is not configured. Set it in your .env, e.g.:"
        echo "  export SEARXNG_URLS=\"http://localhost:8890, https://cloud.damken.com/searx\""
        return 0
    fi

    local n=${#urls[@]} start=$(( RANDOM % ${#urls[@]} ))
    local i idx url out rc any_live=0 last="No results found."
    # Pass 1: random start, walk the rest; skip endpoints in cooldown.
    for (( i = 0; i < n; i++ )); do
        idx=$(( (start + i) % n )); url="${urls[$idx]}"
        searxng_in_cooldown "$url" && continue
        any_live=1
        out=$(_searxng_query_one "$url" "$query"); rc=$?
        case $rc in
            0) printf '%s' "$out"; return 0 ;;
            1) searxng_mark_cooldown "$url"; last="Error: search engine is rate-limiting this client." ;;
            2) last="$out" ;;
        esac
    done
    # Pass 2: only if EVERY endpoint was in cooldown — try them anyway
    # (better a throttled answer than none).
    if (( any_live == 0 )); then
        for (( i = 0; i < n; i++ )); do
            idx=$(( (start + i) % n )); url="${urls[$idx]}"
            out=$(_searxng_query_one "$url" "$query"); rc=$?
            case $rc in
                0) printf '%s' "$out"; return 0 ;;
                1) searxng_mark_cooldown "$url"; last="Error: search engine is rate-limiting this client." ;;
                2) last="$out" ;;
            esac
        done
    fi
    printf '%s' "$last"
}

# Run several web_search calls with BOUNDED CONCURRENCY, preserving input order.
# Args: the queries. Output: each query's result in order, separated by a NUL
# byte (read with `while IFS= read -r -d ''`). Searching a multi-query /web turn
# in parallel is the big latency win — 8 serial searches at up to 30s each
# become a few concurrent batches. Concurrency = WEB_SEARCH_CONCURRENCY
# (default 3, deliberately modest); web_search's per-endpoint cooldown +
# random round-robin keep the parallelism from hammering one instance. Raise it
# only if you run several SEARXNG_URLS. Falls back to serial if mktemp fails.
web_search_many() {
    local conc="${WEB_SEARCH_CONCURRENCY:-3}"; (( conc < 1 )) && conc=1
    local n=$# i=0 running=0 td q
    (( n == 0 )) && return 0
    if ! td=$(mktemp -d "${WEB_CACHE_DIR:-/tmp}/wsm.XXXXXX" 2>/dev/null); then
        for q in "$@"; do web_search "$q" 2>/dev/null; printf '\0'; done
        return 0
    fi
    local -a pids=()
    for q in "$@"; do
        web_search "$q" > "$td/$i.out" 2>/dev/null &
        pids+=("$!"); i=$((i+1)); running=$((running+1))
        if (( running >= conc )); then wait "${pids[@]}"; pids=(); running=0; fi
    done
    [[ ${#pids[@]} -gt 0 ]] && wait "${pids[@]}"
    for (( i = 0; i < n; i++ )); do
        cat "$td/$i.out" 2>/dev/null
        printf '\0'
    done
    rm -rf "$td"
}


# --- Query decomposition (/w) --------------------------------------------------

# Normalize raw decomposer output into clean search queries: strip list
# bullets and "1." / "1)" numbering, trim whitespace, drop comment lines
# and fragments under 4 chars, cap at $1 lines. stdin → stdout. Split out
# from decompose_query for unit testing.
#
# Numbering is only stripped when the digits are followed by "." or ")" —
# the old python version stripped ANY leading digit run, which mangled
# subjects like "3M" into "M" (chati's subject re-attach then papered
# over it).
clean_subqueries() {
    local max="$1"
    sed -E 's/^[[:space:]]*[-*•·]+[[:space:]]*//; s/^[0-9]+[.)][[:space:]]*//' \
        | awk -v max="$max" '
            { gsub(/^[ \t]+|[ \t]+$/, "") }
            length($0) >= 4 && $0 !~ /^#/ { print; if (++n >= max) exit }'
}

# Drop duplicate queries, case- and whitespace-insensitive, keeping first-seen
# order. The decomposer sometimes emits near-identical lines; searching each is
# a wasted round-trip. stdin → stdout. Original text (not the normalized key) is
# what gets printed, so the search still uses the model's phrasing.
dedup_queries() {
    awk '{
        key = tolower($0); gsub(/[[:space:]]+/, " ", key)
        sub(/^ /, "", key); sub(/ $/, "", key)
        if (key != "" && !(key in seen)) { seen[key] = 1; print }
    }'
}

# Triage: does this query need a LIVE web search, or can the model answer
# from its own knowledge? Prints "SEARCH" or "DIRECT". This is what makes
# /web smart instead of all-or-nothing — a joke, a coding question or an
# explanation answers DIRECT (no search), while prices, news, "latest" or
# recent data answer SEARCH.
#
# Bias is deliberate: ANY failure, timeout, or unclear reply → SEARCH. A
# needless search costs a few seconds; a confidently stale answer is worse.
# The model is chosen by router_model() — a small installed model when one
# is available (so the decision is near-instant), with no per-machine
# config needed; WEB_ROUTER_MODEL still overrides it.
web_query_needs_search() {
    local query="$1"
    local model
    model=$(router_model)
    local timeout="${WEB_ROUTER_TIMEOUT:-30}"

    local prompt="You are a router that decides whether a user message needs a LIVE WEB SEARCH to be answered well.

Answer SEARCH if answering needs fresh, real-time, or external facts: current events, news, weather, prices, stock/financial figures, sports scores, release dates, live status, or anything tied to 'today'/'now'/'latest'/'current', or specific recent data a language model likely does not know.

Answer DIRECT if a language model can answer from its own knowledge: jokes, creative writing, code, explanations, definitions, math, translation, rewriting or summarizing text the user gave, opinions, and general or historical knowledge.

Reply with ONLY one word: SEARCH or DIRECT.

User message: $query"

    local r
    r=$(ollama_chat_oneshot "$model" "$prompt" "$timeout") || { echo "SEARCH"; return 0; }
    # Lenient parse — only an explicit DIRECT skips the search.
    case "$(printf '%s' "$r" | tr '[:upper:]' '[:lower:]')" in
        *direct*) echo "DIRECT" ;;
        *)        echo "SEARCH" ;;
    esac
}

# Ask the model to split a user question into atomic search queries, one
# per line, up to DECOMPOSE_MAX_SUBS. $2 (optional) is a context file —
# the session prompt — that tells the decomposer WHAT to look up when the
# query itself is terse (a bare ticker). Falls back to echoing the
# original query on any failure, so /w always has something to search.
#
# DECOMPOSE_MODEL overrides the model just for this call — letting a
# small fast model split the question while a big one writes the final
# answer is often the right tradeoff. DECOMPOSE_MAX_SUBS caps how many
# searches a single question fans out into (default 8). For a big
# enumeration ("presidents of all 54 African countries") raise it, e.g.
# DECOMPOSE_MAX_SUBS=60 — it will run that many searches (slower, and
# heavier on your SearXNG), so it's opt-in rather than the default.

# Preferences for the DECOMPOSE step: mid-size models that still understand a
# domain (finance terms like "p/e", tickers, references) but load and run far
# faster than a 30B answer model. A 3B mangles "p/e de krka" into event tickets;
# the big answer model wastes ~2min cold-loading just to rewrite keywords into
# a search box. Mirrors router_model(): honor DECOMPOSE_MODEL, else the first
# installed preference, else the active model (always works, just slower).
DECOMPOSE_PREFERENCES=("llama3.1:8b" "llama3.1:8b-instruct-q8_0" "gemma4:e4b" "qwen2.5:7b")
decompose_model() {
    if [[ -n "${DECOMPOSE_MODEL:-}" ]]; then printf '%s\n' "$DECOMPOSE_MODEL"; return 0; fi
    local installed pref
    installed=$(ollama list 2>/dev/null | tail -n +2 | awk '{print $1}')
    if [[ -n "$installed" ]]; then
        for pref in "${DECOMPOSE_PREFERENCES[@]}"; do
            if printf '%s\n' "$installed" | grep -qxF "$pref"; then
                printf '%s\n' "$pref"; return 0
            fi
        done
    fi
    active_model
}

decompose_query() {
    local query="$1" context_file="${2:-}"
    local max_subs="${DECOMPOSE_MAX_SUBS:-8}"
    # A single call, but with a big model it can take 30-120s — use the
    # long streaming timeout, not the meta one.
    local timeout="${DECOMPOSE_TIMEOUT:-${OLA_CURL_TIMEOUT:-600}}"
    # Prefer an installed mid-size model over the big answer model (see
    # decompose_model); DECOMPOSE_MODEL still overrides.
    local model; model=$(decompose_model)

    local context=""
    [[ -n "$context_file" && -s "$context_file" ]] && context=$(cat "$context_file")

    local prompt
    if [[ -n "${context//[[:space:]]/}" ]]; then
        prompt="You are producing web SEARCH QUERIES (NOT full sentences, NOT questions) for the user's CURRENT request.

Use the CONTEXT below — it holds the recent conversation and/or an analysis framework. Two jobs:
(a) RESOLVE REFERENCES: if the current request points back at earlier things (\"those\", \"them\", \"it\", \"that company\", \"all of them\"), figure out from the conversation what they are, and put the concrete names into the queries — never search the literal word \"those\".
(b) If the context is an analysis framework (e.g. a stock prompt asking for ROIC, P/E, moat), look up exactly those data points.

=== CONTEXT (recent conversation and/or analysis framework) ===
$context
=== END CONTEXT ===

STRICT RULES:
1. Produce up to $max_subs concise search queries.
2. 3 to 8 keywords each. NO question marks. NO full sentences. Think like someone typing into a search box.
3. If the request centers on one clear subject (a company, a person, a ticker), include that subject in every query — verbatim, do not drop or abbreviate it (e.g. \"3M\", not \"M\").
4. Each query targets a DIFFERENT data point or a different one of the resolved items.
5. PRESERVE NAMES EXACTLY. Copy every proper noun, brand/product name, domain, username, ticker or technical term character-for-character — NEVER translate, transliterate, spell-\"correct\", or localize them (e.g. keep \"claude.ai\" as \"claude.ai\", never \"claudia\"; keep \"PostgreSQL\", never \"Postgres SQL\").
6. Respond with ONLY the queries, one per line, no numbering, no bullets, no commentary.

Example — context says the conversation is about Kenya, Uganda and Burundi, and the request is \"current presidents of those countries\":
Kenya current president 2026
Uganda current president 2026
Burundi current president 2026

User request: $query"
    else
        prompt="Break the following user question into up to $max_subs short web search queries (3-8 keywords each, NO question marks, NO full sentences — think search box, not chatbot). PRESERVE NAMES EXACTLY: copy every proper noun, brand/product name, domain, username or ticker character-for-character — never translate, transliterate or spell-\"correct\" them (e.g. keep \"claude.ai\" as \"claude.ai\", never \"claudia\"). Respond with ONLY the queries, one per line. No numbering, no bullets, no commentary. If the question is already a single concise lookup, return just the original.

Question: $query"
    fi

    local content
    if ! content=$(ollama_chat_oneshot "$model" "$prompt" "$timeout"); then
        printf '%s\n' "$query"
        return 0
    fi
    local subs
    subs=$(printf '%s\n' "$content" | clean_subqueries "$max_subs")
    # Always search the user's ORIGINAL query verbatim too, as a safety net: the
    # decomposer (a small model) sometimes mangles a proper noun / brand / domain
    # — e.g. \"claude.ai\" → \"claudia ai\" (#29). Prepend the original and dedup
    # (case-insensitively) so the real terms are searched even if a subquery
    # drifted. Capped to \$max_subs.
    {
        printf '%s\n' "$query"
        [[ -n "$subs" ]] && printf '%s\n' "$subs"
    } | awk '{ key=tolower($0); sub(/^[ \t]+/,"",key); sub(/[ \t]+$/,"",key) } NF && !seen[key]++' \
      | head -n "$max_subs"
}
