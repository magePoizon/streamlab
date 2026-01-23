#!/usr/bin/env bash
set -e

sudo tee /usr/local/bin/restart_monitoring >/dev/null <<'EOF'
#!/usr/bin/env bash
set -e
cd /opt/streamlab/monitoring
docker compose restart
EOF

sudo chmod +x /usr/local/bin/restart_monitoring

exit 0
