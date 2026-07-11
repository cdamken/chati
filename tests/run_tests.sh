#!/bin/bash
#==============================================================================
# Test runner — sanity checks for the chati scripts.
#==============================================================================
# Three phases, run in order:
#
#   1. Syntax + smoke. Validates every bash/python file parses and that each
#      CLI entry point responds to --help / --version with exit 0. No external
#      dependencies. Always runs.
#
#   2. Unit tests. Exercises pure helpers from lib_chat.sh and chati
#      against a SANDBOXED $BASE_DIR (mktemp). Real $HOME is never touched.
#      Always runs.
#
#   3. Integration. Round-trips through `ola` / `ollama_chat_oneshot`
#      against a real Ollama at $OLLAMA_API. Auto-skipped if `ollama_running`
#      returns false. Run with `RUN_INTEGRATION=1 ./run_tests.sh` to require it.
#
# Usage:
#   ./tests/run_tests.sh              # phases 1+2 always, phase 3 if Ollama up
#   RUN_INTEGRATION=1 ./tests/run_tests.sh   # fail if Ollama isn't reachable
#   FAST=1 ./tests/run_tests.sh       # phase 1 only (fastest)
#
# Exits 0 on all-pass, 1 if any test failed, 2 on harness error.
#==============================================================================

set -o pipefail
# Do NOT `set -e` — assertions must be allowed to fail and be counted.

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_DIR" || { echo "Can't cd to project dir"; exit 2; }

# --- Color helpers (skipped when stdout isn't a TTY) ---
if [[ -t 1 ]]; then
    C_RED=$'\033[31m'; C_GREEN=$'\033[32m'; C_YELLOW=$'\033[33m'
    C_DIM=$'\033[2m';   C_BOLD=$'\033[1m'; C_RESET=$'\033[0m'
else
    C_RED=""; C_GREEN=""; C_YELLOW=""; C_DIM=""; C_BOLD=""; C_RESET=""
fi

# --- Test harness ---
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_SKIPPED=0
CURRENT_TEST=""
FAIL_REASONS=()

phase() { printf '\n%s── %s ──%s\n' "$C_BOLD" "$1" "$C_RESET"; }

run_test() {
    local name="$1"; shift
    CURRENT_TEST="$name"
    local out
    out=$("$@" 2>&1)
    local rc=$?
    if (( rc == 0 )); then
        printf '  %s✓%s %s\n' "$C_GREEN" "$C_RESET" "$name"
        ((TESTS_PASSED++))
    else
        printf '  %s✗%s %s\n' "$C_RED" "$C_RESET" "$name"
        if [[ -n "$out" ]]; then
            printf '%s%s%s\n' "$C_DIM" "$(printf '%s\n' "$out" | sed 's/^/      /')" "$C_RESET"
        fi
        FAIL_REASONS+=("$name")
        ((TESTS_FAILED++))
    fi
}

skip_test() {
    printf '  %s○%s %s %s(%s)%s\n' "$C_YELLOW" "$C_RESET" "$1" "$C_DIM" "$2" "$C_RESET"
    ((TESTS_SKIPPED++))
}

# --- Assertions (return 0/1 so run_test can count them) ---

assert_eq() {
    local actual="$1" expected="$2" what="${3:-value}"
    if [[ "$actual" != "$expected" ]]; then
        printf '%s mismatch: expected %q, got %q\n' "$what" "$expected" "$actual" >&2
        return 1
    fi
}

assert_match() {
    local actual="$1" pattern="$2" what="${3:-value}"
    if ! [[ "$actual" =~ $pattern ]]; then
        printf '%s did not match /%s/: got %q\n' "$what" "$pattern" "$actual" >&2
        return 1
    fi
}

assert_file_exists() {
    local f="$1"
    [[ -f "$f" ]] || { printf 'expected file %q to exist\n' "$f" >&2; return 1; }
}

assert_file_absent() {
    local f="$1"
    [[ ! -e "$f" ]] || { printf 'expected %q to be absent\n' "$f" >&2; return 1; }
}

#==============================================================================
# PHASE 1 — Syntax + smoke
#==============================================================================
phase "PHASE 1: syntax + smoke"

test_bash_syntax() {
    local f
    for f in chati lib_chat.sh lib_web.sh ola_chat/ola ola_chat/mola ola_chat/ola_model ai_local/ailocal setup.sh installer/install_searxng.sh tests/run_tests.sh; do
        bash -n "$f" || { echo "$f failed bash -n"; return 1; }
    done
}
run_test "bash -n every script" test_bash_syntax

test_required_tools() {
    # The whole stack is bash + these two. No python dependency anymore.
    command -v jq >/dev/null   || { echo "jq not installed"; return 1; }
    command -v curl >/dev/null || { echo "curl not installed"; return 1; }
    # halt_error(1) in ola's stream filter needs jq >= 1.6.
    local v
    v=$(jq --version 2>/dev/null)
    case "$v" in
        jq-1.[0-5]*) echo "jq too old ($v) — need >= 1.6 for halt_error"; return 1 ;;
    esac
}
run_test "jq >= 1.6 and curl are available" test_required_tools

test_chati_help() {
    local out
    out=$(./chati --help 2>&1) || return 1
    assert_match "$out" "Usage: chati" "chati --help"
}
run_test "chati --help exits 0 with usage text" test_chati_help

test_chati_version() {
    local out
    out=$(./chati --version 2>&1) || return 1
    assert_match "$out" "chati [0-9]+\.[0-9]+" "chati --version"
}
run_test "chati --version prints a version" test_chati_version

test_mola_help() {
    local out
    out=$(./ola_chat/mola --help 2>&1) || return 1
    assert_match "$out" "Usage: mola" "mola --help"
}
run_test "mola --help exits 0" test_mola_help

test_ola_model_help() {
    local out
    out=$(./ola_chat/ola_model --help 2>&1) || return 1
    assert_match "$out" "Usage:" "ola_model --help"
}
run_test "ola_model --help exits 0" test_ola_model_help

