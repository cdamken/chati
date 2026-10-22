# chati

An Ollama-centric, high-performance chat interface for the command line, with local AI service management and OpenWebUI integration.

![version](https://img.shields.io/badge/version-1.33.2-blue) ![license](https://img.shields.io/badge/license-MIT-green) ![platform](https://img.shields.io/badge/platform-macOS-lightgrey)

## ⚡ Quick Start (macOS)

**`./setup.sh` does everything** — installs all dependencies, Ollama + a chat model, the OpenWebUI browser app, and local web search (SearXNG), and starts everything. Two steps to get the code to it:

> **Prerequisite — Homebrew.** If `brew --version` fails, install it, then activate it in the current terminal (otherwise `brew` stays "command not found" until you open a new one):
> ```bash
> /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
> ```
> ```bash
> eval "$(/opt/homebrew/bin/brew shellenv)"
> ```

**1. Get the code** (clones it, or force-updates an existing `~/chati`):

```bash
git clone https://github.com/cdamken/chati ~/chati 2>/dev/null || (cd ~/chati && git fetch origin && git reset --hard origin/main)
cd ~/chati
```

**2. Run the installer:**

```bash
./setup.sh
```

**Done.** `setup.sh` installed and started everything. Now:

- 💬 **CLI chat:** just run `chati` (setup links it onto your PATH, so it works from any directory — or `./chati` from the repo)
- 🌐 **Browser UI:** already running at **http://127.0.0.1:8888**
- 🔎 **Web search:** local SearXNG is running and wired in — toggle it inside chati with `/web`

> The installer **detects your Mac's memory and picks a model that fits**: **≥32 GB → `gemma4:26b`** (~17 GB, the active default) **and also pulls `gemma4:31b`** (~19 GB, dense/max-quality) as a second option; 16–31 GB → `llama3.1:8b-instruct-q8_0`; <16 GB → `gemma3:4b`. Force a single model with `./setup.sh --model NAME`, or switch live in chati with `/model`.
>
> **CLI only?** `./setup.sh --minimal` skips the browser app and SearXNG. **Undo everything?** `./setup.sh --remove-all` (see [Uninstalling](#uninstalling-remove-all)).
>
> **Paste one command at a time.** macOS zsh treats `#` and stray quotes literally, so pasting explanatory text can strand you at a `quote>` prompt — if that happens, press **Ctrl-C** and paste just the command. Every block above is comment-free. More detail and options in [Fresh Mac Setup](#fresh-mac-setup) below.

## Philosophy: bash as the conductor

The point of this project is to show how far a language from 1989 gets when it orchestrates the right specialized tools. **~4,400 lines of bash** drive the whole experience — streaming LLM chat, RAG web research, session memory with LLM compression, TTS, OCR, a Shell Mode with supervised command execution — and every hard sub-problem is delegated to a battle-tested Unix tool that does one thing well:

| Tool | What bash delegates to it |
|---|---|
| `jq` | Every JSON job: chat payload assembly, NDJSON stream parsing, SearXNG result formatting |
| `curl` | Every HTTP job: streaming chat with Ollama, one-shot meta calls, authenticated search queries |
| `lynx` | Webpage → readable text (`/url`) |
| `say` (macOS) | Text-to-speech with word-by-word color highlighting (`/t`) |
| **Apple Vision** / `pdftotext` / `tesseract` | OCR: native macOS Vision (HEIC/photos, fast) → poppler for digital PDFs → tesseract fallback |
| `sed` / `awk` / `grep` | Text munging everywhere, including statistical language detection for voice selection |
| `ollama` | The actual LLM inference |

The rule is **bash first, tools proudly visible** — not "no other languages". When a task genuinely outgrows bash + a tool, a helper in another language is fine: the macOS OCR engine is a small Swift program (`docr/ocr_vision.swift`) because Apple's Vision framework is where the right capability lives. The chat path itself needs nothing beyond bash + `jq` + `curl` + `lynx`.

## Architecture

This project provides a robust terminal-based chat experience with session management, OCR capabilities, automated batch processing, and a unified manager for local AI services (Ollama + OpenWebUI).

### Core Components

The chat stack is **pure bash** — the only runtime dependencies are `jq`, `curl`, and `lynx` (plus macOS built-ins like `say`). There is no Python in the chat path.

- **`chati`**: The main interactive CLI loop (version via `chati --version`).
- **`libexec/chati-*`**: The local service commands behind `chati --webui` / `--stop` / `--status` / `--doctor`. Ollama starts on demand when you launch chati and SearXNG when you use `/web`; OpenWebUI is the one you start explicitly. OpenWebUI's install/upgrade/backup/restore lives in `installer/install_webui.sh`.
- **`ola_chat/`**: Backend logic for Ollama integration (all bash).
  - `ola`: Streaming chat backend — builds the payload and parses the token stream with inline `jq`.
  - `mola`: Advanced session manager (rename, autorename, delete, etc.).
  - `ola_model`: Model management (pull, switch, list).
- **OCR**: chati picks the best engine per file — **Apple Vision** on macOS for images (incl. HEIC) and scanned PDFs (native, GPU/Neural-Engine fast, far better than tesseract on real photos; built by `setup.sh` from `docr/ocr_vision.swift`), **`pdftotext`** for digital PDFs (instant, exact), and **`docr/`** (a tesseract wrapper with quality-profile detection) as the portable fallback. Force one with `CHATI_OCR_ENGINE=auto|vision|tesseract`.
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

### 2. Get the code

Clone it — or, **if `~/chati` already exists** (you cloned before), the second half force-updates it to the latest instead of failing with *"destination path already exists"*. Saved sessions live outside the checkout, so they're unaffected:

```bash
git clone https://github.com/cdamken/chati ~/chati 2>/dev/null || (cd ~/chati && git fetch origin && git reset --hard origin/main)
cd ~/chati
```

> `fetch` + `reset --hard origin/main` is used (rather than a plain `git pull`) because it works even when the local branch has no upstream configured — a plain `pull` fails there with *"no tracking information for the current branch."* It only discards local **code** edits: your config and chats are safe — `.env` and `conversation_histories/` are gitignored, so they're never touched.
>
> The folder does **not** have to be `~/chati` — every script resolves paths relative to its own location, so any name/location works. See also [Updating to the latest version](#updating-to-the-latest-version).

### 3. Run the installer

```bash
./setup.sh
```

That single command does **everything**, checking each step and printing a clear message on any problem: installs Homebrew (if missing), all packages from [`installer/Brewfile`](installer/Brewfile), starts Ollama, pulls a default chat model, sets file permissions, links `chati` onto your PATH, installs + starts the **OpenWebUI** browser app at `http://127.0.0.1:8888`, and installs + starts a local **SearXNG** for `/web` (wiring it into `.env`). Re-running it is safe (idempotent).

Options (add any of these to the command above):

| Option | Effect |
|---|---|
| `--client [HOST] [--searxng URL]` | **Full client** (remote Ollama): chat + **local OCR** + `/web` via a remote SearXNG. No local Ollama server, models, or OpenWebUI. `--client heather --searxng http://heather:8890`. |
| `--client-minimal [HOST]` | **Bare client** for old / low-disk machines: only `curl`, `jq`, `lynx` and the `ollama` CLI. Chat only (no OCR, no `/web`). Smallest footprint. `--client-minimal heather` → `heather:11434`; omit HOST and set it later with `/host`. |
| `--minimal` | CLI only — skip **both** OpenWebUI and SearXNG (still installs the full Homebrew deps) |
| `--no-webui` | skip OpenWebUI only |
| `--no-searxng` | skip the local SearXNG only |
| `--model NAME` | force a chat model, skipping the memory-based pick (e.g. `--model llama3.3:70b`) |
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
| `ghostscript` / `poppler` | `docr`'s PDF rasterizing engine (OCR pipeline) |
| `uv` / `python@3.11` | **OpenWebUI only** — the chat stack itself is pure bash + jq + curl |

> macOS built-ins used by the scripts (`say`, `open`, `pgrep`, `pkill`, `nohup`) require no installation.

### 4. Run chati

`setup.sh` symlinks `chati` onto your PATH, so from any directory:

```bash
chati
```

(Or `./chati` from inside the repo.)

> **Model note:** `setup.sh` detects unified memory and selects a model that fits, then points chati at it:
>
> | Unified RAM | Model(s) pulled | Size |
> |---|---|---|
> | ≥ 32 GB | `gemma4:26b` (active) **+** `gemma4:31b` | ~17 GB + ~19 GB |
> | 16–31 GB | `llama3.1:8b-instruct-q8_0` | ~8.5 GB |
> | < 16 GB | `gemma3:4b` | ~3.3 GB |
>
> On a ≥32 GB Mac both Gemma 4 models are pulled: `gemma4:26b` (MoE, fast, the active default) and `gemma4:31b` (dense, highest quality) — switch between them with `/model`.
>
> Force a specific model with `./setup.sh --model NAME` (e.g. `llama3.3:70b` on a high-RAM Mac). If the configured model isn't installed (e.g. after switching machines), chati **auto-falls-back** to an installed model instead of failing every message — pick any model anytime with `/model`. For a faster `/web` triage router, also pull a small model: `ollama pull llama3.2:3b`.
>
> **Using a remote Ollama.** On a weak laptop you can offload to a beefier machine's Ollama. Point at it with **any reachable address** (a LAN IP like `192.168.1.50:11434`, a hostname, or a Tailscale name — Tailscale is just convenient, not required): set `OLLAMA_HOST` in `.env`, or save a persistent default from inside chati with **`/host <addr>`**. **`/host`** alone lists the servers it can reach (it scans localhost + Tailscale peers) plus any you've saved, and **`/host <n|name> session`** switches just for this session. chati sends both chat and `/model`/list/pull to that box, and each box has its own installed models.
>
> **Old or low-disk machine? Install as a client** so it runs nothing heavy locally (no Ollama server, no models, no OpenWebUI):
> - `./setup.sh --client heather --searxng http://heather:8890` — **full client**: chat + local OCR (`/ocr`, `/file` on images/PDFs) + `/web` pointed at a remote SearXNG. Installs the OCR tools locally; the AI steps of `/web` run on the remote Ollama.
> - `./setup.sh --client-minimal heather` — **bare client**: only `curl`, `jq`, `lynx` and the `ollama` CLI (tens of MB, no OCR, no `/web`). Chat needs just `bash` + `curl` + `jq`.
>
> `/web` never needs a *local* SearXNG — it's a URL you point at (`SEARXNG_URLS` in `.env`). Share the server's SearXNG by starting it network-exposed there (`SEARXNG_LOCAL_HOST=0.0.0.0` in the environment when it comes up), or point at any other instance.

### 5. OpenWebUI — browser UI on top of Ollama

`setup.sh` already installed and started this for you (unless you used `--minimal`) — open **http://127.0.0.1:8888**. It runs **login-less** (`WEBUI_AUTH=False`) since it's a local single-user instance, and its built-in web search is auto-wired to the local SearXNG. To require login instead, start it with `WEBUI_AUTH=True` (decide before first boot — OpenWebUI blocks turning auth back on once its DB exists). If you skipped it and want it later:

```bash
chati --install --force-webui
chati --webui
```

The first line installs OpenWebUI into `~/openwebui/.venv`; the second starts Ollama + OpenWebUI and opens `http://127.0.0.1:8888`.

## Updating to the latest version

There are **two independent things** to keep current — don't confuse them:

**1. chati itself (the code)** — plain `git`:

```bash
cd ~/chati
git pull
```

Your config and chats are safe: `.env` and `conversation_histories/` are gitignored, so `git pull` never touches them. If a very old checkout refuses to pull cleanly, force it to match the repo (this only discards local *code* edits, not your data):

```bash
git reset --hard origin/main
```

No build step — the scripts run straight from the checkout, so you're on the new version the moment the pull finishes.

Or let chati do both at once — pull the latest release **and** re-apply setup (which upgrades OpenWebUI):

```bash
chati --upgrade
```

**2. Ollama and OpenWebUI (the services, not this code):**

```bash
brew upgrade ollama && chati --stop   # new Ollama binary; next chati launch auto-starts it
chati --install                       # re-applies setup: upgrades OpenWebUI via uv (idempotent)
```

OpenWebUI's upgrade snapshots your data first; if a new build misbehaves, `installer/install_webui.sh restore` brings back the pre-upgrade state.

## Uninstalling (`--remove-all`)

To tear the whole install back down — handy for testing a clean install, or moving on:

```bash
./setup.sh --remove-all
```

It lists exactly what it will delete and asks for confirmation (add `--yes` to skip the prompt). It removes: OpenWebUI (`~/openwebui`), the local SearXNG (`~/searxng`), logs (`~/logs`), the `chati` PATH link, **all pulled Ollama models**, and this repo's local state (`.env`, `.active_ollama_model.txt`, `.web_cache`, `conversation_histories/`, `ola_chat/instances/`).

It deliberately **keeps Homebrew and its packages** (`jq`, `curl`, `ollama`, `tesseract`, …) — they're shared with the rest of your system, so removing them is out of scope. It also leaves the repo code itself. Re-install anytime with `./setup.sh`.

> Only the repo checkout and your Homebrew toolchain survive — everything the installer created is gone. This is the teardown half of an install/uninstall test cycle: `./setup.sh` → use it → `./setup.sh --remove-all`.

## Managing the local services

chati manages the whole local AI stack itself — there is no separate service manager. Ollama starts on demand when you launch chati, SearXNG starts when you use `/web`, and OpenWebUI is the one you start explicitly.

```bash
chati --webui     # start OpenWebUI (brings Ollama up under it); opens http://127.0.0.1:8888
chati --stop      # stop OpenWebUI, SearXNG and Ollama — free the machine
chati --status    # show which of the three are running (read-only)
chati --doctor    # health check: version, Ollama, models, SearXNG, OpenWebUI
```

There is deliberately **no** manual start/restart for Ollama or SearXNG — they come up on their own. `chati --webui` restarts the stack if you need to bounce it (for example after `brew upgrade ollama`: run `chati --stop` so the next launch spawns the new runner binary, or just `chati --webui`).

### Installing / upgrading OpenWebUI

The OpenWebUI venv is installed and upgraded by `installer/install_webui.sh`, which `setup.sh` runs on install and on every `chati --upgrade`:

```bash
chati --install                      # idempotent: uv pip install --upgrade open-webui
chati --install --force-webui        # reinstall the venv from scratch (data stays safe)
installer/install_webui.sh restore   # roll back to the pre-upgrade snapshot
```

Every upgrade **snapshots the current state first** (into a single backup slot). `install_webui.sh` exports `DATA_DIR=~/openwebui/data` — the variable OpenWebUI actually reads — so the database lives **outside** the venv and survives `--force` reinstalls. uv **owns** the Python (a managed 3.11), so a later `brew autoremove` can't delete the interpreter out from under the venv.

Environment knobs: `WEBUI_START_TIMEOUT` (default 180s — first boot after an upgrade migrates the DB and can be slow), `CHATI_NO_OPEN` (skip auto-opening the browser). Requires `uv` (`brew install uv`); it manages a Python 3.11 virtualenv at `~/openwebui/.venv`.

### Backup & restore (OpenWebUI data)

One backup slot, by design: it always holds the state before the last upgrade (or the last manual `backup`). Upgrade replaces it; restore goes back to it.

```bash
installer/install_webui.sh backup         # snapshot now, replacing the previous one
installer/install_webui.sh restore        # go back to the snapshot (asks for confirmation)
installer/install_webui.sh restore --yes  # same, non-interactive
```

The slot lives at `~/openwebui_backups/previous/` and includes the database (consistent `sqlite3 .backup` snapshot), the data directory and the secret key.

### Running on an always-on server

chati 1.36 dropped the old `ailocal` conveniences for autostart / LAN exposure / keep-awake in favor of the three-command model. On a shared server you set the same things up directly:

- **Expose Ollama on the LAN / Tailscale.** Start it bound to all interfaces: `OLLAMA_HOST=0.0.0.0:11434 ollama serve`. On Tailscale, connect from clients by the MagicDNS name (`export OLLAMA_API=http://your-mac.your-tailnet.ts.net:11434`) — stable across IP changes and private to your devices.
  > ⚠️ **Ollama has no authentication.** Only expose it on a trusted network or over Tailscale. This exposes only Ollama; OpenWebUI/SearXNG stay on localhost.
- **Start at login.** Add your own `~/Library/LaunchAgents` plist that runs `ollama serve` (and `chati --webui` if you want the UI up) through a login shell.
- **Keep the Mac awake while serving.** `caffeinate -s` (no sudo; only while on AC power), or system-level `sudo pmset -c sleep 0 disablesleep 1` for a plugged-in server. A Mac in low-power sleep can look alive (`/api/tags` responds) yet return empty generations.

**Stale bind after an Ollama upgrade or after sleep.** If the server answers on `localhost` but clients get `Connection reset by peer` (errno 54) or `Empty reply from server`, a stale `ollama serve` is still running the old binary (or wedged after sleep). Restart it so the current binary takes over:

```bash
pkill -f "ollama serve"
OLLAMA_HOST=0.0.0.0:11434 ollama serve
curl -sS http://<server-ip>:11434/api/version   # verify from the server host
```

See [#52](https://github.com/cdamken/chati/issues/52) and [#55](https://github.com/cdamken/chati/issues/55).

### Logs

| Service        | Log file                      |
|----------------|-------------------------------|
| Ollama         | `~/logs/ollama.log`           |
| OpenWebUI      | `~/logs/webui.log`            |
| SearXNG        | `~/logs/searxng.log`          |
| WebUI upgrades | `~/logs/webui_upgrade.log`    |

---

## Configuration (environment variables)

All tunables are exported by `lib_chat.sh` with sane defaults; override
any of them in `~/.zshrc` if needed.

### Web search (SearXNG)

SearXNG is an **external service you point at** — it is not bundled, and there is **no default URL baked into the repo** (so a clone never talks to someone else's server). Configure your own instance in `~/chati/.env`:

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

**Headless: `chati --search <query>`.** The same pipeline is available non-interactively — it prints the SearXNG results and exits, no REPL and no LLM call:

```bash
chati --search "Kimberly-Clark forward P/E ROIC dividend 2026"
```

This is the programmatic entry point for scripts, pipelines and other machines/agents that need **fresh web facts** without driving the chat UI — e.g. feeding today's numbers into a local model on another host, or a batch screen that pulls current data per item. It reuses `lib_web.sh`'s `web_search`, so it honours the exact same `SEARXNG_URLS`, round-robin and cooldown behaviour. Exit codes: `2` on a missing query, `1` if no backend is configured.

```bash
SEARXNG_URLS="http://localhost:8890, https://cloud.example.com/searx"
```

**Optional: a local SearXNG as a second endpoint.** Stand up a personal SearXNG (native, no Docker) on `127.0.0.1:8890` so `/web` round-robins over your home IP *and* your cloud server's IP:

```bash
./installer/install_searxng.sh   # git clone + venv (Python 3.12, uv-owned) + granian; one-time
```

Then set `SEARXNG_URLS="http://127.0.0.1:8890, https://<your-cloud>/searx"` in `~/chati/.env`. Once installed it **starts on demand** when you use `/web` (no manual start); `chati --status` shows it and `chati --stop` stops it.

`lib_chat.sh` loads `~/chati/.env` automatically (it's gitignored — your endpoint and credentials never enter the repo). With `SEARXNG_URL` empty, `/web` preflights, reports "not configured", and stays off. Run your own SearXNG (cloud or local) per [SEARXNG_SETUP.md](installer/SEARXNG_SETUP.md).

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
| `WEB_CACHE_DIR`           | `~/chati/.web_cache`           | Parent dir for per-turn `turn.XXXXXX` scratch dirs (wiped after each turn) |

### Apple Silicon acceleration

On Apple Silicon, Ollama uses the GPU **automatically** (Metal, and the MLX runtime bundled with the Homebrew build) — there is nothing to "turn on". When chati starts Ollama it additionally sets two performance flags recommended by the Homebrew formula, so large models use less memory and run faster:

| Variable                  | Default   | Purpose                                                              |
|---------------------------|-----------|---------------------------------------------------------------------|
| `OLLAMA_FLASH_ATTENTION`  | `1`       | Flash attention — faster, lower memory                              |
| `OLLAMA_KV_CACHE_TYPE`    | `q8_0`    | Quantize the KV cache to 8-bit — big memory saving on long contexts |

Export different values before starting a service to override them. Keeping Ollama current (`brew upgrade ollama`) is what pulls in newer MLX/Metal improvements.

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
- `/shell` (`/s`): Toggle **Shell Mode** — let the AI propose shell commands to run on your Mac (you approve them). It's an *assisted* mode (you're in the loop), not an autonomous agent. **Clearly read-only commands** (`ls`, `cat`, `grep`, `find`, `ps`, `git status`, `brew list`, …, with no pipes/redirects/`$()`) run **without a prompt**. Anything that could modify files, processes, network or system — or any composed command — shows a **warning and asks `Execute? (y/N)`**, denied by default unless you type `y`. It's a **whitelist**, not a blacklist: anything unrecognized asks first. Set `CHATI_AGENT_CONFIRM=all` to confirm *every* command. (The old `/agent`, `/a` names are retired — they no longer toggle; they just point you here.)
- `/sY`: Toggle **auto-accept** (capital `Y` on purpose, so it can't happen by accident) — turns Shell Mode on and runs **every** proposed command **without asking**, including destructive ones. Shows a warning on enable; use only for a task you're actively watching (Ctrl-C interrupts). `/sY` again — or `/s` — returns to verification. `/s` and `/sY` differ only in this: `/s` asks, `/sY` doesn't (and warns). There is **no Shell Mode without safety** unless you deliberately type `/sY`. (The old `/aY` is retired — it no longer arms auto-accept.)

### Input & Files
- `/multi` (`/m`): Compose a **multiline message** in your `$EDITOR`; on save it's sent like any message (goes through `/web`, `/lang` and Shell Mode). Great for long or formatted prompts without buffer hacks.
- `/file` (`/f`) `<file> [msg]`: Send an entire file with an optional instruction.
- `/batch` (`/s`) `[range] <file>`: Automated line-by-line batch processing.
- `/ocr <file|folder|glob>`: OCR a single image/PDF, every image/PDF in a folder, or a glob (e.g. `/ocr ~/Downloads/scans/` or `/ocr ~/Downloads/*.png`), then analyze the combined text.
- `/url <link>`: Analyze webpage content.

### Configuration
- `/persona [text|-e]`: View, set, edit in `$EDITOR` (`-e`) or clear (`""`) the session persona.
- `/model [idx|name]`: List or switch the Ollama model.
- `/lang [code]`: List or set the LLM response language (auto, en, es, de, …).
- `/voice [name]`: List or set the macOS TTS voice.
- `/speed [0.25-3.0]`: Adjust talk speed (multiplier format).
- `/color`: One menu for **all colors**. `/color` alone lists them; `/color you <name>` / `/color ai <name>` set the **chat text** colors (your input vs the AI reply); `/color tts <fg/bg>` sets the **voice/TTS highlight** colors. Names: default, black, red, green, yellow, blue, magenta, cyan, white, gray. Defaults: you=cyan, AI=terminal default, tts=white/green. Persist per-machine via `CHATI_USER_COLOR` / `CHATI_AI_COLOR` in `.env`.
- `/settings`: Show current chat settings.

---

## Running the test suite

A bash-only test runner lives at `tests/run_tests.sh`. It exercises three phases:

1. **Syntax + smoke** — `bash -n` every shell script, verify `jq >= 1.6` and `curl` are present, and check that each CLI entry point responds to `--help` / `--version` with exit 0.
2. **Unit tests** — pure helpers from `lib_chat.sh` (`trim_ws`, `active_model`, `get_voice`, `session_msg_count`, …), `lib_web.sh` (`clean_subqueries`, `format_search_results`) and chati (`normalize_for_decomp`, `extract_exec_cmd`, `agent_capability_prompt`, …) run against a **sandboxed `$BASE_DIR`** under `mktemp -d`. The real `~/chati` state is never touched.
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
