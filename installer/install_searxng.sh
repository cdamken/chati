#!/bin/bash
#==============================================================================
# install_searxng.sh — native (no-Docker) local SearXNG for chati's /web
#==============================================================================
# Stands up a personal SearXNG under ~/searxng so chati can round-robin
# web search across it AND your cloud instance (two source IPs → double
# the upstream rate-limit budget). Managed afterwards by `ailocal
# start|stop|status searxng`.
#
# Why not Docker: by request. This is the supported manual install —
# git clone + venv + granian + settings.yml. Pinned to Python 3.12
# (SearXNG doesn't support 3.14 yet).
#==============================================================================
set -o pipefail

SEARXNG_DIR="$HOME/searxng"
SEARXNG_SRC="$SEARXNG_DIR/src"
SEARXNG_VENV="$SEARXNG_DIR/.venv"
SEARXNG_SETTINGS="$SEARXNG_DIR/settings.yml"
PORT="${SEARXNG_LOCAL_PORT:-8890}"

echo "🚀 Installing local SearXNG under $SEARXNG_DIR (port $PORT)..."

for dep in git uv curl openssl; do
    command -v "$dep" >/dev/null 2>&1 || { echo "❌ Missing dependency: $dep"; exit 1; }
done

mkdir -p "$SEARXNG_DIR" "$HOME/logs"

# 1. Source (shallow clone; pull if already there).
if [[ -d "$SEARXNG_SRC/.git" ]]; then
    echo "📥 Updating existing clone..."
    git -C "$SEARXNG_SRC" pull --ff-only || echo "   (pull skipped)"
else
    echo "📥 Cloning SearXNG..."
    git clone --depth 1 https://github.com/searxng/searxng "$SEARXNG_SRC" || exit 1
fi

# 2. venv on Python 3.12 (3.14 breaks SearXNG's deps).
echo "🐍 Creating venv (Python 3.12)..."
uv venv --python 3.12 "$SEARXNG_VENV" || exit 1

# 3. Runtime + server (granian) deps. NOT `pip install .` — SearXNG's
#    setup.py imports the package (needs msgspec) at build time, so it's
#    run from the source tree with deps installed instead.
echo "📦 Installing dependencies (this can take a few minutes)..."
uv pip install --python "$SEARXNG_VENV/bin/python" -U pip setuptools wheel >/dev/null 2>&1
uv pip install --python "$SEARXNG_VENV/bin/python" \
    -r "$SEARXNG_SRC/requirements.txt" -r "$SEARXNG_SRC/requirements-server.txt" || exit 1

# 4. Settings: JSON format ON (chati needs it), limiter OFF (personal
#    instance — else it bot-blocks our own calls), bound to localhost.
if [[ ! -f "$SEARXNG_SETTINGS" ]]; then
    echo "⚙️  Writing settings.yml..."
    umask 077
    cat > "$SEARXNG_SETTINGS" <<EOF
use_default_settings: true
server:
  secret_key: "$(openssl rand -hex 32)"
  bind_address: "127.0.0.1"
  port: $PORT
  limiter: false
  public_instance: false
search:
  formats:
    - html
    - json
EOF
else
    echo "⚙️  Keeping existing settings.yml"
fi

# 5. Smoke test. searx is NOT installed as a package (see step 3) — it's
#    imported from the source tree, so verify it the SAME way ailocal runs
#    it at startup: cwd = src + PYTHONPATH = src. A bare `python -c "import
#    searx"` fails with ModuleNotFoundError even on a perfectly good install.
echo "🔎 Verifying import..."
( cd "$SEARXNG_SRC" && PYTHONPATH="$SEARXNG_SRC" "$SEARXNG_VENV/bin/python" -c "import searx" ) \
    || { echo "❌ searx import failed"; exit 1; }

echo ""
echo "✅ SearXNG installed. Start it with:  ailocal start searxng"
echo "   Then add it to chati's ~/chat/.env:"
echo "     SEARXNG_URLS=\"http://127.0.0.1:$PORT, <your-cloud-searxng>\""
