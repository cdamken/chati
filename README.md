# chati

An Ollama-centric, high-performance chat interface for the command line, with local AI service management and OpenWebUI integration.

![version](https://img.shields.io/badge/version-1.2.1-blue) ![license](https://img.shields.io/badge/license-MIT-green) ![platform](https://img.shields.io/badge/platform-macOS-lightgrey)

## ⚡ Quick Start (macOS)

**`./setup.sh` does everything** — installs all dependencies, Ollama + a chat model, the OpenWebUI browser app, and local web search (SearXNG), and starts everything. Two steps to get the code to it:

> **Prerequisite — Homebrew.** If `brew --version` fails, install it, then activate it in the current terminal (otherwise `brew` stays "command not found" until you open a new one):
> ```bash
> /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
> ```
> ```bash
> eval "$(/opt/homebrew/bin/brew shellenv)"
> ```

**1. Clone the repo:**

```bash
git clone https://github.com/cdamken/chati ~/chat
cd ~/chat
```

**2. Run the installer:**

```bash
./setup.sh
```

**Done.** `setup.sh` installed and started everything. Now:

- 💬 **CLI chat:** just run `chati` (setup links it onto your PATH, so it works from any directory — or `./chati` from the repo)
- 🌐 **Browser UI:** already running at **http://127.0.0.1:8888**
- 🔎 **Web search:** local SearXNG is running and wired in — toggle it inside chati with `/web`

> **The chat model is auto-picked from your Mac's memory** (Apple Silicon shares RAM between CPU and GPU): ≥48 GB → `llama3.3:70b`, 32–47 GB → `gemma4:26b`, 16–31 GB → `llama3.1:8b-instruct-q8_0`, <16 GB → `gemma3:4b`. Force any model with `./setup.sh --model NAME`, or switch live in chati with `/model`. A very large auto-pick (the 70B, ~42 GB) asks before downloading.
>
> **CLI only?** `./setup.sh --minimal` skips the browser app and SearXNG. **Undo everything?** `./setup.sh --remove-all` (see [Uninstalling](#uninstalling-remove-all)).
>
> **Paste one command at a time.** macOS zsh treats `#` and stray quotes literally, so pasting explanatory text can strand you at a `quote>` prompt — if that happens, press **Ctrl-C** and paste just the command. Every block above is comment-free. More detail and options in [Fresh Mac Setup](#fresh-mac-setup) below.

## Philosophy: bash as the conductor

The point of this project is to show how far a language from 1989 gets when it orchestrates the right specialized tools. **~4,400 lines of bash** drive the whole experience — streaming LLM chat, RAG web research, session memory with LLM compression, TTS, OCR, an agent mode with supervised shell execution — and every hard sub-problem is delegated to a battle-tested Unix tool that does one thing well:

| Tool | What bash delegates to it |
|---|---|
| `jq` | Every JSON job: chat payload assembly, NDJSON stream parsing, SearXNG result formatting |
| `curl` | Every HTTP job: streaming chat with Ollama, one-shot meta calls, authenticated search queries |
| `lynx` | Webpage → readable text (`/url`) |
| `say` (macOS) | Text-to-speech with word-by-word color highlighting (`/t`) |
| `tesseract` + `imagemagick` | The OCR pipeline behind `/ocr` |
| `sed` / `awk` / `grep` | Text munging everywhere, including statistical language detection for voice selection |
| `ollama` | The actual LLM inference |

The rule is **bash first, tools proudly visible** — not "no other languages". When a task genuinely outgrows bash + a tool, a helper in another language is fine: `docr`'s PDF graphics engine is Groovy because that's where the right library lives. The chat path itself needs nothing beyond bash + `jq` + `curl` + `lynx`.

## Architecture

This project provides a robust terminal-based chat experience with session management, OCR capabilities, automated batch processing, and a unified manager for local AI services (Ollama + OpenWebUI).

### Core Components

The chat stack is **pure bash** — the only runtime dependencies are `jq`, `curl`, and `lynx` (plus macOS built-ins like `say`). There is no Python in the chat path.

- **`chati`**: The main interactive CLI loop (v1.6.2).
- **`ai_local/ailocal`**: Unified local AI service manager — start/stop Ollama and OpenWebUI, upgrade both, and manage OpenWebUI backups.
- **`ola_chat/`**: Backend logic for Ollama integration (all bash).
  - `ola`: Streaming chat backend — builds the payload and parses the token stream with inline `jq`.
  - `mola`: Advanced session manager (rename, autorename, delete, etc.).
  - `ola_model`: Model management (pull, switch, list).
- **`docr/`**: Specialized OCR script with automatic quality profile detection (watermarks, shadows, columns). Uses a Groovy helper for PDF graphics.
- **`lib_chat.sh`**: Shared configuration + core helpers (model selection, session files, voice detection, one-shot Ollama calls).
- **`lib_web.sh`**: Web research helpers — SearXNG search, URL fetch via lynx, LLM query decomposition. All `curl` + `jq`.
- **Web search backend**: a self-hosted **SearXNG** metasearch instance — see [SEARXNG_SETUP.md](installer/SEARXNG_SETUP.md) for the full server-side install and maintenance playbook. `/w` and the decomposition-RAG pipeline talk to it instead of scraping DuckDuckGo (which rate-limits aggressively).

## Fresh Mac Setup

**Three steps.** Install Homebrew → clone → run `setup.sh`. Everything else (all packages, starting Ollama, pulling a first model, permissions, OpenWebUI, SearXNG) is handled by the one installer, which is idempotent — safe to re-run any time.

### 1. Install Homebrew

**Only if `brew --version` fails**, install Homebrew:

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

**Then activate it in this terminal** — the installer only adds `brew` to the PATH of *new* terminals, so in the current one `brew` is "command not found" until you either open a new terminal window or run:

```bash
eval "$(/opt/homebrew/bin/brew shellenv)"
```

(On older Intel Macs the path is `/usr/local/bin/brew` instead of `/opt/homebrew/bin/brew`. Skip step 1 entirely if `brew --version` already works.)

> **Copy-paste tip (important on macOS):** paste only the command itself, not the surrounding text. macOS's zsh does **not** treat `#` as a comment when typed interactively, so pasting a line that includes a trailing `# …` note — or any stray quote — can leave the shell stuck at a `quote>` / `dquote>` prompt waiting for a closing quote. The **setup commands in this section are comment-free** so they paste cleanly. In the reference sections further down, paste the command up to the `#` only. If you ever land on `quote>`, press **Ctrl-C** and try again with just the command.

### 2. Clone the code

```bash
git clone https://github.com/cdamken/chati ~/chat
cd ~/chat
```

> The folder does **not** have to be `~/chat` — every script resolves paths relative to its own location, so any name/location works (`~/chat` is just the convention). If it already exists as an older copy, see [Updating to the latest version](#updating-to-the-latest-version) below instead of re-cloning.

### 3. Run the installer

```bash
./setup.sh
```

That single command does **everything**, checking each step and printing a clear message on any problem: installs Homebrew (if missing), all packages from [`installer/Brewfile`](installer/Brewfile), starts Ollama, pulls a default chat model, sets file permissions, links `chati` onto your PATH, installs + starts the **OpenWebUI** browser app at `http://127.0.0.1:8888`, and installs + starts a local **SearXNG** for `/web` (wiring it into `.env`). Re-running it is safe (idempotent).

Options (add any of these to the command above):

| Option | Effect |
|---|---|
| `--minimal` | CLI only — skip **both** OpenWebUI and SearXNG (no Python/uv install) |
| `--no-webui` | skip OpenWebUI only |
| `--no-searxng` | skip the local SearXNG only |
| `--model NAME` | force a specific chat model, skipping the RAM-based auto-pick (e.g. `--model gemma3:4b`) |
| `--no-pull` | skip the model download (you'll pull one yourself) |
| `--remove-all` | **uninstall** everything setup installed (see [Uninstalling](#uninstalling-remove-all)) |
| `--help` | full option list |

| Package (installed by setup) | Used for |
|---|---|
| `ollama` | Local LLM inference server |
| `jq` | JSON processing in chat and service scripts |
| `curl` | API calls to Ollama and health checks |
| `lynx` | Terminal web browser for URL fetching (`/url`) |
| `imagemagick` | Image preprocessing for OCR (`magick` command) |
| `tesseract` / `tesseract-lang` | OCR engine + language packs |
| `groovy` / `ghostscript` | `docr`'s PDF graphics engine (OCR pipeline) |
| `uv` / `python@3.11` | **OpenWebUI only** — the chat stack itself is pure bash + jq + curl |

> macOS built-ins used by the scripts (`say`, `open`, `pgrep`, `pkill`, `nohup`) require no installation.

### 4. Run chati

`setup.sh` symlinks `chati` onto your PATH, so from any directory:

```bash
chati
```

(Or `./chati` from inside the repo.)

> **Model note:** `setup.sh` **auto-selects the chat model from your unified memory** and points chati at it:
>
> | Unified RAM | Model | Size |
> |---|---|---|
> | ≥ 48 GB | `llama3.3:70b` (Q4) | ~42 GB |
> | 32–47 GB | `gemma4:26b` | ~17 GB |
> | 16–31 GB | `llama3.1:8b-instruct-q8_0` | ~8.5 GB |
> | < 16 GB | `gemma3:4b` | ~3.3 GB |
>
> Force a specific one with `./setup.sh --model NAME`. If the configured model isn't installed (e.g. after switching machines), chati **auto-falls-back** to an installed model instead of failing every message — pick any model anytime with `/model`. For a faster `/web` triage router, also pull a small model: `ollama pull llama3.2:3b`.

### 5. OpenWebUI — browser UI on top of Ollama

`setup.sh` already installed and started this for you (unless you used `--minimal`) — open **http://127.0.0.1:8888**. It runs **login-less** (`WEBUI_AUTH=False`) since it's a local single-user instance, and its built-in web search is auto-wired to the local SearXNG. To require login instead, start it with `WEBUI_AUTH=True` (decide before first boot — OpenWebUI blocks turning auth back on once its DB exists). If you skipped it and want it later:

```bash
./ai_local/ailocal upgrade webui --force
./ai_local/ailocal start
```

The first line installs OpenWebUI into `~/openwebui/.venv`; the second starts Ollama + OpenWebUI and opens `http://127.0.0.1:8888`.

## Updating to the latest version

There are **two independent things** to keep current — don't confuse them:

**1. chati itself (the code)** — plain `git`:

```bash
cd ~/chat
git pull
```

Your config and chats are safe: `.env` and `conversation_histories/` are gitignored, so `git pull` never touches them. If a very old checkout refuses to pull cleanly, force it to match the repo (this only discards local *code* edits, not your data):

```bash
git reset --hard origin/main
```

No build step — the scripts run straight from the checkout, so you're on the new version the moment the pull finishes.

**2. Ollama and OpenWebUI (the services, not this code)** — via `ailocal`:

```bash
./ai_local/ailocal upgrade ollama   # Ollama via Homebrew + refresh models (auto-restarts)
./ai_local/ailocal upgrade webui    # OpenWebUI via uv
./ai_local/ailocal upgrade all      # both
```

## Uninstalling (`--remove-all`)

To tear the whole install back down — handy for testing a clean install, or moving on:

```bash
./setup.sh --remove-all
```

It lists exactly what it will delete and asks for confirmation (add `--yes` to skip the prompt). It removes: OpenWebUI (`~/openwebui`), the local SearXNG (`~/searxng`), logs (`~/logs`), the `chati` PATH link, **all pulled Ollama models**, and this repo's local state (`.env`, `.active_ollama_model.txt`, `.web_cache`, `conversation_histories/`, `ola_chat/instances/`).

It deliberately **keeps Homebrew and its packages** (`jq`, `curl`, `ollama`, `tesseract`, …) — they're shared with the rest of your system, so removing them is out of scope. It also leaves the repo code itself. Re-install anytime with `./setup.sh`.

> Only the repo checkout and your Homebrew toolchain survive — everything the installer created is gone. This is the teardown half of an install/uninstall test cycle: `./setup.sh` → use it → `./setup.sh --remove-all`.

## AI Local Service Manager (`ai_local/ailocal`)

Manages Ollama and OpenWebUI as local services.

> `setup.sh` symlinks `ailocal` onto your PATH, so you can run **`ailocal …`** from any directory. The `./ai_local/ailocal …` form used in the examples below is equivalent (and works even without the PATH link).

### Dependencies

- `ollama` (via Homebrew)
- `uv` + `python3.11` (for OpenWebUI)
- `curl`, `jq`

### Service Management

The CLI follows a `VERB [TARGET]` standard (target: `ollama` | `webui` | `all`, default `all`). The pre-2.1 fused forms (`startwebui`, `stopall`, `list-backups`, …) still work as compatibility aliases.

```bash
./ai_local/ailocal status               # Show Ollama and OpenWebUI status
./ai_local/ailocal start                # Start Ollama then OpenWebUI
./ai_local/ailocal start ollama         # Start Ollama only
./ai_local/ailocal start webui          # Start OpenWebUI (auto-starts Ollama if needed)
./ai_local/ailocal stop                 # Stop both services
./ai_local/ailocal stop webui           # Stop OpenWebUI only
./ai_local/ailocal restart ollama       # bounce Ollama (required after brew upgrade ollama)
```

OpenWebUI runs at `http://127.0.0.1:8888` and opens automatically in the browser on start.

### Upgrading

Every `upgrade webui` **snapshots the current state first** (into the single backup slot). If the result misbehaves, `./ai_local/ailocal restore` brings back the pre-upgrade state — that's the whole recovery story.

```bash
./ai_local/ailocal upgrade ollama              # Upgrade Ollama via Homebrew + refresh all models (auto-restarts the service)
./ai_local/ailocal upgrade webui               # Upgrade OpenWebUI via uv (reports version before → after)
./ai_local/ailocal upgrade webui --force       # Reinstall the venv from scratch (data lives outside, stays safe)
./ai_local/ailocal upgrade all                 # Upgrade both
```

> **Note:** `ailocal` exports `DATA_DIR=~/openwebui/data` — the variable OpenWebUI actually reads — so the database lives **outside** the venv and survives `--force` reinstalls. (For over a year the script exported `WEBUI_DATA_DIR`, which OpenWebUI ignores; data silently lived inside the venv and died with every force-reinstall.) The plain upgrade prints the installed version before/after so a no-op upgrade is visible instead of silently "successful".

> **Note:** `upgrade ollama` restarts the service automatically after the brew upgrade. A server started before the upgrade spawns the new runner binary with old flags and every model load fails with "unknown runner engine" — if you upgrade ollama by hand, run `./ai_local/ailocal restart ollama` afterwards.

Environment knobs: `WEBUI_START_TIMEOUT` (default 180s — first boot after an upgrade migrates the DB and can be slow), `AILOCAL_NO_OPEN` (skip auto-opening the browser).

> **Note:** `upgrade ollama` requires `ollama` to be in PATH. If you installed it as a Mac app rather than via Homebrew, ensure `/usr/local/bin/ollama` or the app's binary is on your `$PATH`.

> **Note:** `upgrade webui` requires `uv` to be installed. Install with `brew install uv`. It manages a Python 3.11 virtualenv at `~/openwebui/.venv`.

### Backup & Restore

One backup slot, by design: it always holds the state before the last upgrade (or the last manual `backup`). No backup zoo to curate — upgrade replaces it, restore goes back to it.

```bash
./ai_local/ailocal backup                      # Snapshot now, replacing the previous one
./ai_local/ailocal restore                     # Go back to the snapshot (asks for confirmation)
./ai_local/ailocal restore --yes               # Same, non-interactive
./ai_local/ailocal status                      # shows the snapshot age and size
```

The slot lives at `~/openwebui_backups/previous/` and includes the database (consistent `sqlite3 .backup` snapshot), the data directory and the secret key.

### Logs

| Service    | Log file                        |
|------------|---------------------------------|
| Ollama     | `~/logs/ollama.log`             |
| OpenWebUI  | `~/logs/webui.log`              |
| Upgrades   | `~/logs/ailocal_upgrade.log`    |
| General    | `~/logs/ailocal.log`            |
| chati   | `~/logs/chati.log`           |

---

## Configuration (environment variables)

All tunables are exported by `lib_chat.sh` with sane defaults; override
any of them in `~/.zshrc` if needed.

### Web search (SearXNG)

SearXNG is an **external service you point at** — it is not bundled, and there is **no default URL baked into the repo** (so a clone never talks to someone else's server). Configure your own instance in `~/chat/.env`:

```bash
cp .env.example .env        # then edit .env
```

| Variable        | Default            | Purpose                                          |
|-----------------|--------------------|--------------------------------------------------|
| `SEARXNG_URL`   | empty (unset)      | Base URL of **your** SearXNG (single instance)   |
| `SEARXNG_URLS`  | empty (unset)      | **Several** endpoints, comma-separated → round-robin across them (takes precedence over `SEARXNG_URL`) |
| `SEARXNG_USER`  | unset              | Basic Auth username (only if your instance needs it) |
| `SEARXNG_PASS`  | unset              | Basic Auth password (only if your instance needs it) |
| `SEARXNG_COOLDOWN` | `60`            | Seconds to park an endpoint after a `429`/`503`  |
| `SEARXNG_CONNECT_TIMEOUT` | `3`     | Fast failover when an endpoint is unreachable    |

**Round-robin across several instances.** SearXNG queries upstream engines (Google/Bing/DDG…) that rate-limit **by IP**. Point `SEARXNG_URLS` at more than one instance — each on a different IP — and `/web` spreads calls **randomly** across them, so N instances ≈ **N× the query budget** before you hit limits (a real win for batch jobs making hundreds of calls). On a `429`/`503` an endpoint is **parked for a cooldown** so traffic flows to the healthy ones instead of bouncing off the throttled one; a dead endpoint fails over instantly. Add a server later = one more URL in `SEARXNG_URLS`, no code change.

```bash
SEARXNG_URLS="http://localhost:8890, https://cloud.example.com/searx"
```

**Optional: a local SearXNG as a second endpoint.** Stand up a personal SearXNG (native, no Docker) on `127.0.0.1:8890` so `/web` round-robins over your home IP *and* your cloud server's IP:

```bash
./installer/install_searxng.sh   # git clone + venv (Python 3.12) + granian; one-time
./ai_local/ailocal start searxng          # managed alongside ollama and webui; shows in ailocal status
```

Then set `SEARXNG_URLS="http://127.0.0.1:8890, https://<your-cloud>/searx"` in `~/chat/.env`. `ailocal start` (no target) also starts it when installed.

`lib_chat.sh` loads `~/chat/.env` automatically (it's gitignored — your endpoint and credentials never enter the repo). With `SEARXNG_URL` empty, `/web` preflights, reports "not configured", and stays off. Run your own SearXNG (cloud or local) per [SEARXNG_SETUP.md](installer/SEARXNG_SETUP.md).

### Decomposition (RAG query splitting)
| Variable               | Default            | Purpose                                                          |
|------------------------|--------------------|------------------------------------------------------------------|
| `DECOMPOSE_MODEL`      | active Ollama model | Override to use a smaller/faster model just for the split step  |
| `DECOMPOSE_MAX_SUBS`   | `8`                | Max searches one question fans out into. Raise for big enumerations (e.g. `60` for "all 54 countries") — slower, heavier on SearXNG, so opt-in |
| `DECOMPOSE_TIMEOUT`    | `$OLA_CURL_TIMEOUT` (600) | Seconds to wait for the decomposition call                |

Heavy-model tip: `export DECOMPOSE_MODEL=llama3.2:3b` makes the split
near-instant while keeping a big model for the final answer.

### Ollama / memory
| Variable                  | Default                       | Purpose                                                       |
|---------------------------|-------------------------------|---------------------------------------------------------------|
| `OLLAMA_API`              | `http://localhost:11434`      | Ollama HTTP endpoint                                          |
| `DEFAULT_MODEL`           | `gemma4:26b`                  | Fallback model when no `.active_ollama_model.txt` is set yet  |
| `OLA_CURL_TIMEOUT`        | `600`                         | Streaming chat timeout (seconds)                              |
| `OLA_CURL_META_TIMEOUT`   | `60`                          | Background meta calls (autorename, compress)                  |
| `COMPRESS_EVERY`          | `20`                          | Auto-compress memory every N new messages                     |
| `SLIDING_WINDOW`          | `20`                          | Recent messages kept verbatim in each Ollama call             |
| `MAX_WEB_CHARS`           | `6000`                        | Cap on web-search content fed to the model                    |
| `MAX_URL_CHARS`           | `15000`                       | Cap on `/url` fetched content                                 |
| `MAX_COMPRESS_CHARS`      | `10000`                       | Cap on context the compressor reads                           |
| `WEB_CACHE_DIR`           | `~/chat/.web_cache`           | Parent dir for per-turn `turn.XXXXXX` scratch dirs (wiped after each turn) |

### Apple Silicon acceleration

On Apple Silicon, Ollama uses the GPU **automatically** (Metal, and the MLX runtime bundled with the Homebrew build) — there is nothing to "turn on". The service starters (`ailocal`, `chati`, `setup.sh`) additionally set two performance flags recommended by the Homebrew formula, so large models use less memory and run faster:

| Variable                  | Default   | Purpose                                                              |
|---------------------------|-----------|---------------------------------------------------------------------|
| `OLLAMA_FLASH_ATTENTION`  | `1`       | Flash attention — faster, lower memory                              |
| `OLLAMA_KV_CACHE_TYPE`    | `q8_0`    | Quantize the KV cache to 8-bit — big memory saving on long contexts |

Export different values before starting a service to override them. Keeping Ollama current (`ailocal upgrade ollama`) is what pulls in newer MLX/Metal improvements.

---

## Chat Key Commands

Standard: every command is a full word; the short form in parentheses is an equivalent alias.

### Running several chats at once (concurrent terminals)
By default all `chati` instances share one "active session" (pointer + live buffer), so two terminals would clobber each other. Set **`CHATI_INSTANCE`** to give a terminal its own isolated active state:

```bash
CHATI_INSTANCE=work     chati    # terminal 1 — its own active session
CHATI_INSTANCE=research chati    # terminal 2 — independent, no clobber
```

Each instance keeps its own active session, buffer, `/back` pointer and command history under `ola_chat/instances/<name>/`. The **saved-session library** (`conversation_histories/`) and the selected model stay **shared** — every instance can `/switch` to any saved session. Unset = the classic single shared instance (unchanged).

### Session Management
- `/sessions`: List all saved conversations with message counts.
- `/new [name]`: Start a new session.
- `/switch [idx|name]`: Switch to a specific session.
- `/back`: Toggle to the previously active session.
- `/rename [idx] <name>`: Rename a session.
- `/autorename [idx|all]`: Automatically generate descriptive titles for sessions using AI.
- `/delete [idx]`: Remove a specific session.

### Mode Toggles
- `/talk` (`/t`): Toggle auto-speech.
- `/web` (`/w`): Toggle web research. **Honest about availability**: turning it on first preflights the (external) SearXNG backend — if you're offline, the server is down, or credentials are wrong, it says so plainly and stays OFF instead of pretending. **Smart when on**: a router decides per message whether the question actually needs live data. A joke, a coding question or an explanation is answered directly (no search); prices, news, "latest" or recent data trigger a SearXNG search + RAG. The router automatically uses a small installed model for a snappy decision (preference list baked into `lib_chat.sh`, matched against `ollama list`; falls back to the active model) — no per-machine config needed. `WEB_AUTO=0` disables triage (always search); `WEB_ROUTER_MODEL` pins a specific router model.
- `/agent` (`/a`): Toggle Agent Mode — let the AI propose shell commands to run on your Mac. Each command asks for `Y/n` confirmation before executing.

### File & Batch
- `/file` (`/f`) `<file> [msg]`: Send an entire file with an optional instruction.
- `/batch` (`/s`) `[range] <file>`: Automated line-by-line batch processing.
- `/ocr <file|folder|glob>`: OCR a single image/PDF, every image/PDF in a folder, or a glob (e.g. `/ocr ~/Downloads/scans/` or `/ocr ~/Downloads/*.png`), then analyze the combined text.
- `/url <link>`: Analyze webpage content.

### Configuration
- `/prompt [text|-e]`: View, set, edit in `$EDITOR` (`-e`) or clear (`""`) the session prompt.
- `/model [idx|name]`: List or switch the Ollama model.
- `/lang [code]`: List or set the LLM response language (auto, en, es, de, …).
- `/voice [name]`: List or set the macOS TTS voice.
- `/speed [0.25-3.0]`: Adjust talk speed (multiplier format).
- `/colors [f/b]`: Set colors for speech highlighting (e.g., white/green).
- `/settings`: Show current chat settings.

---

## Running the test suite

A bash-only test runner lives at `tests/run_tests.sh`. It exercises three phases:

1. **Syntax + smoke** — `bash -n` every shell script, verify `jq >= 1.6` and `curl` are present, and check that each CLI entry point responds to `--help` / `--version` with exit 0.
2. **Unit tests** — pure helpers from `lib_chat.sh` (`trim_ws`, `active_model`, `get_voice`, `session_msg_count`, …), `lib_web.sh` (`clean_subqueries`, `format_search_results`) and chati (`normalize_for_decomp`, `extract_exec_cmd`, `agent_capability_prompt`, …) run against a **sandboxed `$BASE_DIR`** under `mktemp -d`. The real `~/chat` state is never touched.
3. **Integration** — round-trips through `ollama_chat_oneshot` and `ola` against the real Ollama API. Auto-skipped when Ollama isn't running; the test picks the first installed model (override with `TEST_MODEL=name`).

```bash
./tests/run_tests.sh                       # full suite
FAST=1 ./tests/run_tests.sh                # phase 1 only (~1s)
TEST_MODEL=llama3.2:1b ./tests/run_tests.sh   # pin the integration model
RUN_INTEGRATION=1 ./tests/run_tests.sh     # fail (instead of skip) if Ollama is down
```

Exits 0 on all-pass, 1 if anything failed.

> All scripts source `lib_chat.sh` relative to their own directory and every state path in the lib uses `${VAR:-default}`, so the test harness can pre-export `BASE_DIR=/tmp/sandbox` and have every subprocess inherit the sandbox.

---

## Versioning

This project follows [Semantic Versioning](https://semver.org/). The current release is in [`VERSION`](VERSION) and changes are tracked in [`CHANGELOG.md`](CHANGELOG.md). The `chati` CLI also reports its own component version via `chati --version`.

## License

Released under the [MIT License](LICENSE) © 2026 Carlos Damken.

---
*Note: This repository excludes local message history and test data for privacy and performance.*
