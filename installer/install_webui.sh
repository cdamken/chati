#!/bin/bash
#==============================================================================
# install_webui.sh — install / upgrade / back up / restore local OpenWebUI
#==============================================================================
# The browser UI for chati, under ~/openwebui. This is the venv install and
# the data safety net; starting and stopping it is `chati webui` / `chati stop`.
# setup.sh calls this during install and on every `chati upgrade`.
#
# Ported verbatim from the old `ailocal upgrade/backup/restore webui` so no
# hard-won fix is lost: external DATA_DIR (data survives a --force reinstall),
# secret key kept outside the repo, a backup before every upgrade, and a
# restore that integrity-checks the snapshot before touching the live DB.
#
# Why not Docker: by request. Manual install = uv venv + uv pip. Pinned to
# Python 3.11 (OpenWebUI supports 3.11/3.12 only), and uv OWNS that Python (a
# managed standalone build), so a later `brew autoremove` can't delete the
# interpreter out from under the venv — the exact failure the SearXNG venv hit.
#
# Usage:
#   install_webui.sh [--force]     install or upgrade (--force = clean reinstall)
#   install_webui.sh backup        snapshot the live data into the backup slot
#   install_webui.sh restore [--yes]  restore the snapshot over the live data
#==============================================================================
set -o pipefail

# Shared stop helper (chati_svc_stop) + CHATI_WEBUI_PROC, for --force and restore.
CHATI_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=/dev/null
source "$CHATI_DIR/chati-common.sh"

OPENWEBUI_DIR="${OPENWEBUI_DIR:-$HOME/openwebui}"
OPENWEBUI_DATA_DIR="$OPENWEBUI_DIR/data"
OPENWEBUI_VENV="${OPENWEBUI_VENV:-$OPENWEBUI_DIR/.venv}"
WEBUI_SECRET_KEY_FILE="$OPENWEBUI_DIR/.webui_secret_key"
BACKUP_SLOT="$HOME/openwebui_backups/previous"
LOG_DIR="${CHATI_LOG_DIR:-$HOME/logs}"
UPGRADE_LOG="$LOG_DIR/webui_upgrade.log"
PY_VERSION="3.11"

mkdir -p "$LOG_DIR"

log()        { echo "ℹ️  $*"; }
error_exit() { echo "❌ $1" >&2; [[ -n "${2:-}" ]] && echo "   $2" >&2; exit 1; }

