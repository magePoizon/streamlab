#!/usr/bin/env bash
set -e

sudo tee /usr/local/bin/update_management >/dev/null <<'EOF'
#!/usr/bin/env bash
set -e
cd /opt/streamlab/management
docker compose pull
docker compose up -d
EOF

sudo chmod +x /usr/local/bin/update_management

exit 0