test_ailocal_help_version() {
    local out
    out=$(./ai_local/ailocal --help 2>&1) || return 1
    assert_match "$out" "Unified AI Service Manager" "ailocal --help" || return 1
    out=$(./ai_local/ailocal --version 2>&1) || return 1
    assert_match "$out" "ailocal [0-9]+\.[0-9]+" "ailocal --version"
}
run_test "ailocal --help and --version exit 0" test_ailocal_help_version

test_ailocal_status_runs() {
    # Read-only: just pgrep checks, safe anywhere.
    local out
    out=$(./ai_local/ailocal status 2>&1) || return 1
    assert_match "$out" "Ollama:" "status output shape" \
        && assert_match "$out" "OpenWebUI:" "status output shape"
}
run_test "ailocal status reports both services" test_ailocal_status_runs

test_ailocal_verb_target_standard() {
    # The help must document the VERB [TARGET] standard and the
    # single-slot backup/restore pair; bad targets must be rejected
    # with a clear error (not fall through silently).
    local out
    out=$(./ai_local/ailocal --help 2>&1) || return 1
    assert_match "$out" "start +\[target\]" "start verb documented" || return 1
    assert_match "$out" "restart \[target\]" "restart verb documented" || return 1
    assert_match "$out" "backup" "backup documented" || return 1
    assert_match "$out" "restore \[--yes\]" "restore documented" || return 1
    if ./ai_local/ailocal start nonsense >/dev/null 2>&1; then
        echo "expected 'start nonsense' to fail" >&2
        return 1
    fi
}
run_test "ailocal follows the VERB TARGET standard" test_ailocal_verb_target_standard

test_ailocal_searxng_documented() {
    # ailocal must know the searxng target and offer the install path.
    local out; out=$(./ai_local/ailocal --help 2>&1) || return 1
    assert_match "$out" "searxng" "searxng target in help" \
        && assert_match "$out" "install_searxng" "install script referenced"
    # Unknown target still errors clearly (dispatch didn't get sloppy).
    if ./ai_local/ailocal start bogus >/dev/null 2>&1; then
        echo "start bogus should fail" >&2; return 1
    fi
}
run_test "ailocal exposes the searxng target" test_ailocal_searxng_documented

test_ollama_proc_pattern() {
    # The process-match pattern must catch ollama at a path/word boundary
    # but NOT a lookalike like "myollama serve". Eval the real value from
    # the script so the test tracks it.
    eval "$(grep '^OLLAMA_PROC=' "$PROJECT_DIR/ai_local/ailocal")"
    echo "/opt/homebrew/bin/ollama serve" | grep -qE "$OLLAMA_PROC" \
        || { echo "pattern should match the real path form" >&2; return 1; }
    echo "ollama serve" | grep -qE "$OLLAMA_PROC" \
        || { echo "pattern should match the bare form" >&2; return 1; }
    if echo "myollama serve" | grep -qE "$OLLAMA_PROC"; then
        echo "pattern wrongly matches 'myollama serve'" >&2; return 1
    fi
}
run_test "ailocal OLLAMA_PROC matches ollama, not lookalikes" test_ollama_proc_pattern

test_ola_dash_m_no_hang() {
    # `ola -m` with no value used to infinite-loop (shift 2 on 1 arg never
    # advances → re-matches -m forever). Must now exit promptly, not hang.
    "$PROJECT_DIR/ola_chat/ola" -m >/dev/null 2>&1 &
    local pid=$! i
    for i in 1 2 3 4 5 6; do kill -0 "$pid" 2>/dev/null || break; sleep 0.5; done
    if kill -0 "$pid" 2>/dev/null; then
        kill -9 "$pid" 2>/dev/null
        echo "ola -m hung (infinite loop regression)" >&2
        return 1
    fi
    wait "$pid"; (( $? != 0 ))   # should exit non-zero (the guard errored)
}
run_test "ola -m with no value errors instead of hanging" test_ola_dash_m_no_hang

test_chati_help_documents_aliases() {
    # chati's standard: full word + short alias, both shown in help.
    local out
    out=$(awk '/^show_help\(\) \{/,/^}$/' "$PROJECT_DIR/chati")
    assert_match "$out" "/talk +\(/t\)" "/talk alias" \
        && assert_match "$out" "/web +\(/w\)" "/web alias" \
        && assert_match "$out" "/agent +\(/a\)" "/agent alias" \
        && assert_match "$out" "/file +\(/f\)" "/file alias" \
        && assert_match "$out" "/batch +\(/s\)" "/batch alias"
}
run_test "chati help documents word+alias standard" test_chati_help_documents_aliases

test_chati_dispatch_has_long_forms() {
    # The dispatcher must accept BOTH forms for every aliased command.
    local dispatch
    dispatch=$(sed -n '/case "\$cmd_name" in/,/esac/p' "$PROJECT_DIR/chati")
    assert_match "$dispatch" "/file\|/f\)" "/file|/f arm" \
        && assert_match "$dispatch" "/batch\|/s\)" "/batch|/s arm" \
        && assert_match "$dispatch" "/talk\|/t\)" "/talk|/t arm" \
        && assert_match "$dispatch" "/web\|/w\)" "/web|/w arm" \
        && assert_match "$dispatch" "/agent\|/a\)" "/agent|/a arm"
}
run_test "chati dispatcher accepts long and short forms" test_chati_dispatch_has_long_forms

if [[ "${FAST:-0}" == "1" ]]; then
    phase "FAST mode: skipping phases 2 + 3"
    exit_code=0
    (( TESTS_FAILED > 0 )) && exit_code=1
    echo ""
    printf '%sResults:%s %s%d passed%s · %s%d failed%s · %s%d skipped%s\n' \
        "$C_BOLD" "$C_RESET" \
        "$C_GREEN" "$TESTS_PASSED" "$C_RESET" \
        "$C_RED" "$TESTS_FAILED" "$C_RESET" \
        "$C_YELLOW" "$TESTS_SKIPPED" "$C_RESET"
    exit $exit_code
