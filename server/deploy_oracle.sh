#!/usr/bin/env bash
# Tunefy relay — one-shot setup for Oracle Cloud Always Free (Ubuntu 22.04 ARM).
# Run as the `ubuntu` user after SSHing into the VM:
#   bash deploy_oracle.sh
set -euo pipefail

REPO="https://raw.githubusercontent.com/grandelagbanou28-gif/Tunefy/main/server"
APP_DIR="$HOME/tunefy-relay"
RELAY_KEY="${RELAY_KEY:-ef18836a78d502fd085b90c1ae497419919a19ce5234bc13}"
PORT="${PORT:-8080}"

echo "==> Installing system packages"
sudo apt-get update -y
sudo apt-get install -y python3 python3-pip python3-venv curl

echo "==> Creating virtualenv and installing Python deps"
mkdir -p "$APP_DIR"
cd "$APP_DIR"
python3 -m venv .venv
.venv/bin/pip install --upgrade pip
.venv/bin/pip install fastapi 'uvicorn[standard]' httpx

echo "==> Installing / updating yt-dlp"
.venv/bin/pip install -U yt-dlp
sudo ln -sf "$APP_DIR/.venv/bin/yt-dlp" /usr/local/bin/yt-dlp

echo "==> Downloading relay from GitHub"
curl -fsSL "$REPO/main.py" -o "$APP_DIR/main.py"

echo "==> Installing systemd unit"
sudo tee /etc/systemd/system/tunefy-relay.service >/dev/null <<EOF
[Unit]
Description=Tunefy audio relay (yt-dlp)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=$USER
WorkingDirectory=$APP_DIR
Environment=PORT=$PORT
Environment=RELAY_KEY=$RELAY_KEY
Environment=YT_DLP_BIN=$APP_DIR/.venv/bin/yt-dlp
ExecStart=$APP_DIR/.venv/bin/python -m uvicorn main:app --host 0.0.0.0 --port $PORT
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable --now tunefy-relay

echo "==> Daily yt-dlp auto-update (cron)"
( crontab -l 2>/dev/null || true; echo "15 3 * * * $APP_DIR/.venv/bin/pip install -U -q yt-dlp && sudo systemctl restart tunefy-relay" ) | crontab -

echo "==> Opening port $PORT in the firewall"
sudo ufw allow ${PORT}/tcp || true

echo "==> Done. Check with:"
echo "    curl http://127.0.0.1:$PORT/health"
echo "Then open TCP $PORT in Oracle Cloud: Instance -> Subnet -> Ingress Rules."
echo "Finally rebuild the app with:"
echo "    --dart-define=RELAY_BASE_URL=http://<PUBLIC_IP>:$PORT"
