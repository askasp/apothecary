#!/usr/bin/env bash
set -euo pipefail

# Apothecary Platform Setup Script
# Usage: curl -sSL https://raw.githubusercontent.com/.../setup.sh | bash -s -- myapp.example.com
#
# Sets up a VM with all dependencies for running Apothecary in platform mode:
# Erlang, Elixir, Node, Postgres, Caddy, git
#
# Domain is stored in /etc/apothecary/env and can be changed later.

DOMAIN="${1:-}"
if [ -z "$DOMAIN" ]; then
  echo "Usage: $0 <platform-domain>"
  echo "  e.g. $0 myapp.example.com"
  exit 1
fi

echo "==> Apothecary Platform Setup"
echo "    Domain: $DOMAIN"
echo ""

# --- Detect OS ---
if [ -f /etc/os-release ]; then
  . /etc/os-release
  OS_ID="${ID}"
else
  echo "ERROR: Cannot detect OS. This script supports Ubuntu/Debian."
  exit 1
fi

if [[ "$OS_ID" != "ubuntu" && "$OS_ID" != "debian" ]]; then
  echo "ERROR: This script supports Ubuntu/Debian. Detected: $OS_ID"
  exit 1
fi

echo "==> Detected OS: $OS_ID"

# --- System packages ---
echo "==> Updating packages..."
sudo apt-get update -qq

echo "==> Installing base dependencies..."
sudo apt-get install -y -qq \
  git curl wget gnupg2 apt-transport-https \
  build-essential autoconf m4 libncurses5-dev \
  libssl-dev libwxgtk3.2-dev libgl1-mesa-dev \
  libglu1-mesa-dev libpng-dev unzip inotify-tools

# --- Erlang + Elixir via asdf ---
echo "==> Installing Erlang and Elixir..."
if ! command -v asdf &>/dev/null; then
  git clone https://github.com/asdf-vm/asdf.git ~/.asdf --branch v0.14.0
  echo '. "$HOME/.asdf/asdf.sh"' >> ~/.bashrc
  export PATH="$HOME/.asdf/shims:$HOME/.asdf/bin:$PATH"
fi

source "$HOME/.asdf/asdf.sh" 2>/dev/null || true

if ! asdf plugin list | grep -q erlang; then
  asdf plugin add erlang
fi
if ! asdf plugin list | grep -q elixir; then
  asdf plugin add elixir
fi

ERLANG_VERSION="27.2"
ELIXIR_VERSION="1.18.1-otp-27"

echo "==> Installing Erlang $ERLANG_VERSION (this may take a while)..."
asdf install erlang "$ERLANG_VERSION" || true
asdf global erlang "$ERLANG_VERSION"

echo "==> Installing Elixir $ELIXIR_VERSION..."
asdf install elixir "$ELIXIR_VERSION" || true
asdf global elixir "$ELIXIR_VERSION"

# --- Node.js ---
echo "==> Installing Node.js..."
if ! asdf plugin list | grep -q nodejs; then
  asdf plugin add nodejs
fi
NODE_VERSION="22.12.0"
asdf install nodejs "$NODE_VERSION" || true
asdf global nodejs "$NODE_VERSION"

# --- PostgreSQL ---
echo "==> Installing PostgreSQL..."
sudo apt-get install -y -qq postgresql postgresql-contrib

sudo systemctl enable postgresql
sudo systemctl start postgresql

# Create apothecary role (idempotent)
sudo -u postgres psql -c "DO \$\$
BEGIN
  IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'apothecary') THEN
    CREATE ROLE apothecary WITH LOGIN CREATEDB PASSWORD 'apothecary';
  END IF;
END
\$\$;" 2>/dev/null || true

echo "==> PostgreSQL configured"

# --- Caddy ---
echo "==> Installing Caddy..."
sudo apt-get install -y -qq debian-keyring debian-archive-keyring
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | sudo gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg 2>/dev/null || true
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | sudo tee /etc/apt/sources.list.d/caddy-stable.list >/dev/null
sudo apt-get update -qq
sudo apt-get install -y -qq caddy

# Configure Caddy for admin API + wildcard cert
echo "==> Configuring Caddy..."
sudo mkdir -p /etc/caddy
sudo tee /etc/caddy/Caddyfile > /dev/null <<EOF
{
    admin localhost:2019
}

# Wildcard cert for platform domain
*.$DOMAIN {
    tls {
        dns cloudflare {env.CF_API_TOKEN}
    }
    reverse_proxy localhost:4005
}
EOF

sudo systemctl enable caddy
sudo systemctl restart caddy
echo "==> Caddy configured"

# --- Apothecary ---
APOTHECARY_DIR="/opt/apothecary"
echo "==> Setting up Apothecary..."

if [ ! -d "$APOTHECARY_DIR" ]; then
  sudo git clone https://github.com/knute-labs/apothecary.git "$APOTHECARY_DIR"
  sudo chown -R "$USER:$USER" "$APOTHECARY_DIR"
else
  cd "$APOTHECARY_DIR"
  git pull --ff-only || true
fi

cd "$APOTHECARY_DIR"
mix local.hex --force
mix local.rebar --force
mix deps.get
MIX_ENV=prod mix compile

# --- Environment file ---
echo "==> Writing environment config..."
sudo mkdir -p /etc/apothecary
sudo tee /etc/apothecary/env > /dev/null <<EOF
PLATFORM_DOMAIN=$DOMAIN
PORT=4005
MIX_ENV=prod
SECRET_KEY_BASE=$(openssl rand -base64 64 | tr -d '\n' | head -c 64)
PHX_HOST=$DOMAIN
EOF

sudo chmod 600 /etc/apothecary/env

# --- Systemd service ---
echo "==> Creating systemd service..."
sudo tee /etc/systemd/system/apothecary.service > /dev/null <<EOF
[Unit]
Description=Apothecary Platform
After=network.target postgresql.service caddy.service
Requires=postgresql.service

[Service]
Type=simple
User=$USER
Group=$USER
WorkingDirectory=$APOTHECARY_DIR
EnvironmentFile=/etc/apothecary/env
ExecStart=/bin/bash -lc 'mix phx.server'
Restart=on-failure
RestartSec=5
Environment=HOME=$HOME

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable apothecary
sudo systemctl start apothecary

echo ""
echo "=========================================="
echo "  Apothecary Platform Setup Complete!"
echo "=========================================="
echo ""
echo "  Domain: $DOMAIN"
echo "  Dashboard: http://$DOMAIN:4005"
echo ""
echo "  Next steps:"
echo "  1. Point DNS for *.$DOMAIN to this server's IP"
echo "  2. If using Cloudflare DNS for TLS, set CF_API_TOKEN in /etc/apothecary/env"
echo "  3. Restart: sudo systemctl restart apothecary"
echo ""
echo "  Config: /etc/apothecary/env"
echo "  Logs:   journalctl -u apothecary -f"
echo "  Caddy:  /etc/caddy/Caddyfile"
echo ""
