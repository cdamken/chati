# SearXNG Web Search Backend

`chati`'s `/w` (web search) and the decomposition-RAG pipeline rely on a
**self-hosted SearXNG instance**. We use SearXNG instead of scraping DuckDuckGo
directly because DDG triggers an anti-bot challenge after ~50 sustained
queries — a death sentence for batch runs like `/s` over hundreds of lines.

SearXNG is a metasearch aggregator: it queries many engines in parallel
(Google, DDG, Brave, Bing, Mojeek, Wikipedia, …) and returns clean JSON.
Because each upstream sees only a slice of our traffic, no individual engine
rate-limits us.

## Architecture

```
chati (Mac)
   │
   │  HTTPS + Basic Auth
   ▼
https://cloud.damken.com/searx
   │
   │  Apache reverse proxy
   ▼
127.0.0.1:8889  (SearXNG, systemd-managed)
   │
   │  parallel queries
   ▼
Google · DDG · Brave · Bing · Mojeek · Wikipedia · …
```

Externally only port 443 is exposed (Apache). SearXNG listens on
`127.0.0.1:8889` and is reached only via the Apache vhost, so no extra
firewall holes are needed.

## Client-side setup (your Mac)

`web_search.py` reads three env vars:

| Variable        | Required                  | Default                                    |
|-----------------|---------------------------|--------------------------------------------|
| `SEARXNG_URL`   | yes (defaults in lib_chat.sh) | `https://cloud.damken.com/searx`       |
| `SEARXNG_USER`  | yes if instance has auth  | unset                                      |
| `SEARXNG_PASS`  | yes if instance has auth  | unset                                      |

Put the credentials in `~/.zshrc` so every shell has them:

```bash
export SEARXNG_USER=carlos
export SEARXNG_PASS='<your-password>'
```

`SEARXNG_URL` is already exported by `lib_chat.sh` with the production
default — override it only if you self-host elsewhere.

Quick check:

```bash
curl -u "$SEARXNG_USER:$SEARXNG_PASS" \
  "$SEARXNG_URL/search?q=hello&format=json" | jq '.results | length'
```

If you get a positive number, you're set.

## Server-side install (Ubuntu / Debian)

These steps are what was done on `cloud.damken.com`. They assume:

- Ubuntu 20.04+ with Apache 2 + Let's Encrypt SSL already running.
- Apache modules `proxy`, `proxy_http`, `ssl`, `auth_basic`, `authn_file`,
  `authz_user`, `rewrite` enabled.
- Passwordless sudo for the deploy user.

### 1. Python 3.11 via `uv` (no PPA needed)

The deadsnakes PPA is empty for focal (Ubuntu 20.04 reached EOL May 2025).
`uv` downloads pre-built CPython binaries — works everywhere, no compile:

```bash
curl -LsSf https://astral.sh/uv/install.sh | sh
sudo cp ~/.local/bin/uv /usr/local/bin/uv
sudo uv python install 3.11
```

### 2. Dedicated service user and SearXNG checkout

```bash
sudo useradd -r -m -d /opt/searxng -s /bin/bash searxng
sudo -u searxng git clone https://github.com/searxng/searxng \
    /opt/searxng/searxng-repo
sudo -u searxng -- bash -c \
    'cd /opt/searxng && /usr/local/bin/uv venv --python 3.11 .venv'
```

### 3. Install dependencies

SearXNG's `setup.py` imports `msgspec` at module load, which breaks
`--no-build-isolation`. Install requirements first, then the package with
`--no-deps`:

```bash
sudo -u searxng -- bash -c '
  cd /opt/searxng && source .venv/bin/activate &&
  /usr/local/bin/uv pip install --upgrade pip wheel setuptools &&
  /usr/local/bin/uv pip install \
    -r ./searxng-repo/requirements.txt \
    -r ./searxng-repo/requirements-server.txt &&
  /usr/local/bin/uv pip install --no-build-isolation --no-deps \
    -e ./searxng-repo
'
```

### 4. Configuration — `/etc/searxng/settings.yml`

```bash
sudo mkdir -p /etc/searxng
SECRET=$(openssl rand -hex 32)
sudo tee /etc/searxng/settings.yml > /dev/null <<EOF
use_default_settings: true

general:
  instance_name: "damkencloud-searx"
  privacypolicy_url: false
  donation_url: false
  contact_url: false
  enable_metrics: false

server:
  bind_address: "127.0.0.1"
  port: 8889
  base_url: "https://cloud.damken.com/searx/"
  secret_key: "$SECRET"
  limiter: false
  public_instance: false
  image_proxy: false
  http_protocol_version: "1.0"
  method: "GET"

search:
  safe_search: 0
  autocomplete: ""
  default_lang: ""
  formats:
    - html
    - json

ui:
  static_use_hash: true

outgoing:
  request_timeout: 5.0
  max_request_timeout: 15.0
  pool_connections: 100
  pool_maxsize: 20
  enable_http2: true

redis:
  url: false
EOF
sudo chown searxng:searxng /etc/searxng/settings.yml
```

Key knobs:
- `server.port: 8889` — change if 8889 is busy (8888 was already used by
  `otelcol-contrib` on this server).
- `search.formats: [html, json]` — **JSON is what chati needs**, do not
  omit it.
- `server.base_url` — must match the Apache path you'll expose.

### 5. systemd service — `/etc/systemd/system/searxng.service`

