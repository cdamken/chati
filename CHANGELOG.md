# Changelog

All notable changes to this project are documented here. The format is based
on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project
adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

The version here tracks the **project/repo** as a whole. The `chati` CLI also
carries its own internal version (shown by `chati --version`).

## [1.14.0] - 2026-08-02

### Added
- **`/think` — see the model's reasoning.** Toggle it and a reasoning model's
  thinking streams live in bright gray under a 💭 header, then the answer follows
  in the normal color. The reasoning is display-only: it never enters the saved
  answer or the conversation history. Sends Ollama's `"think": true` and renders
  the separate `.message.thinking` channel (`ola_stream_thinking`). Off by
  default, so a normal turn is byte-for-byte unchanged. `/think` gates on the
  model's reported capability (`ollama show`) — on a plain model it says there's
  nothing to show and points you to `/model` (e.g. `deepseek-r1:7b`). gemma4,
  deepseek-r1, and qwen3 report the capability.

## [1.13.0] - 2026-08-02

### Added
- **Agent mode (`/a`, `/aY`) plans multi-part tasks before acting.** For a
  request with several parts or that touches many files ("organize Downloads
  into subfolders, index each file, and group the yusuf files"), the agent now
  writes a short numbered plan of subtasks first, then works them one `[EXEC:]`
  at a time and doesn't stop until every step is done. Ported from chati-gh's
  task-decomposition (#27) so a big instruction no longer loses a part midway.
  Single simple requests are unchanged (no plan, straight to the command).

## [1.12.1] - 2026-08-02

### Changed
- **`/web` decompose no longer cold-loads the big answer model.** Splitting a
  question into search queries used to run on the active (answer) model — a 30B
  paying ~2 minutes of cold-load just to rewrite keywords was the real "/web is
  slow" delay (the search itself is ~1s). A new `decompose_model()` picker now
  prefers an installed mid model (`llama3.1:8b`, then `…q8_0`, `gemma4:e4b`,
  `qwen2.5:7b`), honoring `DECOMPOSE_MODEL`, and only falls back to the active
  model when none is installed. The **answer** still uses the active model, so
  analysis quality is unchanged. Works with no `.env` config.

### Added
- **`setup.sh` pulls the `/web` helper models** (`llama3.2:3b` for routing,
  `llama3.1:8b` for decompose) alongside the chat model, so web research is fast
  out of the box after a fresh `git pull` + `./setup.sh`. Skipped under
  `--no-pull` (then `/web` falls back to the chat model for those steps).

## [1.12.0] - 2026-08-02

### Changed
- **`/web` searches its subqueries in parallel.** `do_web_research` ran each
  decomposed subquery one after another (up to 30s each); it now searches them
  concurrently with a bounded pool (`WEB_SEARCH_CONCURRENCY`, default 3),
  preserving order — a multi-query turn drops from the sum of the searches to a
  few batches. The per-endpoint cooldown and random round-robin keep the
  parallelism from hammering a single SearXNG instance.

### Added
- **`web_search_many` (lib_web.sh):** run several `web_search` calls with bounded
  concurrency; results come back in input order, NUL-delimited.
- **`dedup_queries` (lib_web.sh):** drop case/whitespace-duplicate subqueries
  before searching, so a decomposer that repeats itself no longer costs extra
  round-trips.

## [1.11.1] - 2026-07-30

### Fixed
- **SearXNG installer never prompts on the venv again (#5, hardening).** The
  1.10 fix reused an existing `~/searxng/.venv` only when it had a working
  interpreter; a half-created or broken venv still fell through to a bare
  `uv venv`, which prompts *"A virtual environment already exists … replace it?
  [y/N]"* and aborts an unattended re-run when answered "no". Now a broken venv
  is recreated **non-interactively** with `uv venv --clear` (safe — a venv holds
  no config; `settings.yml` is preserved and deps are reinstalled anyway), so
  the installer can never hang or fail on that prompt.

## [1.11.0] - 2026-07-30

### Added
- **Prettier answers: inline TeX is rendered as Unicode as it streams (#8).**
  Models often emit LaTeX-style math — `$\rightarrow$`, `\alpha`, `x^{2}`,
  `\leq`, `\sum` — which reads as noise in a terminal. chati now rewrites the
  common commands to their glyphs on the fly (`→`, `α`, `x²`, `≤`, `∑`), plus
  Greek letters, arrows, set/logic operators, and digit super/subscripts. It's
  deliberately conservative: fenced ` ``` ` code blocks and inline `` `code` ``
  spans pass through untouched, and `$…$` is unwrapped **only** when it really
  contains a command (so `$5`, `$PATH`, `$(cmd)` and `snake_case` are safe).
  Turn it off with `CHATI_PRETTY=0`. (Emoji already work — that's the model.)

## [1.10.0] - 2026-07-30

### Fixed
- **Saved sessions no longer disappear after an upgrade or re-clone (#7).**
  All persistent user data — saved sessions, the active-session pointer, the
  model choice, per-instance buffers, the default prompt — used to live *inside*
  the checkout (`$BASE_DIR`). Cloning chati to a new path (e.g. re-cloning to
  `~/chat` when an older install had lived elsewhere) started from an empty
  state, so every session looked deleted — while the originals sat untouched in
  the old directory. Data now lives in a stable, checkout-independent location
  (`$CHATI_DATA_HOME`, default `~/.local/share/chati`, override with the env
  var). On first run of 1.10, any in-checkout sessions/settings are **moved**
  there once (non-destructive, idempotent) so they survive all future upgrades.
- **OpenWebUI no longer wedges on a pre-existing database (#6).** `ailocal`
  forced `WEBUI_AUTH=False` on every start; on a DB that had been created *with*
  auth and real accounts, that left the UI loaded but with no way to sign in or
  reach chat. It now forces login-less mode only on a **fresh** DB; on an
  existing one it honours whatever the DB was set up with (an explicit
  `WEBUI_AUTH=…` still wins).
- **SearXNG re-install/upgrade no longer fails on an existing venv (#5).**
  `install_searxng.sh` reuses `~/searxng/.venv` when present instead of calling
  `uv venv` (which errors when the venv exists and you decline to replace it);
  dependencies are still (re)installed and `settings.yml` is preserved.

### Added
- **`setup.sh --remove-webui`** — uninstall *only* OpenWebUI (wipes `~/openwebui`,
  app + data/DB), the clean-slate fix for a wedged UI. Ollama, pulled models,
  chati and SearXNG are left untouched. Symmetric **`--remove-searxng`** removes
  just the local SearXNG. (#6)
- `chati --version` now tracks the project version (was pinned at 1.6.2, which
  made upgrades look like no-ops). (#7)

## [1.9.2] - 2026-07-30

### Fixed
- The clone-or-update one-liner (#4) again: the 1.9.1 version used `git pull`,
  which fails with *"no tracking information for the current branch"* when the
  local `main` has no upstream configured (as on a machine set up by
  re-pointing the remote). Now uses
  `… || (cd ~/chat && git fetch origin && git reset --hard origin/main)`,
  which works regardless of tracking or divergence and only discards local
  code edits (config/chats are gitignored). Reproduced and verified.

## [1.9.1] - 2026-07-30

### Fixed
- Docs: the clone step failed with *"destination path already exists"* when
  `~/chat` was already cloned. The Quick Start / Fresh Mac Setup now use a
  clone-or-update one-liner:
  `git clone … ~/chat 2>/dev/null || git -C ~/chat pull`. (#4)

## [1.9.0] - 2026-07-29

### Fixed
- `ailocal start`/`restart` no longer **hangs when run non-interactively**
  (piped or backgrounded). The Ollama and OpenWebUI launches didn't redirect
  stdin, so `</dev/null` is now added to both (matching SearXNG) — an open
  input fd kept the caller's pipe from seeing EOF. Same fix applied to the
  `ollama serve` launches in `chati` and `setup.sh`. (#1)

### Added
- **`/multi` (`/m`)**: compose a multiline message in `$EDITOR`; on save it's
  sent through the normal path (web/lang/agent all apply). (#2)
- **Chat text colors**: your input and the AI reply can each have their own
  color so a long transcript is easy to scan. `/color [user|ai] <name>` live,
  or `CHATI_USER_COLOR` / `CHATI_AI_COLOR` in `.env`. Defaults: you=cyan,
  AI=terminal default. Distinct from `/colors` (TTS highlighting). (#3)

## [1.8.1] - 2026-07-28

### Changed
- Keep-awake now uses `caffeinate -s` instead of `-i`: it prevents sleep **only
  while on AC power**, so a laptop on battery sleeps normally and doesn't drain.
  (`awake on|off|status` unchanged.)

## [1.8.0] - 2026-07-28

### Added
- **`ailocal awake on|off|status`** — keep the Mac from idle-sleeping while it
  serves, so a shared Ollama endpoint stays reachable over LAN/Tailscale. Uses
  `caffeinate` (no sudo), persisted via a marker and re-armed by `ailocal start`
  / autostart. Fixes the "Ollama alive but returns empty generations" symptom
  that happens when the host is in low-power sleep. `--remove-all` cleans it up
  (plus the LAN `launchctl setenv` and `~/.config/chati`).

## [1.7.1] - 2026-07-22

### Added
- `ailocal lan on` / `lan status` now also show the machine's **Tailscale
  MagicDNS address** (e.g. `http://host.tailnet.ts.net:11434`) when Tailscale
  is up. Because LAN mode binds `0.0.0.0`, Ollama is reachable over Tailscale
  too — and the MagicDNS name is stable across IP changes, so it's the
  recommended way to reach it from other machines. README updated.

## [1.7.0] - 2026-07-22

### Added
- **`ailocal lan on|off|status`** — expose the Ollama API to other computers.
  `on` sets `OLLAMA_HOST=0.0.0.0:11434` via `launchctl setenv` (seen by the
  whole login session, incl. the autostart agent) and persists it in a marker
  so it survives reboots (`startollama` re-applies it); prints the LAN address.
  Replaces the fragile `~/.zshrc` export, which didn't reliably reach the
  auto-started Ollama. `off` returns to localhost. Ollama has no auth — LAN only.
- On a ≥32 GB Mac, `setup.sh` now also pulls **`gemma4:31b`** (~19 GB, dense,
  max-quality) alongside the active `gemma4:26b` (MoE). Switch with `/model`.

## [1.6.1] - 2026-07-22

### Changed
- Auto-accept is now **only** `/aY` (capital Y) — removed the `/ay` and `/aa`
  aliases so it can't be triggered by a lowercase reflex; it must be deliberate.
- `/a` and `/aY` both de-escalate to **verification** (never leave you in an
  insecure state): `/a` from auto-accept → verification; `/aY` again →
  verification. The only difference between `/a` and `/aY` is that `/a` asks and
  `/aY` doesn't (and warns). There is no agent mode without safety unless you
  explicitly type `/aY`.

## [1.6.0] - 2026-07-22

### Added
- **`/aY` auto-accept mode** in Agent Mode. `/aY` (aliases `/ay`, `/aa`) turns
  Agent Mode on and runs **every** proposed command **without asking** —
  including destructive ones — for a hands-off task you're actively watching. A
  prominent warning is shown on enable; `/settings` shows a red AUTO-ACCEPT
  status; `/aY` again (or `/a`) turns it off. Default stays the safe whitelist.

## [1.5.0] - 2026-07-22

### Changed
- **Agent Mode is now a whitelist, not a prompt-for-everything gate.** Clearly
  read-only commands (`ls`, `cat`, `grep`, `find`, `ps`, `git status`,
  `brew list`, `ollama list`, … with no pipes/redirects/`$()`) run without a
  prompt; anything that could modify files/processes/network/system — or any
  composed command — shows a warning and still asks `Execute? (y/N)` (denied by
  default). Deny-by-default is preserved: anything unrecognized asks first, and
  composition/redirection/substitution always prompts (so `ls; rm -rf ~` can't
  slip through). `CHATI_AGENT_CONFIRM=all` restores confirm-everything. New unit
  tests cover the safe/risky classification.

## [1.4.0] - 2026-07-22

### Added
- **Login autostart.** `ailocal autostart on|off|status` installs/removes a
  macOS LaunchAgent that runs `ailocal start` at login, so Ollama + OpenWebUI
  + SearXNG come up automatically. It runs through a login shell, so terminal
  env applies (e.g. `OLLAMA_HOST=0.0.0.0` for LAN access carries over).
  `./setup.sh --remove-all` removes the agent.

## [1.3.0] - 2026-07-22

### Added
- Memory-based model selection (done right this time): `setup.sh` detects
  unified memory and auto-selects a model that fits — **≥32 GB → `gemma4:26b`**
  (so a 48 GB Mac gets gemma4:26b automatically, no `--model` needed),
  16–31 GB → `llama3.1:8b-instruct-q8_0`, <16 GB → `gemma3:4b`. `--model NAME`
  still forces a specific model. Unlike the 1.2.0 attempt, the table is
  gemma-centric so it doesn't override gemma4:26b on typical Macs.

## [1.2.2] - 2026-07-22

### Changed
- The installer's default model is **`gemma4:26b`**, installed automatically
  by `./setup.sh` with no flags. Reverted the RAM-based auto-selection added
  in 1.2.0, which silently overrode that default (e.g. picking `llama3.3:70b`
  on a 48 GB Mac). RAM detection is gone; the default is flat and predictable.
  Use `--model NAME` for anything else (e.g. `llama3.3:70b` on a high-RAM Mac).

## [1.2.1] - 2026-07-22

### Added
- Apple Silicon performance tuning: the Ollama service is now started with
  `OLLAMA_FLASH_ATTENTION=1` and `OLLAMA_KV_CACHE_TYPE=q8_0` (the Homebrew
  formula's recommended flags) in `ailocal`, `chati` and `setup.sh` — less
  memory and faster inference for large models. Both are overridable via env.
  GPU/MLX acceleration remains automatic; documented in the README.

## [1.2.0] - 2026-07-22

### Added
- **RAM-aware model selection.** `setup.sh` now detects the Mac's unified
  memory (`sysctl hw.memsize`) and auto-picks a chat model sized for it:
  ≥48 GB → `llama3.3:70b` (~42 GB), 32–47 GB → `gemma4:26b` (~17 GB),
  16–31 GB → `llama3.1:8b-instruct-q8_0` (~8.5 GB), <16 GB → `gemma3:4b`.
  `--model NAME` forces a specific model and skips the auto-pick. A very
  large auto-pick (the 70B) asks before the multi-GB download, and is never
  auto-pulled in a non-interactive run (use `--yes` or `--model`).

## [1.1.0] - 2026-07-22

### Changed
- Default chat model is now **`gemma4:26b`** (was `gemma3:4b`) — a large,
  high-quality model (~17 GB). Made consistent across the whole project: the
  `lib_chat.sh` fallback `DEFAULT_MODEL` was still `llama3.2:1b`, so running
  `chati` without `setup.sh` fell back to a tiny model instead of the
  documented default; it now matches. Override with `./setup.sh --model NAME`
  (e.g. the lighter `gemma3:4b`) or `/model` in-chat.

## [1.0.2] - 2026-07-12

### Added
- `ailocal` is now also symlinked onto `$PATH` by `setup.sh` (alongside
  `chati`), so `ailocal status|start|stop|upgrade …` works from any directory.
  `--remove-all` cleans up both links.

## [1.0.1] - 2026-07-11

### Fixed
- OpenWebUI's SearXNG web search now actually comes up enabled. Its search
  settings are OpenWebUI "PersistentConfig" (read from env only on first boot,
  then DB-authoritative), so on an existing DB the env was ignored. `ailocal`
  now sets `ENABLE_PERSISTENT_CONFIG=False` so the web-search env is applied on
  every boot, and `setup.sh` installs SearXNG **before** starting OpenWebUI so
  it's present when the UI first reads its config.

## [1.0.0] - 2026-07-11

First public release.

### Added
- **`setup.sh`** — one-command, idempotent, do-everything installer: Homebrew
  deps, Ollama + a default chat model, the OpenWebUI browser app, and a local
  SearXNG for `/web` — all installed and started. Options: `--minimal`,
  `--no-webui`, `--no-searxng`, `--model NAME`, `--no-pull`.
- **`setup.sh --remove-all`** — reversible teardown of everything the installer
  creates (keeps Homebrew and its shared packages).
- `chati` is symlinked onto `$PATH`, so it runs from any directory.
- OpenWebUI ships login-less by default (`WEBUI_AUTH=False`, override with
  `WEBUI_AUTH=True`) and its web search is auto-wired to the local SearXNG.
- MIT license; `CHANGELOG.md`; `VERSION`.

### Changed
- Default chat model is `gemma3:4b`.
- README rewritten around a top-of-file Quick Start; install commands are
  copy-paste safe on macOS zsh (no `#` comments / stray quotes that strand the
  shell at a `quote>` prompt).

### Fixed
- `chati` no longer fails every turn when the configured model isn't installed
  (falls back to an installed one; a stale explicit selection self-heals).
- `install_searxng.sh` import smoke test runs like the real runtime (no false
  "searx import failed").
- `installer/Brewfile` no longer carries obsolete `tap` lines that broke
  `brew bundle` on modern Homebrew.
- `docr` no longer hardcodes a personal home path for the language-list file.