fi

#==============================================================================
# PHASE 2 — Unit tests (sandboxed)
#==============================================================================
phase "PHASE 2: unit tests (sandboxed)"

# Build a sandbox under /tmp and rewrite the lib_chat.sh paths so nothing
# touches the real ~/chat state. The trap fires whether we exit cleanly,
# fail an assertion, or get killed.
SANDBOX=$(mktemp -d "${TMPDIR:-/tmp}/chat-tests.XXXXXX")
trap 'rm -rf "$SANDBOX" 2>/dev/null' EXIT
export BASE_DIR="$SANDBOX"
export OLA_DIR="$SANDBOX/ola_chat"
export DOCR_DIR="$SANDBOX/docr"
export HISTORY_DIR="$SANDBOX/conversation_histories"
export ACTIVE_MODEL_FILE="$SANDBOX/.active_ollama_model.txt"
export MESSAGES_FILE="$OLA_DIR/.messages.active.ola.txt"
export ACTIVE_FILE="$MESSAGES_FILE"
export PREVIOUS_FILE="$OLA_DIR/.ola_previous.txt"
export BACK_FILE="$OLA_DIR/.ola_back.txt"
export DEFAULT_SYSTEM_PROMPT="$OLA_DIR/.system_prompt.txt"
export LAST_RESPONSE_FILE="$OLA_DIR/.last_response.txt"
mkdir -p "$OLA_DIR" "$HISTORY_DIR"

# Source the lib AFTER the env overrides so the helpers see our paths.
# `active_model` etc. read from $ACTIVE_MODEL_FILE directly so this works.
source "$PROJECT_DIR/lib_chat.sh"

# --- trim_ws ---
test_trim_ws_both_sides() {
    local r; r=$(trim_ws "   hello world   ")
    assert_eq "$r" "hello world" "both-sides trim"
}
run_test "trim_ws strips leading + trailing whitespace" test_trim_ws_both_sides

test_trim_ws_already_clean() {
    local r; r=$(trim_ws "hello")
    assert_eq "$r" "hello" "no-op trim"
}
run_test "trim_ws is a no-op for clean input" test_trim_ws_already_clean

test_trim_ws_only_whitespace() {
    local r; r=$(trim_ws "     ")
    assert_eq "$r" "" "all-whitespace input"
}
run_test "trim_ws of all-whitespace returns empty" test_trim_ws_only_whitespace

# --- active_model ---
# With NO selection, active_model must return a *usable* model: one that
# appears in `ollama list`, or $DEFAULT_MODEL when nothing is installed /
# ollama is unreachable. It must NEVER return an uninstalled name while
# other models exist — that was the fresh-machine bug (default llama3.2:1b
# not present → cryptic "model not found" on the first send).
assert_model_usable() {
    local m="$1" what="${2:-active model}" installed
    installed=$(ollama list 2>/dev/null | tail -n +2 | awk 'NF{print $1}')
    if [[ -n "$installed" ]]; then
        printf '%s\n' "$installed" | grep -qxF "$m" && return 0
        printf '%s: %q is not installed while models exist\n' "$what" "$m" >&2
        return 1
    fi
    assert_eq "$m" "$DEFAULT_MODEL" "$what (no models installed → default)"
}

test_active_model_fallback() {
    rm -f "$ACTIVE_MODEL_FILE"
    assert_model_usable "$(active_model)" "no-selection fallback"
}
run_test "active_model with no selection returns a usable model" test_active_model_fallback

test_active_model_reads_file() {
    echo "gemma2:9b" > "$ACTIVE_MODEL_FILE"
    local r; r=$(active_model)
    assert_eq "$r" "gemma2:9b" "model from file"
}
run_test "active_model reads the active model file" test_active_model_reads_file

test_active_model_empty_file_falls_back() {
    : > "$ACTIVE_MODEL_FILE"   # empty file
    assert_model_usable "$(active_model)" "empty-file fallback"
}
run_test "active_model falls back on empty file" test_active_model_empty_file_falls_back

# --- expand_path ---
test_expand_path_tilde() {
    local r; r=$(expand_path "~/foo")
    assert_eq "$r" "$HOME/foo" "tilde expansion"
}
run_test "expand_path resolves leading tilde" test_expand_path_tilde

test_expand_path_escaped_space() {
    local r; r=$(expand_path 'foo\ bar')
    assert_eq "$r" "foo bar" "backslash-space → space"
}
run_test "expand_path unescapes backslash-spaces" test_expand_path_escaped_space

# --- session_msg_count ---
test_session_msg_count_missing() {
    local r; r=$(session_msg_count "$SANDBOX/does-not-exist")
    assert_eq "$r" "0" "missing file"
}
run_test "session_msg_count returns 0 for missing file" test_session_msg_count_missing

test_session_msg_count_jsonl() {
    local f="$SANDBOX/sess1"
    cat > "$f" <<'JSONL'
{"role":"user","content":"hi"}
{"role":"assistant","content":"hello"}
{"role":"user","content":"bye"}
JSONL
    local r; r=$(session_msg_count "$f")
    assert_eq "$r" "3" "JSONL count"
}
run_test "session_msg_count counts JSONL turns" test_session_msg_count_jsonl

test_session_msg_count_legacy() {
    local f="$SANDBOX/sess2"
    cat > "$f" <<'LEGACY'
user: hi
assistant: hello back
LEGACY
    local r; r=$(session_msg_count "$f")
    assert_eq "$r" "2" "legacy count"
}
run_test "session_msg_count counts legacy role: lines" test_session_msg_count_legacy