```bash
sudo tee /etc/systemd/system/searxng.service > /dev/null <<'EOF'
[Unit]
Description=SearXNG metasearch
After=network.target

[Service]
User=searxng
Group=searxng
WorkingDirectory=/opt/searxng/searxng-repo
Environment=SEARXNG_SETTINGS_PATH=/etc/searxng/settings.yml
ExecStart=/opt/searxng/.venv/bin/python -m searx.webapp
Restart=on-failure
RestartSec=5
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF
sudo systemctl daemon-reload
sudo systemctl enable --now searxng
```

Local sanity check:

```bash
curl -s "http://127.0.0.1:8889/search?q=hello&format=json" | jq '.results | length'
```

### 6. Basic Auth — htpasswd

Generate a strong password and store it for the Mac side:

```bash
PASS=$(openssl rand -base64 24 | tr -d '=+/' | cut -c1-32)
sudo htpasswd -bc /etc/apache2/searx.htpasswd carlos "$PASS"
echo "Password (save this!): $PASS"
```

### 7. Apache reverse proxy

Add this block to your SSL vhost **before** the catch-all
`Alias / /var/www/owncloud/` line (on `cloud.damken.com` that lives in
`/etc/apache2/sites-available/default-ssl.conf`):

```apache
# SearXNG metasearch (reverse proxy to localhost:8889)
<Location /searx>
    AuthType Basic
    AuthName "SearXNG"
    AuthUserFile /etc/apache2/searx.htpasswd
    Require valid-user
    ProxyPreserveHost On
</Location>
ProxyPass /searx http://127.0.0.1:8889/searx
ProxyPassReverse /searx http://127.0.0.1:8889/searx
```

Then:

```bash
sudo apache2ctl configtest        # must print "Syntax OK"
sudo systemctl reload apache2
```

End-to-end test from your Mac:

```bash
curl -u 'carlos:<password>' \
  'https://cloud.damken.com/searx/search?q=hello&format=json' \
  | jq '.results | length'
```

## Maintenance

### Logs

```bash
ssh -p 2222 carlos@cloud.damken.com 'sudo journalctl -u searxng -f'
```

### Restart

```bash
ssh -p 2222 carlos@cloud.damken.com 'sudo systemctl restart searxng'
```

### Status / health

```bash
ssh -p 2222 carlos@cloud.damken.com \
  'sudo systemctl status searxng --no-pager; \
   curl -sf http://127.0.0.1:8889/healthz && echo " — healthz OK"'
```

### Upgrade to latest SearXNG

```bash
ssh -p 2222 carlos@cloud.damken.com '
  cd /opt/searxng/searxng-repo &&
  sudo -u searxng git pull &&
  sudo -u searxng -- bash -c "
    cd /opt/searxng && source .venv/bin/activate &&
    /usr/local/bin/uv pip install \
      -r ./searxng-repo/requirements.txt \
      -r ./searxng-repo/requirements-server.txt &&
    /usr/local/bin/uv pip install --no-build-isolation --no-deps \
      -e ./searxng-repo
  " &&
  sudo systemctl restart searxng
'
```

### Rotate the Basic Auth password

```bash
ssh -p 2222 carlos@cloud.damken.com 'sudo htpasswd /etc/apache2/searx.htpasswd carlos'
# update ~/.zshrc on the Mac with the new value
```

### Apache vhost rollback

A `.bak.<timestamp>` copy of `default-ssl.conf` was written before the
`/searx` block was inserted. To revert:

```bash
ssh -p 2222 carlos@cloud.damken.com '
  ls /etc/apache2/sites-available/default-ssl.conf.bak.* | tail -1
  # sudo cp <that file> /etc/apache2/sites-available/default-ssl.conf
  # sudo systemctl reload apache2
'
```

## Troubleshooting

| Symptom                                            | Diagnosis                            | Fix                                                       |
|----------------------------------------------------|--------------------------------------|-----------------------------------------------------------|
| `Error: cannot reach SearXNG`                      | Service down or wrong URL            | `sudo systemctl status searxng`; verify `SEARXNG_URL`     |
| `Error: SearXNG rejected the credentials (401)`    | Wrong user/pass in env               | Re-export `SEARXNG_USER` / `SEARXNG_PASS`                 |
| `Error: SearXNG returned non-JSON (auth challenge?)` | Apache auth challenge HTML returned | Same as 401 — bad creds                                   |
| Results array is `[]`                              | All engines returned no hits         | Try a less specific query; check `journalctl -u searxng`  |
| systemd loops "active (running)" but `/healthz` 5xx | Cache / startup error                | `sudo rm -rf /opt/searxng/.cache && sudo systemctl restart searxng` |

## Why these specific choices

- **`uv` instead of system Python**: deadsnakes PPA is empty for focal
  EOL. `uv` is a single static binary, downloads pre-built CPython,
  no compile, no surprises.
- **Path-based (`/searx`) instead of a subdomain**: matches the existing
  pattern (`/carlos`, `/ren`, `/abordallo`) on this server. No new DNS
  records, no new Let's Encrypt cert.
- **Basic Auth instead of OAuth/SSO**: simplest thing that works for one
  user with a rotating IP.
- **Port 8889 instead of 8888**: 8888 is occupied by `otelcol-contrib`
  on this server.
- **`--no-deps -e .` install**: SearXNG's `setup.py` imports `msgspec`
  before it's a build-isolation dep, so we install requirements first
  then layer the editable package on top without re-resolving.
