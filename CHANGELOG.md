# Changelog

All notable changes to this project are documented here. The format is based
on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project
adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

The version here tracks the **project/repo** as a whole. The `chati` CLI also
carries its own internal version (shown by `chati --version`).

## [1.27.1] - 2026-08-11

### Fixed
- **Each chat truly keeps its own settings now — a new/switched session no
  longer inherits the previous one's toggles (#60).** Per-session settings
  (#37) saved correctly on leave, but `load_active_settings` didn't reset to a
  baseline first, so a `/new` (or `/switch`/`/back` into a session with no saved
  settings, and no global `/defaults`) kept the toggles from the session you
  just left. Loading is now layered — **factory reset → global defaults → this
  session's own settings** — captured from a one-time snapshot of the built-in
  values at startup. A fresh session starts clean (and never silently keeps
  Shell / auto-accept armed from a previous one); returning to a saved session
  restores exactly its settings.

## [1.27.0] - 2026-08-11

### Changed
- **`/host` is now the single command for Ollama endpoints.** It absorbed
  `/ollama`: `/host` lists discovered + saved servers (localhost + Tailscale
  peers) with versions and the current default; `/host <n|name|local>` sets the
  default (saved to `.env`); `/host <n|name> session` switches for this run only
  (not saved); `/host forget <n|name>` drops a saved one. A bare host still
  defaults to `:11434`.

### Removed
- **Dropped legacy command aliases and the retired-name notices** (single-user
  cleanup, no migration path needed): `/ollama` and `/endpoint` (use `/host`),
  `/prompt` (use `/persona`), `/colors` (use `/color`), and `/agent` / `/a` /
  `/aY` (use `/shell` / `/s` / `/sY`). The designed word+short-form pairs stay:
  `/file`+`/f`, `/batch`+`/b`, `/talk`+`/t`, `/web`+`/w`, `/shell`+`/s`.
- **Removed the old `~/chat` → `~/chati` folder migration** from `setup.sh` and
  the README (the rename is long done; nobody runs the old path).

## [1.26.2] - 2026-08-11

### Changed
- **`ailocal lan on` now enables auto-heal automatically** (and `lan off`
  disables it). Exposing Ollama on the network is exactly when the sleep/wake
  bind-wedge bites (#55), so the self-healer that keeps remote clients from
  losing the server after the Mac naps is now coupled to LAN exposure instead of
  being a separate step you had to know about. `setup.sh` does **not** expose
  Ollama by default (it has no auth); its final summary points to `ailocal lan
  on` for those who want to serve other machines, noting it also turns on
  auto-heal.

## [1.26.1] - 2026-08-11

### Fixed
- **chati no longer hangs at startup when `.env` points at an unreachable
  Ollama.** If a saved `OLLAMA_HOST` (via `/host`) named a remote box that was
  down, startup tried to launch a LOCAL `ollama serve` and wait for it — but
  with `OLLAMA_HOST` set to a remote address the server can't even bind, so the
  readiness loop spun and the session appeared frozen right after the banner
  (`🚀 Starting 'ollama serve'…`). Now startup detects a remote endpoint and,
  instead of starting a local server, **falls back to localhost when it
  answers** (so chats keep working) or prints a clear note and continues —
  never blocks. Point back at the remote with `/host <name>` once it's up.

## [1.26.0] - 2026-08-11

### Added
- **`ailocal autoheal` — self-heal Ollama's LAN/Tailscale bind after a
  sleep/wake (#55).** After the Mac sleeps and wakes (or Ollama auto-updates in
  the background), the daemon can keep running yet stop accepting on the real
  interfaces while `localhost` still works, so remote clients get `connection
  reset` / `empty reply` even though `pgrep` says Ollama is up. `ailocal
  autoheal on` installs a LaunchAgent that probes reachability off-localhost
  every 120s (configurable via `AUTOHEAL_INTERVAL`) and restarts Ollama when the
  bind is wedged; launchd also fires it right after wake, so it recovers within
  one interval. `ailocal heal` runs the check once by hand. No-op unless `ailocal
  lan on` is set.

### Changed
- **`/model` / `/models`.** `/models` is now accepted as an alias of `/model`
  (it used to say "Unknown command"). When the active Ollama endpoint is
  **remote** and unreachable, the error now says the remote machine is
  asleep/unexposed and points to `/ollama` or `/host local`, instead of the
  misleading "start it with ailocal startollama" (which only applies locally).

## [1.25.5] - 2026-08-11

### Changed
- **`/host` and `/ollama` default the port to 11434 consistently.** A bare host
  already worked (`/host heather` → `heather:11434`); now a full URL with a
  scheme but no port does too (`/host http://heather` used to hit `:80`, now
  `heather:11434`). An explicit port or a URL with a path is left untouched.
  Help text for `/host` now spells out the default.

## [1.25.4] - 2026-08-08

### Fixed
- **A cold big model no longer trips the streaming stall guard (#50).** The guard
  aborts a stream after ~300s under 1 byte/sec, but a cold-loading big model
  (e.g. `gemma4:31b`, ~19 GB) can emit zero bytes for minutes while it loads, so
  the load itself looked like a stall (`curl: (28) Operation too slow`). `ola`
  now warms the model first (`POST /api/generate` with just the model name, a
  generous `OLA_LOAD_TIMEOUT`=900s and no stall guard), so cold-load time never
  counts against the stream; the guard then only catches real mid-stream stalls.
  A model already resident returns from the preload instantly.

## [1.25.3] - 2026-08-07

### Fixed
- **Ctrl-C no longer quits chati — it interrupts the current turn and returns
  to the prompt.** With no INT trap in the main REPL, pressing Ctrl-C while the
  model was streaming killed the foreground `ola` and the signal propagated up,
  terminating the whole session. Now a main-shell trap catches SIGINT: it stops
  the in-flight generation (or a pending Shell-mode command / confirmation) and
  drops you back to `> `. The prompt reprints on Ctrl-C at idle; Ctrl-D (EOF)
  still exits cleanly. The `/batch` cancel handler was restoring `trap - INT`
  (uncaught) on finish — it now reinstalls the main-loop handler so the next
  Ctrl-C after a batch is still caught.

## [1.25.2] - 2026-08-07

### Changed
- **Retired the old Shell-mode names `/agent`, `/a`, `/aY` (#47).** After the
  1.19.0 rename to Shell, they were kept as aliases; now they no longer do
  anything except point you to the new command. This matters most for `/aY`: a
  reflex keystroke can no longer arm auto-accept — it just prints
  `ℹ️ '/aY' was renamed. Use /shell (/s)… /sY for auto-accept.` The working
  commands are `/shell` (`/s`) and `/sY`.

## [1.25.1] - 2026-08-07

### Changed
- **Friendlier first-launch message per terminal.** A brand-new terminal (its
  own tty, no session yet) used to greet you with a scary `⚠️ Current session
  missing. Starting a new one...` — it isn't missing, it's just your first one.
  Now it says `✨ Starting a new session…`. The `⚠️` warning is kept only for the
  real case: an active session whose file was actually deleted/moved. `/settings`
  also shows `(new — none yet)` instead of the literal `active` before the first
  session exists.

## [1.25.0] - 2026-08-07

### Changed
- **Per-terminal isolation by default (#37, part 2).** With no explicit
  `CHATI_INSTANCE`, chati now derives one from the controlling terminal (tty),
  so each window/pane keeps its OWN active session, live buffer and model — two
  terminals no longer clobber each other's session or model. The same terminal
  resumes its state across relaunches; a different terminal is independent (it
  starts fresh — your saved sessions are still shared, reachable with
  `/switch`). Falls back to the shared instance when there's no tty (pipes,
  scripts, tests), so non-interactive use is unchanged. **Model is now
  per-terminal** (`/model` in one window doesn't change another), falling back
  to the global default (your usual model) when a terminal hasn't chosen one.

## [1.24.0] - 2026-08-07

### Added
- **Per-session settings + editable global defaults (#37, part 1).** Your
  toggles now travel WITH the session: `/lang`, `/web`, `/think`, Shell (`/s`,
  `/sY`), Talk/`/voice`/`/speed`, and the chat/TTS colors are saved when you
  leave or `/switch` a session (and at exit), and restored when you come back —
  so each conversation keeps its own config instead of losing it on exit. A NEW
  session inherits the **global defaults**: `/defaults save` snapshots the
  current settings as that default, `/defaults` shows them, `/defaults clear`
  resets. Settings live in a `${session}_settings` companion (renamed/deleted
  with the session). (Per-terminal TTY isolation and per-session *model* are
  part 2, still tracked in #37.)

## [1.23.0] - 2026-08-07

### Added
- **Remembered Ollama servers + auto-fallback to localhost (#39 follow-up).**
  - Every server you switch to (via `/host` or `/ollama <addr>`) is **saved** to
    `~/.local/share/chati/ollama_hosts`, so `/ollama` lists it again later even
    while it's asleep (shown as `saved, offline` but still pickable). Multiple
    servers are supported; drop one with `/ollama forget <n|host>`. localhost is
    never saved (always implied).
  - **Auto-fallback:** if the remote Ollama you're pointed at goes away
    mid-session (asleep, off-network), chati drops back to **localhost**
    automatically (only when localhost actually answers) and re-picks a valid
    local model, so you're never stuck. Disable with `CHATI_OLLAMA_FALLBACK=0`.

## [1.22.1] - 2026-08-07

### Docs
- **Clarified that the remote-Ollama endpoint is not Tailscale-only.** `/host`,
  `/ollama <addr>` and `OLLAMA_HOST` accept ANY reachable address (a LAN IP like
  `192.168.1.50:11434`, a hostname, or a Tailscale name). Only `/ollama`'s
  auto-discovery is Tailscale-based (it scans localhost + Tailscale peers); you
  can always point at a plain LAN IP by hand. Updated `.env.example`, the README
  note, and the `/ollama` empty-list hint.

## [1.22.0] - 2026-08-07

### Added
- **`/host` — set and persist the default Ollama endpoint from inside chati.**
  Follow-up to #39: `/ollama` switches for the current session only; `/host
  <host|url|local>` writes `OLLAMA_HOST` to your `.env` so it survives restarts
  (and applies immediately). `/host` alone shows the current + saved endpoint;
  `/host local` resets to localhost and removes it from `.env`. Rewrites `.env`
  in place (keeps comments and other vars, no duplicate lines, `600` perms). No
  more hand-editing `.env` to point at a remote Ollama.

## [1.21.0] - 2026-08-07

### Added
- **Use an external / remote Ollama, with discovery (#39).** Point chati at a
  more powerful machine's Ollama for BOTH chat and model ops. Set `OLLAMA_HOST`
  in `.env` (the same var the `ollama` CLI reads; chati derives its API URL from
  it via `resolve_ollama_api`, so `/model`, list and pull hit the same box), or
  switch live with the new **`/ollama`** command: it discovers reachable servers
  (localhost + online Tailscale peers on :11434), lists them with versions, and
  switches to the one you pick (`/ollama <n|host|url|local>`). Each server has
  its own models, so `/settings` shows the endpoint next to the model when it's
  remote. A `0.0.0.0` bind is treated as localhost for the client.

## [1.20.0] - 2026-08-07

### Changed
- **Unified color config + `/persona` (naming polish).** All color settings now
  live under one `/color` command: `/color` alone shows a menu (chat text +
  voice/TTS highlight); `/color you|ai <name>` sets the chat colors and
  `/color tts <fg/bg>` the spoken-highlight colors. This retires the confusing
  near-twins `/color` vs `/colors` (the old `/colors fg/bg` still works as an
  alias). And `/prompt` is now **`/persona`** (clearer: it sets the session's
  role/persona; `/prompt` kept as an alias). `/settings` shows "Persona" and a
  `tts=` entry in the Colors line.

## [1.19.0] - 2026-08-07

### Changed
- **"Agent Mode" renamed to "Shell Mode" (`/shell`, `/s`, `/sY`).** In 2026
  "agent" means an autonomous process you dispatch; chati's feature is the
  opposite — the model proposes ONE shell command and you approve it. The new
  name says what it does: enable shell commands (you stay in the loop). `/shell`
  (`/s`) toggles it, `/sY` is auto-accept. The old `/agent`, `/a`, `/aY` keep
  working as aliases, so nothing breaks. `/settings` and help now say "Shell".
  To free `/s`, the `/batch` short alias moved to **`/b`** (`/batch` still works).

## [1.18.3] - 2026-08-07

### Fixed
- **Streaming no longer hangs for 10+ minutes on a stuck/cold-loading model, and
  background compaction stops timing out (#35).** Two causes:
  1. The chat stream only had an overall `--max-time`, so a wedged or cold-
     loading big model (or a sleeping host) produced 0 bytes for the whole
     timeout before failing with a generic error. Added a stall guard
     (`--speed-limit 1 --speed-time $OLA_STALL_TIMEOUT`, default 300s, plus a
     10s connect timeout) so it aborts in minutes, and the error now names the
     likely cause (big model cold-loading / low memory / asleep) with fixes
     (smaller model via /model, `ailocal awake on`).
  2. Background memory compaction and auto-titling used the big ANSWER model
     (`active_model`), so they timed out behind it and silently dropped the
     summary. They now use a small `compress_model` (COMPRESS_MODEL overrides).
  Also: the test suite no longer writes to the real `~/logs/chati.log`.

## [1.18.2] - 2026-08-07

### Changed
- **Smarter /web triage: local/disk actions no longer trigger a web search (#33).**
  With `/web` on, the router ran on every message and, being SEARCH-biased with
  no notion of local work, would web-search a disk task ("organize my Downloads",
  "read ~/contract.pdf"). It now reasons on two axes and takes the Agent-Mode
  signal: an action on your own machine/files -> DIRECT (no search), while a task
  that must FETCH from the internet -> SEARCH even if it then saves locally
  (e.g. "download cat images into ~/Downloads"). `augment_message` passes the
  `/a`/`/aY` state to the router. Verified live: organize/read-local -> DIRECT,
  download-images/current-price -> SEARCH.

## [1.18.1] - 2026-08-06

### Fixed
- **Web search no longer mangles proper nouns / brands / domains (#29).** The
  query decomposer (a small model) rewrote names it "recognized" — e.g. a
  question about **claude.ai** was searched as **"claudia ai"**. The decomposer
  prompt now hard-requires copying every proper noun, brand/product name, domain,
  username and ticker character-for-character (no translate/transliterate/spell-
  "correct"), and chati now ALWAYS also searches the user's original query
  verbatim as a safety net, so the real terms are searched even if a subquery
  drifts.

## [1.18.0] - 2026-08-06

### Added
- **Apple Vision OCR — much faster and far more accurate on real photos (#28).**
  chati now picks the best OCR engine per file instead of always shelling out to
  docr/tesseract:
  1. **Digital PDFs** (with a text layer) → `pdftotext` (poppler) — instant,
     lossless, no OCR at all.
  2. **Images (incl. HEIC/WEBP/AVIF) and scanned PDFs** → **Apple Vision** on
     macOS, a tiny native helper (`docr/ocr_vision.swift`, compiled by `setup.sh`
     to `docr/ocrvision`, no Python) using the system's on-device text
     recognition. Reads HEIC directly (no ImageMagick conversion) and is *far*
     better than tesseract on angled/glare/low-light photos.
  3. **Fallback** → docr/tesseract when Vision isn't available (non-macOS, or the
     helper didn't build).
  Measured on a real HEIC photo of a screen: **Vision 2.3 s, usable text** vs
  **tesseract 8.6 s producing garbage** (it read the angled photo rotated).
  Force an engine with `CHATI_OCR_ENGINE=auto|vision|tesseract`; set Vision's
  languages with `CHATI_OCR_LANGS` (default `es-ES en-US de-DE`). New OCR-able
  formats: WEBP, AVIF, HEIF. `poppler` added to the Brewfile. The `/ocr` command
  and auto-OCR both use the new engine selection.

## [1.17.0] - 2026-08-06

### Added
- **Fine-tuning-ready JSONL session log (#12).** chati now appends one JSONL
  record per user turn — `{ts, session, model, instruction, context_sent,
  response}` — to `~/.local/share/chati/finetune/<session>.jsonl`, a clean
  training/history stream separate from `conversation_histories`. Captured once
  per turn (before agent sub-steps). Disable with `CHATI_FINETUNE_LOG=0`.

### Changed
- **`ailocal lan status` / `lan on` now print the raw Tailscale IPv4 too (#20).**
  MagicDNS names aren't resolvable by every client (Python `urllib`'s
  `getaddrinfo`, some HTTP libs) even when `curl` resolves them — so scripts and
  agents reaching a shared Ollama over Tailscale got a name that didn't work.
  Both commands now show the MagicDNS name **and** the raw `100.x` IP, noting the
  raw IP is the robust choice for programmatic/cross-machine use.
- **Agent mode: "act, don't draft" (#13).** `agent_capability_prompt` gains a
  rule forbidding the model from pasting a file's new contents as prose/markdown/
  code-fence instead of emitting the command that writes it, with append/create/
  `sed`-edit worked examples. (The multi-part **decomposition** half of #13 was
  already covered by the existing "PLAN multi-part work first" rule.)

## [1.16.0] - 2026-08-06

### Changed
- **Install folder renamed `chat` → `chati`, with automatic migration (#10).**
  The project began as a Pharia "chat" app and the docs installed it to `~/chat`;
  it's `chati` now, so the canonical path is **`~/chati`**. On the next deploy the
  rename happens by itself: `setup.sh` run from an old `~/chat` checkout **moves
  it to `~/chati` and re-execs** from there (re-pointing the `chati`/`ailocal`
  PATH links), and the README's get-the-code one-liner does the same `mv` up
  front. Safe: user data already lives outside the checkout (`~/.local/share/chati`
  since 1.10), so only code + `.env` + local scratch move; saved sessions are
  untouched. Docs, the SearXNG installer hint, and internal comments updated to
  `~/chati`. Internal names (`ola_chat/`, `lib_chat.sh`, `conversation_histories/`)
  are unchanged — only the install path moved.

## [1.15.3] - 2026-08-06

### Changed
- **Live progress while OCR runs, so it never looks frozen (#21).** docr can take
  a minute or more per file (HEIC/photos longer) and ran silently — with no GPU
  activity (OCR is CPU/tesseract work), it looked like a crash. `ocr_files_to_text`
  now prints a per-file `[i/N]` header, a live `⏳ working… Ns` elapsed counter
  that ticks each second, and a `✓ done in Ns` (or a clear warning with docr's
  last output if nothing was extracted). Up-front note that OCR is CPU-bound so
  no GPU activity is expected. Used by both `/ocr` and auto-OCR.

### Changed
- **Auto-OCR reuses a path you gave earlier in the session (#21).** If you name
  a PDF/image (or a folder) and then a few turns later say *"lee los pdfs"* or
  *"resume ese documento"* without repeating the path, chati now looks back
  through the recent conversation, finds the most recent image/PDF path or
  folder you mentioned, and OCRs it — instead of asking you to type it again.
  Scans only the last handful of your turns (so a stale path from long ago
  doesn't resurface) and still respects `CHATI_AUTO_OCR_MAX`; if it finds
  nothing, it falls back to the hint from 1.15.1.

## [1.15.1] - 2026-08-05

### Changed
- **Auto-OCR is more forgiving, and never leaves the model to bluff (#21).**
  Follow-up to 1.15.0's auto-OCR: (1) naming a **folder** now OCRs the image/PDF
  files inside it (`lee los pdfs de ~/Downloads/facturas`), not just individual
  files; (2) a safety cap (`CHATI_AUTO_OCR_MAX`, default 8) means a huge folder
  isn't silently OCR'd — chati points you to `/ocr` instead; (3) when your
  message clearly asks to **read a document but names no path chati can find**,
  it now prints a short hint (name the file, drag it in, or use `/ocr`) instead
  of letting a small model hallucinate that it "can't do OCR." Triggers only on a
  document/OCR keyword **plus** a read/analyze cue, so casual mentions of a PDF
  don't trip it.

## [1.15.0] - 2026-08-05

Consolidated release of three merged PRs (#11, #14, #22).

### Added
- **Automatic OCR of images/PDFs you mention (#21, PR #22).** chati now reaches
  for the `docr` OCR tool on its own: when your message names an image or PDF
  that exists on disk — typed, tab-completed, or drag-and-dropped (escaped
  spaces handled) — it OCRs the file and folds the text into the prompt, so
  *"resume ~/Downloads/factura.pdf"* just works with no `/ocr` step. Conservative
  by design: only real, on-disk, OCR-able paths (`jpg/jpeg/png/pdf/tif/tiff/bmp/
  gif/heic`) trigger it, so a bare ".pdf" mention or a `.txt` path never does.
  Toggle with `CHATI_AUTO_OCR=0`; `/ocr` is unchanged. Extraction is now a shared
  `ocr_files_to_text` helper used by both paths.
- **Headless `chati search <query>` (PR #14).** A one-shot subcommand that runs
  the SearXNG web search and prints results — no REPL, no LLM call — so scripts,
  pipelines and other machines/agents can pull fresh web facts. Reuses the same
  `SEARXNG_URLS` round-robin as `/web`. Exit codes: `2` on missing query, `1` if
  no backend is configured.

### Fixed
- **A LAN-exposed Ollama is reachable on *every* start, not just after a manual
  restart (PR #11).** When `ailocal lan on` is set, other machines must always
  reach Ollama (LAN/Tailscale) — after login autostart and reboots too. Two gaps
  broke that: `startollama` short-circuited on "already running" without checking
  the daemon was actually reachable off-localhost (so one that came up before the
  LAN marker, or with a wedged/IPv6-only socket, stayed invisible forever), and
  it applied the marker as `${OLLAMA_HOST:-…}`, letting a stale value win. Now the
  marker is authoritative on every start, and if LAN is on but the daemon isn't
  reachable on the Mac's LAN/Tailscale address, `startollama` restarts it to apply
  the bind. New `ollama_lan_reachable` helper probes the real external addresses.

## [1.14.1] - 2026-08-02

### Fixed
- **`/think` now detects reasoning models reliably.** The capability gate parsed
  `ollama show` text, whose layout shifts between CLI/server versions — on a
  client≠server setup it wrongly reported "no thinking" for capable models
  (deepseek-r1, gemma4), so `/think` refused to turn on. It now asks Ollama's
  JSON API (`/api/show` capabilities) via `model_can_think`, and stays lenient
  if the check itself cannot run so a capable model is never wrongly blocked.

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