# --- remove_session_files / move_session_files ---
test_remove_session_files() {
    local base="$SANDBOX/sess-rm"
    touch "$base" "${base}_prompt" "${base}_summary" "${base}_compressed_at"
    remove_session_files "$base"
    assert_file_absent "$base" \
        && assert_file_absent "${base}_prompt" \
        && assert_file_absent "${base}_summary" \
        && assert_file_absent "${base}_compressed_at"
}
run_test "remove_session_files wipes base + 3 companions" test_remove_session_files

test_move_session_files() {
    local src="$SANDBOX/sess-mv" dst="$SANDBOX/sess-new"
    touch "$src" "${src}_prompt" "${src}_summary"   # no _compressed_at
    move_session_files "$src" "$dst"
    assert_file_exists "$dst" \
        && assert_file_exists "${dst}_prompt" \
        && assert_file_exists "${dst}_summary" \
        && assert_file_absent "${dst}_compressed_at" \
        && assert_file_absent "$src"
}
run_test "move_session_files renames base + present companions" test_move_session_files

# --- get_voice (language detection, folded in from detect_voice.sh) ---
test_voice_spanish() {
    local r; r=$(get_voice "¿Hola, cómo estás? Gracias por la ayuda con el análisis.")
    assert_eq "$r" "Paulina" "Spanish text"
}
run_test "get_voice picks Paulina for Spanish" test_voice_spanish

test_voice_english() {
    local r; r=$(get_voice "The quick brown fox jumps over the lazy dog with your thanks.")
    assert_eq "$r" "Samantha" "English text"
}
run_test "get_voice picks Samantha for English" test_voice_english

test_voice_empty_fallback() {
    local r; r=$(get_voice "")
    assert_eq "$r" "Samantha" "empty input"
}
run_test "get_voice falls back to Samantha on empty input" test_voice_empty_fallback

test_voice_russian() {
    local r; r=$(get_voice "Привет, как дела? Спасибо за помощь.")
    assert_eq "$r" "Milena" "Russian text"
}
run_test "get_voice picks Milena for Russian" test_voice_russian

test_voice_arabic() {
    local r; r=$(get_voice "مرحبا كيف حالك شكرا")
    assert_eq "$r" "Maged" "Arabic text"
}
run_test "get_voice picks Maged for Arabic" test_voice_arabic

# --- clean_subqueries (decomposer output normalization) ---
test_clean_subqueries_bullets_and_numbers() {
    local out
    out=$(printf -- '- Apple Inc ROIC\n2) Apple Inc P/E ratio\n# comment\nok\nApple growth\n' \
        | clean_subqueries 10)
    local expected="Apple Inc ROIC
Apple Inc P/E ratio
Apple growth"
    assert_eq "$out" "$expected" "bullets/numbering stripped, short+comment lines dropped"
}
run_test "clean_subqueries strips bullets, numbering, junk lines" test_clean_subqueries_bullets_and_numbers

test_clean_subqueries_keeps_digit_subjects() {
    # "3M ..." must survive — only "1." / "1)" style numbering is stripped.
    local out; out=$(printf '3M ROIC TTM 5 year\n' | clean_subqueries 4)
    assert_eq "$out" "3M ROIC TTM 5 year" "digit-prefixed subject intact"
}
run_test "clean_subqueries keeps digit-prefixed subjects like 3M" test_clean_subqueries_keeps_digit_subjects

test_clean_subqueries_caps_at_max() {
    local n; n=$(printf 'query one\nquery two\nquery three\n' | clean_subqueries 2 | wc -l | tr -d ' ')
    assert_eq "$n" "2" "line cap"
}
run_test "clean_subqueries caps output at max lines" test_clean_subqueries_caps_at_max

# --- format_search_results (SearXNG JSON → LLM text block) ---
test_format_results_fixture() {
    local out
    out=$(format_search_results <<'JSON'
{"results":[{"title":"Apple Q3","content":"Revenue up 5%","url":"https://x.com/a","engine":"ddg"}],
 "infoboxes":[{"infobox":"Apple Inc","content":"Tech company"}],
 "answers":["AAPL trades on NASDAQ"]}
JSON
)
    assert_match "$out" "Apple Q3" "result title" \
        && assert_match "$out" "\\[ddg\\] https://x.com/a" "engine+url line" \
        && assert_match "$out" "\\[infobox\\] Apple Inc" "infobox block" \
        && assert_match "$out" "\\[answer\\] AAPL trades" "answer block"
}
run_test "format_search_results renders hits, infoboxes, answers" test_format_results_fixture

test_format_results_empty() {
    local out; out=$(printf '{"results":[]}' | format_search_results)
    assert_eq "$out" "" "empty result set → empty output"
}
run_test "format_search_results yields empty for no hits" test_format_results_empty

# --- utf8_truncate (LOW: no broken trailing multibyte char to the LLM) ---
test_utf8_truncate_drops_partial_char() {
    # "café" = c a f + 2-byte é. Cutting to 4 bytes splits the é; the
    # result must be "caf" (partial char dropped), never "caf\xc3".
    local r; r=$(printf 'café' | utf8_truncate 4)
    assert_eq "$r" "caf" "partial trailing UTF-8 char dropped"
}
run_test "utf8_truncate drops a split trailing multibyte char" test_utf8_truncate_drops_partial_char

test_utf8_truncate_keeps_whole() {
    local r; r=$(printf 'café' | utf8_truncate 100)
    assert_eq "$r" "café" "under the cap → unchanged"
}
run_test "utf8_truncate leaves in-budget text intact" test_utf8_truncate_keeps_whole

# --- searxng_auth_config (creds off the argv, 600 perms) ---
test_searxng_auth_config_writes_600() {
    local f
    f=$(SEARXNG_USER=u SEARXNG_PASS=p searxng_auth_config)
    [[ -n "$f" && -f "$f" ]] || { echo "no config file produced" >&2; return 1; }
    local perms; perms=$(ls -l "$f" | cut -c1-10)
    local body; body=$(cat "$f")
    rm -f "$f"
    assert_eq "$perms" "-rw-------" "config must be 0600" \
        && assert_eq "$body" 'user = "u:p"' "curl --config user line"
}
run_test "searxng_auth_config writes a 0600 creds file (off argv)" test_searxng_auth_config_writes_600

