#!/usr/bin/env bash
set -e

sudo tee /usr/local/bin/rebuild_monitoring >/dev/null <<'EOF'
#!/usr/bin/env bash
set -e
cd /opt/streamlab/monitoring
docker compose up -d --build --force-recreate
EOF

sudo chmod +x /usr/local/bin/rebuild_monitoring

exit 0
