#!/usr/bin/env bash
set -e

sudo tee /usr/local/bin/update_media >/dev/null <<'EOF'
#!/usr/bin/env bash
set -e
cd /opt/streamlab/media
docker compose pull
docker compose up -d
docker image prune -f
EOF

sudo chmod +x /usr/local/bin/update_media

exit 0
