#!/usr/bin/env bash
set -e

sudo tee /usr/local/bin/restart_media >/dev/null <<'EOF'
#!/usr/bin/env bash
set -e
cd /opt/streamlab/media
docker compose restart
EOF

sudo chmod +x /usr/local/bin/restart_media

exit 0