test_searxng_auth_config_empty_without_creds() {
    local f; f=$(SEARXNG_USER="" SEARXNG_PASS="" searxng_auth_config)
    assert_eq "$f" "" "no creds → no config file"
}
run_test "searxng_auth_config yields nothing without creds" test_searxng_auth_config_empty_without_creds

# --- CHATI_INSTANCE: per-instance active state for concurrent terminals ---
# Re-source lib_chat.sh in clean subshells (state-file vars unset so the
# ${VAR:-default} recompute; BASE_DIR/OLA_DIR stay the sandbox).
test_chati_instance_isolates_state() {
    local unset_state=(-u PREVIOUS_FILE -u MESSAGES_FILE -u ACTIVE_FILE -u BACK_FILE -u LAST_RESPONSE_FILE)
    local a b
    a=$(env "${unset_state[@]}" CHATI_INSTANCE=alpha bash -c "source '$PROJECT_DIR/lib_chat.sh'; printf '%s' \"\$PREVIOUS_FILE\"")
    b=$(env "${unset_state[@]}" CHATI_INSTANCE=beta  bash -c "source '$PROJECT_DIR/lib_chat.sh'; printf '%s' \"\$PREVIOUS_FILE\"")
    [[ "$a" == *"/instances/alpha/.ola_previous.txt" ]] || { echo "alpha not isolated: $a" >&2; return 1; }
    [[ "$a" != "$b" ]] || { echo "two instances share active state" >&2; return 1; }
}
run_test "CHATI_INSTANCE isolates active state per instance" test_chati_instance_isolates_state

test_chati_instance_unset_is_backward_compatible() {
    # No CHATI_INSTANCE → state stays directly under OLA_DIR (no instances/).
    local p
    p=$(env -u PREVIOUS_FILE -u CHATI_INSTANCE bash -c "source '$PROJECT_DIR/lib_chat.sh'; printf '%s' \"\$PREVIOUS_FILE\"")
    if [[ "$p" == *"/instances/"* ]]; then
        echo "unset CHATI_INSTANCE should not use instances/: $p" >&2; return 1
    fi
}
run_test "no CHATI_INSTANCE keeps the classic shared paths" test_chati_instance_unset_is_backward_compatible

test_searxng_endpoints_single() {
    # Backward compat: a single SEARXNG_URL (no commas → no newline) must
    # still yield one endpoint, trailing slash stripped.
    local r; r=$(SEARXNG_URLS="" SEARXNG_URL="https://a.test/searx/" searxng_endpoints)
    assert_eq "$r" "https://a.test/searx" "single URL, slash stripped"
}
run_test "searxng_endpoints handles a single SEARXNG_URL" test_searxng_endpoints_single

test_searxng_endpoints_list() {
    local r; r=$(SEARXNG_URLS="http://a:1/ , http://b:2 ,http://c:3/" searxng_endpoints | tr '\n' '|')
    assert_eq "$r" "http://a:1|http://b:2|http://c:3|" "list trimmed, slashes stripped"
}
run_test "searxng_endpoints parses a comma list" test_searxng_endpoints_list

test_searxng_cooldown() {
    local u="http://cooldown.test:1"
    SEARXNG_COOLDOWN=60 searxng_mark_cooldown "$u"
    searxng_in_cooldown "$u" || { echo "should be in cooldown right after marking" >&2; return 1; }
    printf '%s' "1" > "$(_searxng_cooldown_file "$u")"   # expired (epoch 1)
    if searxng_in_cooldown "$u"; then echo "expired cooldown should read false" >&2; rm -f "$(_searxng_cooldown_file "$u")"; return 1; fi
    rm -f "$(_searxng_cooldown_file "$u")"
}
run_test "searxng cooldown marks and expires per endpoint" test_searxng_cooldown

test_searxng_auth_config_escapes_quotes() {
    # A password with " or \ must be escaped for curl's quoted config
    # value — otherwise it ends the string early → wrong creds → silent
    # 401. USER='u"x' PASS='p\a"b' → user = "u\"x:p\\a\"b".
    local f body
    f=$(SEARXNG_USER='u"x' SEARXNG_PASS='p\a"b' searxng_auth_config)
    body=$(cat "$f"); rm -f "$f"
    assert_eq "$body" 'user = "u\"x:p\\a\"b"' "quotes and backslashes escaped"
}
run_test "searxng_auth_config escapes \" and \\ in creds" test_searxng_auth_config_escapes_quotes

# --- router_model (small-model picker, no machine config) ---
test_router_model_honors_override() {
    local r; r=$(WEB_ROUTER_MODEL="my-pinned:7b" router_model)
    assert_eq "$r" "my-pinned:7b" "explicit override must win"
}
run_test "router_model honors WEB_ROUTER_MODEL override" test_router_model_honors_override

test_router_model_never_empty() {
    # With no override it must still return SOMETHING (an installed
    # preference, or the active model) — never empty.
    local r; r=$(router_model)
    [[ -n "$r" ]] || { echo "router_model returned empty" >&2; return 1; }
}
run_test "router_model always returns a model name" test_router_model_never_empty

# --- .env sourcing (per-machine config) ---
test_env_file_is_sourced() {
    # lib_chat.sh must load $BASE_DIR/.env before applying defaults, so
    # personal config (SearXNG endpoint/creds) lives outside the repo.
    # The sandbox BASE_DIR is empty, so write a marker .env and re-source.
    printf 'export SEARXNG_URL="http://marker.example:9"\n' > "$BASE_DIR/.env"
    ( source "$PROJECT_DIR/lib_chat.sh"
      [[ "$SEARXNG_URL" == "http://marker.example:9" ]] ) \
        || { echo ".env was not sourced (SEARXNG_URL not picked up)" >&2; rm -f "$BASE_DIR/.env"; return 1; }
    rm -f "$BASE_DIR/.env"
}
run_test "lib_chat.sh sources \$BASE_DIR/.env" test_env_file_is_sourced

