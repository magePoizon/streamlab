#!/usr/bin/env bash
set -e
 
# Creates executable command to quickly update the regiestered git repo...cause I'm lazy 

sudo tee /usr/local/bin/git_update_now >/dev/null <<'EOF'
#!/usr/bin/env bash
set -e
cd /opt/streamlab
git status
git add -A
if git diff --cached --quiet; then
  echo "No changes staged; nothing to commit."
  exit 0
fi
git commit -m "${*:-Update server config}"
git push
EOF

sudo chmod +x /usr/local/bin/git_update_now
