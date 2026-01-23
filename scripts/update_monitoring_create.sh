#!/usr/bin/env bash
set -e

sudo tee /usr/local/bin/update_monitoring >/dev/null <<'EOF'
#!/usr/bin/env bash
set -e
cd /opt/streamlab/monitoring
docker compose pull
docker compose up -d
EOF

sudo chmod +x /usr/local/bin/update_monitoring

exit 0