test_searxng_url_has_no_baked_default() {
    # The repo must ship neutral — no personal endpoint baked in as the
    # default. With no .env and no env override, SEARXNG_URL stays empty.
    rm -f "$BASE_DIR/.env"
    ( unset SEARXNG_URL; source "$PROJECT_DIR/lib_chat.sh"
      [[ -z "$SEARXNG_URL" ]] ) \
        || { echo "SEARXNG_URL has a baked-in default — should be empty" >&2; return 1; }
}
run_test "no SearXNG URL baked into the repo" test_searxng_url_has_no_baked_default

# --- web_search_available preflight ---
test_web_unavailable_when_url_empty() {
    # No SEARXNG_URL → must report unavailable (return 1), deterministic
    # and offline. This is what keeps /web honest.
    if SEARXNG_URL="" web_search_available 2>/dev/null; then
        echo "expected unavailable when SEARXNG_URL is empty" >&2
        return 1
    fi
}
run_test "web_search_available is false without a URL" test_web_unavailable_when_url_empty

# --- web_query_needs_search router (failure-safe default) ---
test_router_defaults_to_search() {
    # The critical safety property: on ANY failure (here, a model that
    # cannot exist), the router must default to SEARCH — never silently
    # skip the web for a query that might have needed it. Deterministic
    # regardless of whether Ollama is up (bad model / no daemon both
    # make ollama_chat_oneshot fail fast).
    local r
    r=$(WEB_ROUTER_MODEL="no-such-model-xyz:0b" WEB_ROUTER_TIMEOUT=5 \
        web_query_needs_search "anything at all")
    assert_eq "$r" "SEARCH" "failure must default to SEARCH"
}
run_test "web_query_needs_search defaults to SEARCH on failure" test_router_defaults_to_search

# --- ollama_running probe ---
test_ollama_running_returns_boolean() {
    if ollama_running; then
        : # truthy is valid
    else
        : # falsy is valid
    fi
    # The point: it must not error out, just return a status.
}
run_test "ollama_running returns 0 or 1, never errors" test_ollama_running_returns_boolean

# --- chati pure helpers (sourced via eval after the lib is loaded) ---
# We extract specific functions from chati instead of sourcing the whole
# file (which would trigger the REPL).
eval "$(awk '/^normalize_for_decomp\(\) \{/,/^}$/' "$PROJECT_DIR/chati")"
eval "$(awk '/^extract_subject\(\) \{/,/^}$/' "$PROJECT_DIR/chati")"
eval "$(awk '/^agent_capability_prompt\(\) \{/,/^}$/' "$PROJECT_DIR/chati")"
eval "$(awk '/^extract_exec_cmd\(\) \{/,/^}$/' "$PROJECT_DIR/chati")"
eval "$(awk '/^agent_confirmed\(\) \{/,/^}$/' "$PROJECT_DIR/chati")"
eval "$(awk '/^macro_fola\(\) \{/,/^}$/' "$PROJECT_DIR/chati")"
eval "$(awk '/^ocr_is_ocrable\(\) \{/,/^}$/' "$PROJECT_DIR/chati")"
eval "$(awk '/^ocr_collect_files\(\) \{/,/^}$/' "$PROJECT_DIR/chati")"

# --- ocr_collect_files (file / directory / glob) ---
test_ocr_collect_single_file() {
    local img="$SANDBOX/scan.png"; : > "$img"
    local r; r=$(ocr_collect_files "$img")
    assert_eq "$r" "$img" "single file passthrough"
}
run_test "ocr_collect_files accepts a single file" test_ocr_collect_single_file

test_ocr_collect_directory() {
    # A folder with mixed contents → only the image/PDF files, sorted.
    local d="$SANDBOX/ocrdir"; mkdir -p "$d"
    : > "$d/a.jpg"; : > "$d/b.pdf"; : > "$d/notes.txt"; : > "$d/c.png"
    local r; r=$(ocr_collect_files "$d")
    local expected="$d/a.jpg
$d/b.pdf
$d/c.png"
    assert_eq "$r" "$expected" "directory → image/pdf files only (txt excluded)"
}
run_test "ocr_collect_files gathers OCR-able files from a directory" test_ocr_collect_directory

test_ocr_collect_empty_dir() {
    local d="$SANDBOX/emptydir"; mkdir -p "$d"; : > "$d/readme.txt"
    local r; r=$(ocr_collect_files "$d")
    assert_eq "$r" "" "no images/pdf → empty"
}
run_test "ocr_collect_files returns nothing for a dir with no images" test_ocr_collect_empty_dir

test_ocr_collect_glob() {
    local d="$SANDBOX/globdir"; mkdir -p "$d"
    : > "$d/one.jpg"; : > "$d/two.jpg"; : > "$d/skip.txt"
    local n; n=$(ocr_collect_files "$d/*.jpg" | wc -l | tr -d ' ')
    assert_eq "$n" "2" "glob expands to the two jpgs"
}
run_test "ocr_collect_files expands a glob" test_ocr_collect_glob

test_ocr_collect_missing() {
    local r; r=$(ocr_collect_files "$SANDBOX/does-not-exist.png")
    assert_eq "$r" "" "missing path → empty"
}
run_test "ocr_collect_files returns nothing for a missing path" test_ocr_collect_missing

test_normalize_for_decomp_arrow() {
    local r; r=$(normalize_for_decomp "3M <--> US88579Y1010")
    assert_eq "$r" "3M US88579Y1010" "arrow merge"
}
run_test "normalize_for_decomp merges 'Name <--> ID'" test_normalize_for_decomp_arrow

test_normalize_for_decomp_passthrough() {
    local r; r=$(normalize_for_decomp "plain question")
    assert_eq "$r" "plain question" "free-form passthrough"
}
run_test "normalize_for_decomp passes free-form text through" test_normalize_for_decomp_passthrough

