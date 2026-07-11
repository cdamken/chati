# OLA Chat - Backend & Management

Core backend for the Ollama chat system. These scripts are invoked by the parent `chati` interface to handle API communication, session management, and model utilities. **Everything in this folder is bash** — JSON work is done with inline `jq`.

## Folder Contents

- **`ola`** — Chat backend. Builds the payload with inline `jq` (per-session prompt + summary + optional agent-mode system message + sliding window; accepts both JSONL and the legacy `role: content` line format), streams tokens from the Ollama API (`$OLLAMA_API/api/chat`), appends each turn as JSONL to the active message buffer, and writes the final response to `$LAST_RESPONSE_FILE` for the caller.
- **`mola`** — Session manager. Owns the conversation files under `../conversation_histories/`.
- **`ola_model`** — Model utility. Lists installed Ollama models and switches the active one written to `$ACTIVE_MODEL_FILE`.
- **`README.md`** — This file.

## Backend Procedures

### `ola` (Communication)
1. Append the user turn as JSONL to `$MESSAGES_FILE`.
2. Build the payload with inline `jq` (per-session prompt + summary + `$OLA_EXTRA_SYSTEM` if set + last `$SLIDING_WINDOW` messages).
3. POST to Ollama with `"stream": true`.
4. Parse the NDJSON stream with `jq -j --unbuffered` (an `{"error": …}` chunk aborts via `halt_error`), clear the 🤔 glyph on the first byte, and `tee` the full text into `$LAST_RESPONSE_FILE` so the user sees tokens arrive live and the caller can read the final text from the side-channel file.
5. Append the assistant turn as JSONL using the captured text.

### `mola` (Session Management)
Subcommands:

| Command | What it does |
|---|---|
| `list` (alias `ls`) | List all sessions with message counts; marks the active one. |
| `new [name]` | Start a new session (`YYYYMMDD_HHMM_name`). Saves the current session as the `/back` target. |
| `switch <idx\|name>` | Switch to a session. Saves the current one as the `/back` target. |
| `back` | Toggle to the previously-active session (set by `new`/`switch`). |
| `rename [idx] <name>` | Rename a session, keeping its timestamp prefix. |
| `autorename [idx\|all\|all-force]` | Ask the LLM for a descriptive title. |
| `delete <idx\|name>` | Delete a session and its companions (`_prompt`, `_summary`, `_compressed_at`). |
| `compress` | Generate/refresh the session summary via the LLM. Called automatically by `chati` every `$COMPRESS_EVERY` messages. |
| `save` | Copy the active buffer back to the session file on disk. |

Companion files per session live next to the conversation file:

- `${session}_prompt` — system prompt for that session
- `${session}_summary` — LLM-generated summary used as compressed memory
- `${session}_compressed_at` — message-count marker so `maybe_compress` knows when to re-summarize

### `ola_model`
- `list` — Show installed models, highlight which is selected/running.
- `current` — Print the currently-selected model.
- `set <name|number>` — Update `$ACTIVE_MODEL_FILE`.
- `rm <model>`, `pull <model>`, `ps` — thin wrappers around `ollama`.

## Required Environment

These scripts expect the environment exported by `lib_chat.sh` (`$HISTORY_DIR`, `$ACTIVE_FILE`, `$MESSAGES_FILE`, `$LAST_RESPONSE_FILE`, `$BACK_FILE`, `$ACTIVE_MODEL_FILE`, `$OLA_CURL_TIMEOUT`, `$OLA_CURL_META_TIMEOUT`, …). The parent `chati` sources `lib_chat.sh` before invoking any of them.
