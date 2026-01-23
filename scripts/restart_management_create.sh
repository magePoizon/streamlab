#!/usr/bin/env bash
set -e

sudo tee /usr/local/bin/restart_management >/dev/null <<'EOF'
#!/usr/bin/env bash
set -e
cd /opt/streamlab/management
docker compose restart
EOF

sudo chmod +x /usr/local/bin/restart_management

exit 0