test_extract_subject_arrow() {
    local r; r=$(extract_subject "Apple Inc <--> US0378331005")
    assert_eq "$r" "Apple Inc" "subject left of arrow"
}
run_test "extract_subject grabs the left side of '<-->'" test_extract_subject_arrow

test_extract_subject_no_arrow() {
    local r; r=$(extract_subject "just a question")
    assert_eq "$r" "" "no arrow → empty"
}
run_test "extract_subject returns empty on free-form text" test_extract_subject_no_arrow

test_agent_prompt_shape() {
    local r; r=$(agent_capability_prompt)
    assert_match "$r" "RUNTIME HARNESS OVERRIDE" "header line present" \
        && assert_match "$r" "\\[EXEC:" "EXEC tool format present" \
        && assert_match "$r" "find ~ -maxdepth" "few-shot example present"
}
run_test "agent_capability_prompt contains the required sections" test_agent_prompt_shape

# --- extract_exec_cmd ---
test_exec_simple() {
    local r; r=$(extract_exec_cmd "[EXEC: ls -la ~]")
    assert_eq "$r" "ls -la ~" "simple command"
}
run_test "extract_exec_cmd parses a bare EXEC line" test_exec_simple

test_exec_with_prose() {
    local response="I'll list your home directory.
[EXEC: ls -la ~]
Let me know if you want [more detail] afterwards."
    local r; r=$(extract_exec_cmd "$response")
    assert_eq "$r" "ls -la ~" "prose with brackets after the call must not leak in"
}
run_test "extract_exec_cmd ignores brackets on other lines" test_exec_with_prose

test_exec_inner_brackets() {
    local r; r=$(extract_exec_cmd "[EXEC: [[ -f ~/x ]] && echo yes]")
    assert_eq "$r" "[[ -f ~/x ]] && echo yes" "inner [[ ]] preserved"
}
run_test "extract_exec_cmd keeps inner [[ ]] intact" test_exec_inner_brackets

test_exec_none() {
    if extract_exec_cmd "Just a normal answer, no tool call." >/dev/null; then
        echo "expected exit 1 for a response without EXEC" >&2
        return 1
    fi
}
run_test "extract_exec_cmd returns 1 when there is no call" test_exec_none

# --- SECURITY: parser end-anchoring (HIGH #2/#3) ---
test_exec_inner_bracket_not_corrupted() {
    # A legit command whose own text contains ']' must survive intact —
    # the old %]* cut it at the last bracket and ran something different.
    local r; r=$(extract_exec_cmd "[EXEC: test -d ~/d] || mkdir ~/d]")
    assert_eq "$r" "test -d ~/d] || mkdir ~/d" "inner ']' preserved, not truncated"
}
run_test "extract_exec_cmd does not corrupt commands with inner ']'" test_exec_inner_bracket_not_corrupted

test_exec_rejects_unterminated() {
    # A line that doesn't end with the closing bracket isn't a well-formed
    # call — reject it rather than run a half-parsed command.
    if extract_exec_cmd "[EXEC: ls ~ and then some trailing prose" >/dev/null; then
        echo "expected rejection of a line without a closing ']'" >&2
        return 1
    fi
}
run_test "extract_exec_cmd rejects a call with no closing bracket" test_exec_rejects_unterminated

# --- SECURITY: execution gate deny-by-default (HIGH #1) ---
test_gate_denies_by_default() {
    # The single most important property: anything that isn't an explicit
    # yes must NOT execute. Empty (reflex Enter), n, no, junk → denied.
    local bad
    for bad in "" " " "n" "N" "no" "nope" "q" "x" "yn" "sure"; do
        if agent_confirmed "$bad"; then
            echo "gate wrongly APPROVED input: [$bad]" >&2
            return 1
        fi
    done
}
run_test "agent gate denies by default (empty/n/junk never runs)" test_gate_denies_by_default

test_gate_accepts_explicit_yes() {
    local good
    for good in "y" "Y" "yes" "YES" "Yes"; do
        if ! agent_confirmed "$good"; then
            echo "gate wrongly DENIED affirmative: [$good]" >&2
            return 1
        fi
    done
}
run_test "agent gate accepts explicit y/Y/yes" test_gate_accepts_explicit_yes

# --- macro_fola (send_and_capture stubbed) ---
test_macro_fola_real_newlines() {
    # Stub the dispatcher: capture the composed message instead of
    # calling ola.
    local captured=""
    send_and_capture() { captured="$1"; }
    local f="$SANDBOX/fola-input.txt"
    printf 'line one\nline two\n' > "$f"
    macro_fola "$f" "Summarize this"
    unset -f send_and_capture
    # The header and the content must be separated by REAL newlines,
    # not the literal characters backslash-n.
    case "$captured" in
        *'\n'*) echo "message contains literal backslash-n" >&2; return 1 ;;
    esac
    assert_match "$captured" "Summarize this:" "instruction present" \
        && assert_match "$captured" "line one" "file content present"
}
run_test "macro_fola composes real newlines (no literal \\n)" test_macro_fola_real_newlines

# --- mola CLI subcommands (sandboxed) ---
# Reset the active buffer + previous file for these tests.
: > "$MESSAGES_FILE"; : > "$PREVIOUS_FILE"; : > "$BACK_FILE"
rm -rf "$HISTORY_DIR"; mkdir -p "$HISTORY_DIR"

test_mola_new() {
    "$PROJECT_DIR/ola_chat/mola" new "unit_test_session" >/dev/null
    local active; active=$(cat "$PREVIOUS_FILE")
    assert_match "$active" "^[0-9]{8}_[0-9]{4}_unit_test_session$" "active session name shape"
}
run_test "mola new creates a timestamped session" test_mola_new

