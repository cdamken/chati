# Changelog

All notable changes to this project are documented here. The format is based
on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project
adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

The version here tracks the **project/repo** as a whole. The `chati` CLI also
carries its own internal version (shown by `chati --version`).

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
