#!/usr/bin/env bash
set -e

sudo tee /usr/local/bin/rebuild_media >/dev/null <<'EOF'
#!/usr/bin/env bash
set -e
cd /opt/streamlab/media
docker compose up -d --build --force-recreate
EOF

sudo chmod +x /usr/local/bin/rebuild_media

exit 0
