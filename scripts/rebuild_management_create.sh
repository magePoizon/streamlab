#!/usr/bin/env bash
set -e

sudo tee /usr/local/bin/rebuild_management >/dev/null <<'EOF'
#!/usr/bin/env bash
set -e
cd /opt/streamlab/management
docker compose up -d --build --force-recreate
EOF

sudo chmod +x /usr/local/bin/rebuild_management

exit 0
