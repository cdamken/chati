# Changelog

All notable changes to this project are documented here. The format is based
on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project
adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

The version here tracks the **project/repo** as a whole. The `chati` CLI also
carries its own internal version (shown by `chati --version`).

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