check_dependencies() {
    local dep missing=()
    for dep in uv curl openssl; do
        command -v "$dep" >/dev/null 2>&1 || missing+=("$dep")
    done
    [[ ${#missing[@]} -gt 0 ]] \
        && error_exit "Missing required dependencies: ${missing[*]}" "Install them via Homebrew."
    return 0
}

# Installed open-webui version (empty if not installed).
webui_installed_version() {
    "$OPENWEBUI_VENV/bin/python3" -c \
        'import importlib.metadata as m; print(m.version("open-webui"))' 2>/dev/null
}

# Locate the LIVE OpenWebUI database. With DATA_DIR exported it lives in the
# external data dir; the venv fallback covers installs from before that fix.
find_webui_db() {
    if [[ -f "$OPENWEBUI_DATA_DIR/webui.db" ]]; then
        echo "$OPENWEBUI_DATA_DIR/webui.db"
        return 0
    fi
    find "$OPENWEBUI_VENV" -name "webui.db" -path "*open_webui/data*" 2>/dev/null | head -n 1
}

create_backup() {
    local staging="$BACKUP_SLOT.staging.$$"
    rm -rf "$staging"
    mkdir -p "$staging/data" || error_exit "Failed to create staging directory"

    # Data directory contents (uploads, vector_db, ...), if any.
    if [[ -d "$OPENWEBUI_DATA_DIR" ]] && [[ -n "$(ls -A "$OPENWEBUI_DATA_DIR" 2>/dev/null)" ]]; then
        cp -R "$OPENWEBUI_DATA_DIR/" "$staging/data/" 2>/dev/null
        # The live cp of a hot WAL-mode DB can be torn; replaced below
        # with a consistent sqlite3 snapshot.
        rm -f "$staging/data/webui.db" "$staging/data/webui.db-wal" "$staging/data/webui.db-shm"
    fi

    local db
    db=$(find_webui_db)
    if [[ -z "$db" ]]; then
        rm -rf "$staging"
        error_exit "No webui.db found in $OPENWEBUI_DATA_DIR or $OPENWEBUI_VENV — refusing to create an empty backup."
    fi
    log "Backing up database: $db"
    if command -v sqlite3 >/dev/null 2>&1; then
        sqlite3 "$db" ".backup '$staging/data/webui.db'" \
            || { rm -rf "$staging"; error_exit "sqlite3 .backup failed for $db"; }
    else
        cp "$db" "$staging/data/webui.db" \
            || { rm -rf "$staging"; error_exit "cp failed for $db"; }
    fi

    [[ -f "$WEBUI_SECRET_KEY_FILE" ]] && cp "$WEBUI_SECRET_KEY_FILE" "$staging/" 2>/dev/null

    {
        echo "previous state from $(date '+%Y-%m-%d %H:%M')"
        echo "OpenWebUI version: $(webui_installed_version || echo unknown)"
        echo "Database source: $db"
    } > "$staging/BACKUP_INFO.txt"

    # Swap: only now does the old snapshot go away.
    mkdir -p "$(dirname "$BACKUP_SLOT")"
    rm -rf "$BACKUP_SLOT"
    mv "$staging" "$BACKUP_SLOT"
    log "Backup saved: $BACKUP_SLOT ($(du -sh "$BACKUP_SLOT" 2>/dev/null | cut -f1))"
}

restore_backup() {
    local assume_yes="$1"
    if [[ ! -f "$BACKUP_SLOT/data/webui.db" ]]; then
        error_exit "No backup to restore (slot: $BACKUP_SLOT)" "Run 'install_webui.sh backup' to create one."
    fi

    echo "Backup slot: $(head -1 "$BACKUP_SLOT/BACKUP_INFO.txt" 2>/dev/null || echo unknown)" >&2

    # Validate the backup is a healthy, NON-EMPTY SQLite file BEFORE touching
    # the live DB. With a single slot, restoring a corrupt or empty backup over
    # the live copy would lose everything — verify first, abort if bad. Two
    # checks: PRAGMA integrity_check catches corruption, but a 0-byte file
    # reports "ok" (SQLite treats empty as a valid empty DB) — so also require a
    # real schema (>=1 table).
    if command -v sqlite3 >/dev/null 2>&1; then
        local check tables
        check=$(sqlite3 "$BACKUP_SLOT/data/webui.db" "PRAGMA integrity_check;" 2>&1 | head -1)
        if [[ "$check" != "ok" ]]; then
            error_exit "Backup database failed integrity check (\"$check\")." \
                "Refusing to restore over your live data. The live DB is untouched."
        fi
        tables=$(sqlite3 "$BACKUP_SLOT/data/webui.db" \
            "SELECT count(*) FROM sqlite_master WHERE type='table';" 2>/dev/null)
        if [[ -z "$tables" || "$tables" -lt 1 ]]; then
            error_exit "Backup database is empty (no tables) — refusing to restore over your live data." \
                "The live DB is untouched."
        fi
    fi

    if [[ "$assume_yes" != "--yes" ]]; then
        echo "WARNING: This will overwrite your current OpenWebUI data!"
        echo -n "Continue? (y/N): "
        read -r confirm
        [[ ! "$confirm" =~ ^[Yy]$ ]] && return 1
    fi

    chati_svc_stop "$CHATI_WEBUI_PROC" "OpenWebUI"

    log "Restoring previous state..."
    mkdir -p "$OPENWEBUI_DATA_DIR"

    # Keep a recovery copy of the current live DB OUTSIDE the data dir, so the
    # clean-replace below can't touch it. (DATA_DIR is exported so OpenWebUI
    # reads from $OPENWEBUI_DATA_DIR/webui.db.)
    local live_db="$OPENWEBUI_DATA_DIR/webui.db"
    local pre_restore="$OPENWEBUI_DIR/webui.db.pre-restore"
    [[ -f "$live_db" ]] && cp "$live_db" "$pre_restore" 2>/dev/null

    # Faithful restore: REPLACE the data dir contents, don't merge into them. A
    # plain `cp -R` left orphan files from the old state behind (uploads/vector_db
    # the backup didn't have), so the restored state wasn't what was backed up.
    # Wipe then copy the whole snapshot (includes webui.db — integrity-checked above).
    rm -rf "$OPENWEBUI_DATA_DIR"
    mkdir -p "$OPENWEBUI_DATA_DIR"
    cp -R "$BACKUP_SLOT/data/." "$OPENWEBUI_DATA_DIR/" \
        || error_exit "Failed to restore data into $OPENWEBUI_DATA_DIR"
    log "Restored $BACKUP_SLOT/data → $OPENWEBUI_DATA_DIR (previous live DB kept at $pre_restore)"

    [[ -f "$BACKUP_SLOT/.webui_secret_key" ]] && cp "$BACKUP_SLOT/.webui_secret_key" "$WEBUI_SECRET_KEY_FILE"

    log "Restore completed. Start it again with: chati webui"
}

upgrade_webui() {
    check_dependencies
    local force="$1"

    local before
    before=$(webui_installed_version)

    # ALWAYS snapshot before touching anything. Every upgrade is backed up; if
    # the result is broken, run `install_webui.sh restore`.
    if [[ -n "$(find_webui_db)" ]]; then
        create_backup
    fi

    log "Starting OpenWebUI install/upgrade (installed: ${before:-none}, force: ${force:---no})..."
    mkdir -p "$OPENWEBUI_DIR"

    if [[ "$force" == "--force" ]]; then
        chati_svc_stop "$CHATI_WEBUI_PROC" "OpenWebUI"
        rm -rf "$OPENWEBUI_VENV" "$OPENWEBUI_DIR/pyproject.toml" "$OPENWEBUI_DIR/requirements.txt"
    fi

    # Have uv own the Python BEFORE building the venv: a managed standalone
    # CPython that `brew autoremove` can't delete (fast no-op once present).
    uv python install "$PY_VERSION" >> "$UPGRADE_LOG" 2>&1 \
        || error_exit "Failed to install uv-managed Python $PY_VERSION (see $UPGRADE_LOG)"

    # All project work in a subshell so the caller's cwd never changes.
    (
        cd "$OPENWEBUI_DIR" || exit 1
        if [[ ! -f pyproject.toml ]]; then
            uv init --python="$PY_VERSION" . >> "$UPGRADE_LOG" 2>&1 || exit 2
        fi
        if [[ ! -d "$OPENWEBUI_VENV" ]]; then
            uv venv --python "$PY_VERSION" >> "$UPGRADE_LOG" 2>&1 || exit 3
        fi
        install_cmd=("uv" "pip" "install" "--python" "$OPENWEBUI_VENV/bin/python3")
        [[ "$force" == "--force" ]] && install_cmd+=("--force-reinstall")
        # --refresh bypasses uv's cache so "latest" really means latest.
        install_cmd+=("--refresh" "--upgrade" "open-webui")
        echo "Running: ${install_cmd[*]}" >&2
        "${install_cmd[@]}" >> "$UPGRADE_LOG" 2>&1 || exit 4
    )
    local rc=$?
    case $rc in
        1) error_exit "Cannot cd to $OPENWEBUI_DIR" ;;
        2) error_exit "Failed to init uv project" ;;
        3) error_exit "Failed to create venv" ;;
        4) log "OpenWebUI install/upgrade failed — see $UPGRADE_LOG. Your data is safe; run 'install_webui.sh restore' if needed."; return 1 ;;
    esac

    local after
    after=$(webui_installed_version)
    if [[ -n "$before" && "$before" == "$after" ]]; then
        # Make the no-op VISIBLE — a silent "successful" no-op is how --force
        # became the only upgrade that ever worked.
        log "OpenWebUI is still at $after — no newer version was installed."
        log "If PyPI has a newer release, try: install_webui.sh --force"
    else
        log "OpenWebUI installed/upgraded: ${before:-none} → ${after:-unknown}"
        log "If anything misbehaves: 'install_webui.sh restore' brings back the pre-upgrade state."
    fi
    return 0
}

case "${1:-}" in
    backup)      check_dependencies; create_backup ;;
    restore)     restore_backup "${2:-}" ;;
    --force)     upgrade_webui --force ;;
    ""|--update|upgrade|install) upgrade_webui "" ;;
    *)           error_exit "Unknown argument: $1" "Usage: install_webui.sh [--force | backup | restore [--yes]]" ;;
esac