test_mola_list_shows_active() {
    local out; out=$("$PROJECT_DIR/ola_chat/mola" list)
    assert_match "$out" "\\[ACTIVE\\]" "active marker"
}
run_test "mola list marks the active session" test_mola_list_shows_active

test_mola_save_no_active_session() {
    # With an empty PREVIOUS_FILE, save must be a clean no-op — the old
    # code degenerated into `cp file $HISTORY_DIR/` ("is a directory").
    # Save/restore the active-session pointer so later tests still see it.
    local saved_prev; saved_prev=$(cat "$PREVIOUS_FILE" 2>/dev/null)
    : > "$PREVIOUS_FILE"
    local rc=0
    "$PROJECT_DIR/ola_chat/mola" save >/dev/null 2>&1 || rc=1
    printf '%s' "$saved_prev" > "$PREVIOUS_FILE"
    return $rc
}
run_test "mola save is a no-op without an active session" test_mola_save_no_active_session

test_mola_save_then_delete() {
    # Put a fake user turn into the active buffer and save it.
    echo '{"role":"user","content":"hello"}' >> "$MESSAGES_FILE"
    "$PROJECT_DIR/ola_chat/mola" save >/dev/null
    local active; active=$(cat "$PREVIOUS_FILE")
    assert_file_exists "$HISTORY_DIR/$active"

    # Switch away so we can delete the original.
    "$PROJECT_DIR/ola_chat/mola" new "second" >/dev/null
    # `mola delete` requires interactive y/N; pipe "y\n".
    yes | "$PROJECT_DIR/ola_chat/mola" delete "$active" >/dev/null 2>&1
    assert_file_absent "$HISTORY_DIR/$active"
}
run_test "mola save + delete round-trip" test_mola_save_then_delete

test_mola_switch_rejects_traversal() {
    # /switch must not accept a path-traversal name (would read an
    # arbitrary file into the active buffer + poison PREVIOUS_FILE).
    if "$PROJECT_DIR/ola_chat/mola" switch "../../etc/hosts" >/dev/null 2>&1; then
        echo "traversal /switch should have been rejected" >&2; return 1
    fi
}
run_test "mola switch rejects path traversal" test_mola_switch_rejects_traversal

test_mola_delete_rejects_traversal() {
    # /delete must not accept a traversal name (would rm an arbitrary
    # file + companions after the y/N confirm).
    if yes | "$PROJECT_DIR/ola_chat/mola" delete "../../etc/hosts" >/dev/null 2>&1; then
        echo "traversal /delete should have been rejected" >&2; return 1
    fi
}
run_test "mola delete rejects path traversal" test_mola_delete_rejects_traversal

#==============================================================================
# PHASE 3 — Integration (needs Ollama)
#==============================================================================
phase "PHASE 3: integration (needs Ollama)"

if ! ollama_running; then
    if [[ "${RUN_INTEGRATION:-0}" == "1" ]]; then
        echo "  ${C_RED}Integration required but Ollama is not running at $OLLAMA_API${C_RESET}"
        ((TESTS_FAILED++))
    else
        skip_test "ollama_chat_oneshot round-trip" "Ollama not running"
        skip_test "ola stream end-to-end"           "Ollama not running"
    fi
else
    # Pick a real installed model to exercise the chat round-trip. Caller
    # can pin via TEST_MODEL; otherwise take the first installed model that
    # is NOT an embedding model — bge-*/nomic-embed/*-embed can't chat and
    # return an empty response, which would fail these tests spuriously.
    TEST_MODEL="${TEST_MODEL:-$(ollama list 2>/dev/null | awk 'NR>1 {print $1}' \
        | grep -viE 'embed|^bge-' | head -n1)}"
    if [[ -z "$TEST_MODEL" ]]; then
        skip_test "ollama_chat_oneshot round-trip" "no models installed"
        skip_test "ola stream end-to-end"           "no models installed"
    else
        echo "  ${C_DIM}(using TEST_MODEL=$TEST_MODEL)${C_RESET}"
        # Big models can take 30-90s on cold start; bump the meta timeout.
        export OLA_CURL_META_TIMEOUT="${OLA_CURL_META_TIMEOUT_TEST:-180}"

        test_oneshot_roundtrip() {
            # This validates the TRANSPORT (curl + jq plumbing returns the
            # assistant's content), not the model's instruction-following —
            # small models routinely ignore "reply with exactly one word",
            # which made the old contains-PONG assertion flaky.
            local r; r=$(ollama_chat_oneshot "$TEST_MODEL" "Say hello.")
            [[ -n "$r" ]] || { echo "empty response from $TEST_MODEL" >&2; return 1; }
        }
        run_test "ollama_chat_oneshot returns assistant content" test_oneshot_roundtrip

        test_ola_stream() {
            # Pin the model for this call so we don't depend on what
            # active_model returns from the sandboxed ACTIVE_MODEL_FILE.
            : > "$LAST_RESPONSE_FILE"
            "$PROJECT_DIR/ola_chat/ola" -m "$TEST_MODEL" "Say hi in one word." \
                >/dev/null 2>&1 || return 1
            [[ -s "$LAST_RESPONSE_FILE" ]] || { echo "LAST_RESPONSE_FILE is empty"; return 1; }
        }
        run_test "ola populates LAST_RESPONSE_FILE" test_ola_stream
    fi
fi

#==============================================================================
# Results
#==============================================================================
echo ""
printf '%sResults:%s %s%d passed%s · %s%d failed%s · %s%d skipped%s\n' \
    "$C_BOLD" "$C_RESET" \
    "$C_GREEN" "$TESTS_PASSED" "$C_RESET" \
    "$C_RED" "$TESTS_FAILED" "$C_RESET" \
    "$C_YELLOW" "$TESTS_SKIPPED" "$C_RESET"

if (( TESTS_FAILED > 0 )); then
    echo ""
    echo "${C_RED}Failed tests:${C_RESET}"
    for r in "${FAIL_REASONS[@]}"; do
        echo "  - $r"
    done
    exit 1
fi
exit 0
