# Stremio Homelab Server

---

**Required Services/Containers**:

### Management
- 🧭 **Portainer** — web UI to manage containers/stacks on the Docker VM
- ⏰ **watchtower** (update notifications only, no auto-updates) — alerts when images have updates
- ☁️ **cloudflared** (Cloudflare Tunnel client) — private ingress to expose services safely
- 📁 **Filebrowser** — web file manager for quick access to `/opt/streamlab`
- 📈 **Uptime Kuma** — uptime/health monitoring for services and endpoints

### Monitoring
- 📡 **Prometheus** — metrics collection for host + containers
- 🧱 **node-exporter** — host-level metrics from the Docker VM
- 🧪 **cAdvisor** — container-level metrics
- 📊 **Grafana** — dashboards for those metrics


### Media
- 🔒 **gluetun** (VPN gateway) — forces media traffic through Mullvad
- 🧿 **gost** (proxy service behind gluetun) — local proxy bound to the VPN gateway
- 🎬 **AIOStreams** — Stremio addon resolver/service
- 🚦 **StremThru** — Stremio addon proxy/manager

### External Services
- **Cloudflare - with CloudflareOne**
- **Google Cloud**
- **Mullvad VPN**
- **Real Debrid**


---

## Table of Contents
0. Architecture overview  
1. Proxmox installation + baseline  
2. Proxmox layout (VMs/LXCs + resource plan)  
3. Docker VM preparation (OS hardening + Docker)  
4. Filesystem layout (one-stop /opt/streamlab)  
5. Deploy services (management, monitoring, media)  
6. Operations (start/stop, logs, updates)  
7. Git “backup” workflow (config-as-code)  
8. Secure access (Netbird + SSH locking + Cloudflare Tunnel + Access)  
9. Cloudflare hostnames + Google SSO (Cloudflare Access)  
10. Stremio setup (Real Debrid + AIOStreams + StremThru)

---

## 0) Architecture overview

### Top level
- **Proxmox host** 
- **Netbird LXC**
- **Docker Host VM** containers:
  - Portainer + watchtower + cloudflared + Filebrowser + Uptime Kuma
  - Prometheus + Grafana + node-exporter + cAdvisor
  - gluetun + gost + AIOStreams + StremThru


### Network
- LAN subnet: `192.168.1.0/24`
- Proxmox IP: `192.168.1.10`
- Docker VM IP: `192.168.1.20`
- Ports in use (host -> service [container listen port]):
  - `9000` -> Portainer (`9000`)
  - `8081` -> Filebrowser (`80`)
  - `3003` -> Uptime Kuma (`3001`)
  - `9090` -> Prometheus (`9090`)
  - `3000` -> Grafana (`3000`)
  - `3001` -> AIOStreams via gluetun (`3000`)
  - `8082` -> gluetun LAN access (`8082`)


## Directory tree
/opt/streamlab
├── management
│   ├── portainer
│   ├── watchtower
│   ├── cloudflared
│   └── filebrowser
├── monitoring
│   ├── prometheus
│   ├── grafana
│   ├── node-exporter
│   └── cadvisor
├── media
│   ├── gluetun
│   ├── gost
│   ├── aiostreams
│   └── stremthru
├── dev
├── data
│   ├── portainer
│   ├── grafana
│   ├── prometheus
│   ├── filebrowser
│   ├── uptime-kuma
│   ├── aiostreams
│   └── stremthru
├── secrets
└── scripts


---

## 1) Install Proxmox VE (bare metal)

1. Download the Proxmox VE ISO and create a bootable USB.
2. Install Proxmox to your 1TB drive.
3. During install, assign a static IP to the Proxmox management interface:
   - `192.168.1.10`
4. After install, open:
   - `https://192.168.1.10:8006`

---

## 2) Proxmox layout: LXC + VM + resource planning

### Recommended layout (fits now + leaves room for NAS later)

#### LXC 100 — `netbird`
- vCPU: 1
- RAM: 512MB–1GB
- Disk: 4–8GB
- Purpose: private access to homelab/admin services

#### VM 200 — `streamlab`
- vCPU: 4
- RAM: 8GB
- Disk: 120GB (adjustable)
- Purpose: all Docker services in this guide


---

## 3) Prepare the Docker Host VM

### 3.1 Install Debian 12 in VM 200
- VM has its own LAN IP: `192.168.1.20`
- Install `qemu-guest-agent` during or after install. It lets Proxmox talk to the VM for clean shutdowns, IP reporting, and better backup/restore behavior.

After first login (as root), create a non-root admin user and install sudo:
```bash
apt-get update
apt-get install -y sudo
adduser <youruser>
usermod -aG sudo,docker <youruser>
```

### 3.2 OS updates + base packages
On the Docker VM:

```bash
sudo apt-get update && sudo apt-get upgrade -y
sudo apt-get install -y \
  ca-certificates curl git gnupg \
  ufw fail2ban \
  qemu-guest-agent
```

Enable guest agent service:
```bash
sudo systemctl enable --now qemu-guest-agent
```

### 3.2.1 DNS stability
If DNS breaks after reboots, ensure IPv4 resolvers are pinned and resolvconf manages `/etc/resolv.conf`.

1) Add IPv4 DNS to the interface config:
```bash
sudo nano /etc/network/interfaces
```
```plaintext
allow-hotplug ens18
iface ens18 inet static
    address 192.168.1.20/24
    gateway 192.168.1.1
    dns-nameservers 192.168.1.1 1.1.1.1
```

2) Install `resolvconf` and restart networking:
```bash
sudo apt-get update
sudo apt-get install -y resolvconf
sudo systemctl restart resolvconf
sudo systemctl restart networking
```

If DNS is broken and `apt-get update` fails, set temporary resolvers first:
```bash
sudo tee /etc/resolv.conf >/dev/null <<'EOF'
nameserver 192.168.1.1
nameserver 1.1.1.1
EOF
```

3) Verify:
```bash
cat /etc/resolv.conf
getent hosts github.com
```

### 3.2.2 Disable IPv6 on Docker 
If IPv6 issues arise

1) Create a docker daemon to set dns settings:
```bash 
sudo nano /etc/docker/daemon.json
```

```json
{
  "dns": ["1.1.1.1", "1.0.0.1", "9.9.9.9"],
  "ipv6": false
}
```

2) Restart docker:
```bash 
sudo systemctl restart docker
```

3) Verify
```bash 
sudo systemctl status docker
```


### 3.3 Install Docker + Compose

```plaintext 
https://docs.docker.com/engine/install/debian/#install-using-the-repository
```

After Docker is installed:
```bash
sudo usermod -aG docker "$USER"
newgrp docker
docker version
docker compose version
```

---

## 4) Filesystem layout (`/opt/streamlab`)

On the Docker VM:

```bash
sudo mkdir -p /opt/streamlab
sudo chown -R "$USER:$USER" /opt/streamlab

cd /opt/streamlab
mkdir -p management monitoring media dev \
         data/{portainer,grafana,prometheus,filebrowser,uptime-kuma,aiostreams,stremthru} \
         secrets \
         scripts
```

### What goes where
- `management/`, `monitoring/`, `media/`, `dev/` → docker-compose files + configs
- `data/**` → persistent application data
- `secrets/**` → tokens/keys/env files

Create a shared network for the containers to speak to each other:
```bash
docker network create containers_network
```

---

## 5) Deploy the services

### Stack A — Management (Portainer + watchtower + cloudflared + Filebrowser)

#### Portainer setup
- Required: `/opt/streamlab/data/portainer`
- Owner: root by default (Portainer runs as root). If you see write errors, `chown` this folder to the container UID.

#### Watchtower setup
Create a Discord webhook:
1. Discord → Server Settings → Integrations → Webhooks → New Webhook.
2. Copy the webhook URL.

Discord gives you a webhook like:
- `https://discord.com/api/webhooks/TOKEN/WEBHOOKID`

Shoutrrr expects:
- `discord://TOKEN@WEBHOOKID`

**File:** `/opt/streamlab/secrets/watchtower.env`

```env
# Put TOKEN first, then WEBHOOKID
WATCHTOWER_NOTIFICATION_URL=discord://ENTER_TOKEN@ENTER_WEBHOOKID?splitlines=no
```

#### Cloudflared setup (Cloudflare Tunnel)
This runs the Cloudflare Tunnel agent.

Configure Cloudflare Tunnel:
Zero Trust -> Networks -> Connectors 
Add one of the services as the "Route Tunnel" host e.g. portainer.YOUR_DOMAIN - http://portainer:9000

Setup Google IdP:
https://developers.cloudflare.com/cloudflare-one/integrations/identity-providers/google/

Add Google IdP setup to "Applications"
Zero Trust -> Applications


**File:** `/opt/streamlab/secrets/core.env`

```env
TUNNEL_TOKEN=PASTE_YOUR_CLOUDFLARE_TUNNEL_TOKEN_HERE
```

#### Filebrowser setup
Make filebrowser read only, so it runs as the generic read-only user you created - UID 1000. 
This is also defined in the volume read "/srv:ro"


```bash
sudo mkdir -p /opt/streamlab/data/filebrowser
sudo chown -R 1000:1000 /opt/streamlab/data/filebrowser
sudo chmod -R 775 /opt/streamlab/data/filebrowser
```

- Once up and running, change admin password:
```bash
docker stop filebrowser

docker run --rm \
  -v /opt/streamlab/data/filebrowser:/database \
  filebrowser/filebrowser:latest \
  users update admin \
  --database /database/filebrowser.db \
  --password <ENTER_PASSWORD>
```

#### Uptime-Kuma Setup

```bash
sudo mkdir -p /opt/streamlab/data/uptime-kuma
sudo chown -R 1000:1000 /opt/streamlab/data/uptime-kuma
sudo chmod -R 775 /opt/streamlab/data/uptime-kuma
```


#### Management compose file
**File:** `/opt/streamlab/management/docker-compose.yml`

```yaml
services:
  portainer:
    image: portainer/portainer-ce:latest
    container_name: portainer
    restart: unless-stopped
    # LAN access
    ports:
      - "9000:9000"
    networks:
      - containers_network
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - /opt/streamlab/data/portainer:/data
    labels:
      - "com.centurylinklabs.watchtower.enable=true"

  watchtower:
    image: containrrr/watchtower:latest
    container_name: watchtower
    restart: unless-stopped
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
    env_file:
      - /opt/streamlab/secrets/watchtower.env
    environment:
      WATCHTOWER_NOTIFICATIONS: shoutrrr
      WATCHTOWER_NOTIFICATION_TEMPLATE: "@everyone {{range .}}{{.Message}}{{println}}{{end}}"
      WATCHTOWER_NOTIFICATION_SKIP_TITLE: "true"
      DOCKER_API_VERSION: "1.44"
    command: >
      --monitor-only
      --label-enable
      --schedule "0 30 4 * * *"
      --cleanup
    labels:
      - "com.centurylinklabs.watchtower.enable=true"

  cloudflared:
    image: cloudflare/cloudflared:latest
    container_name: cloudflared
    restart: unless-stopped
    dns:
      - 1.1.1.1
      - 1.0.0.1
    command: tunnel --no-autoupdate run
    env_file:
      - /opt/streamlab/secrets/core.env
    networks:
      - containers_network
    labels:
      - "com.centurylinklabs.watchtower.enable=true"

  filebrowser:
    image: filebrowser/filebrowser:latest
    container_name: filebrowser
    restart: unless-stopped
    # LAN access
    ports:
      - "8081:80"
    networks:
      - containers_network
    volumes:
      - /opt/streamlab:/srv:ro
      - /opt/streamlab/data/filebrowser:/database
    command:
      - "--database=/database/filebrowser.db"
      - "--root=/srv"
    user: "1000:1000"
    labels:
      - "com.centurylinklabs.watchtower.enable=true"

  uptime-kuma:
    image: louislam/uptime-kuma:latest
    container_name: uptime-kuma
    restart: unless-stopped
    ports:
      - "3003:3001"
    networks:
      - containers_network
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - /opt/streamlab/data/uptime-kuma:/app/data
    labels:
      - "com.centurylinklabs.watchtower.enable=true"
      
networks:
  containers_network:
    external: true
```

Start it:
```bash
cd /opt/streamlab/management
docker compose up -d
```


---

### Stack B — Monitoring (Prometheus + Grafana + node-exporter + cAdvisor)

#### Prometheus Setup
**File:** `/opt/streamlab/monitoring/prometheus.yml`

```bash
cd /opt/streamlab/monitoring
nano /opt/streamlab/monitoring/prometheus.yml
```

```yaml
global:
  scrape_interval: 60s

scrape_configs:
  - job_name: "prometheus"
    static_configs:
      - targets: ["prometheus:9090"]

  - job_name: "node-exporter"
    static_configs:
      - targets: ["node-exporter:9100"]

  - job_name: "cadvisor"
    static_configs:
      - targets: ["cadvisor:8080"]
```

- Required: `/opt/streamlab/data/prometheus`
- Prometheus UID: 65534

```bash
sudo mkdir -p /opt/streamlab/data/prometheus
sudo chown -R 65534:65534 /opt/streamlab/data/prometheus
sudo chmod -R 775 /opt/streamlab/data/prometheus
```

#### Grafana Setup
**File:** `/opt/streamlab/secrets/monitor.env`

```bash
cd /opt/streamlab/secrets/
nano /opt/streamlab/secrets/monitor.env
```

```plaintext
# Grafana admin bootstrap
GF_SECURITY_ADMIN_USER=admin
GF_SECURITY_ADMIN_PASSWORD=ENTER_PASSWORD
GF_USERS_ALLOW_SIGN_UP=false

# Public URL for correct links behind Cloudflare Access
GF_SERVER_ROOT_URL=https://grafana.YOUR_DOMAIN
```

- Required:`/opt/streamlab/data/grafana`
- Grafana UID: 472 

```bash
sudo mkdir -p /opt/streamlab/data/grafana
sudo chown -R 472:472 /opt/streamlab/data/grafana
sudo chmod -R 775 /opt/streamlab/data/grafana
```
**Prometheus datasource (provisioned from disk)**
Create a datasource provisioning file so Grafana always has Prometheus configured.

**File:** `/opt/streamlab/monitoring/grafana/provisioning/datasources/prometheus.yml`

```bash
sudo mkdir -p /opt/streamlab/monitoring/grafana/provisioning/datasources/
sudo nano /opt/streamlab/monitoring/grafana/provisioning/datasources/prometheus.yml
```

```yaml
apiVersion: 1
datasources:
  - name: Prometheus
    type: prometheus
    access: proxy
    url: http://prometheus:9090
    isDefault: true
```

**Dashboard template (provisioned from disk)**
Create a provisioning config and a dashboard JSON file so Grafana loads it on startup.


**File:** `/opt/streamlab/monitoring/grafana/provisioning/dashboards/default.yml`

```bash
sudo mkdir -p /opt/streamlab/monitoring/grafana/provisioning/dashboards
sudo nano /opt/streamlab/monitoring/grafana/provisioning/dashboards/default.yml
```

```yaml
apiVersion: 1
providers:
  - name: "default"
    orgId: 1
    folder: "Streamlab"
    type: file
    disableDeletion: false
    editable: true
    allowUiUpdates: true
    options:
      path: /etc/grafana/dashboards
```

**File:** `/opt/streamlab/monitoring/grafana/dashboards/streamlab-overview.json`

```bash
sudo mkdir -p /opt/streamlab/monitoring/grafana/dashboards
sudo nano /opt/streamlab/monitoring/grafana/dashboards/streamlab-overview.json
```

```json
{
  "uid": "streamlab-overview",
  "title": "streamlab Overview",
  "timezone": "browser",
  "schemaVersion": 38,
  "version": 1,
  "editable": true,
  "panels": [
    {
      "type": "stat",
      "title": "Targets Up",
      "datasource": "Prometheus",
      "targets": [
        {
          "expr": "count(up == 1)"
        }
      ],
      "gridPos": {
        "h": 6,
        "w": 12,
        "x": 0,
        "y": 0
      }
    }
  ]
}
```


#### Docker Setup
**File:** `/opt/streamlab/monitoring/docker-compose.yml`

```bash
cd /opt/streamlab/monitoring
nano /opt/streamlab/monitoring/docker-compose.yml
```


```yaml
services:
  prometheus:
    image: prom/prometheus:latest
    container_name: prometheus
    restart: unless-stopped
    # LAN access
    ports:
      - "9090:9090"
    # Public URL for correct links behind Cloudflare Access
    command:
      - "--config.file=/etc/prometheus/prometheus.yml"
      - "--web.external-url=https://prometheus.YOUR_DOMAIN"
    networks:
      - containers_network
    volumes:
      - /opt/streamlab/monitoring/prometheus.yml:/etc/prometheus/prometheus.yml:ro
      - /opt/streamlab/data/prometheus:/prometheus
    labels:
      - "com.centurylinklabs.watchtower.enable=true"

  grafana:
    image: grafana/grafana:latest
    container_name: grafana
    restart: unless-stopped
    # LAN access
    ports:
      - "3000:3000"
    networks:
      - containers_network
    volumes:
      - /opt/streamlab/data/grafana:/var/lib/grafana
      - /opt/streamlab/monitoring/grafana/provisioning:/etc/grafana/provisioning:ro
      - /opt/streamlab/monitoring/grafana/dashboards:/etc/grafana/dashboards:ro
    env_file:
      - /opt/streamlab/secrets/monitor.env
    labels:
      - "com.centurylinklabs.watchtower.enable=true"

  node-exporter:
    image: prom/node-exporter:latest
    container_name: node-exporter
    restart: unless-stopped
    networks:
      - containers_network
    pid: host
    volumes:
      - /:/host:ro,rslave
    command:
      - "--path.rootfs=/host"
    labels:
      - "com.centurylinklabs.watchtower.enable=true"

  cadvisor:
    image: gcr.io/cadvisor/cadvisor:latest
    container_name: cadvisor
    restart: unless-stopped
    networks:
      - containers_network
    volumes:
      - /:/rootfs:ro
      - /var/run:/var/run:ro
      - /sys:/sys:ro
      - /var/lib/docker/:/var/lib/docker:ro
    labels:
      - "com.centurylinklabs.watchtower.enable=true"

networks:
  containers_network:
    external: true
```

Start:
```bash
cd /opt/streamlab/monitoring
docker compose up -d
```

---

### Stack C — Media + Routing (gluetun + gost + AIOStreams + StremThru)


#### Mullvad WireGuard: what you need
Generate a Mullvad WireGuard config from Mullvad’s site/app. Then extract:
- **Private key**
- **Address(es)** (CIDR)
- Choose your **server city** or similar filter

#### Create media env files

**File:** `/opt/streamlab/secrets/gluetun.env`
```env
# Mullvad + WireGuard
VPN_SERVICE_PROVIDER=mullvad
VPN_TYPE=wireguard

# From Mullvad WireGuard config
WIREGUARD_PRIVATE_KEY=REPLACE_ME
WIREGUARD_ADDRESSES=REPLACE_ME_XX.XX.XX.XX/32

# Server selection (example)
SERVER_CITIES=London

# Allow local subnet access
LOCAL_NETWORK=192.168.1.0/24

TZ=Europe/London
```

**File:** `/opt/streamlab/secrets/aiostreams.env`

```env
# Required for AIOStreams to start
SECRET_KEY=REPLACE_WITH_64_CHAR_HEX_OR_PROJECT_REQUIRED_FORMAT
BASE_URL=https://aiostreams.YOUR_DOMAIN

# Optional: if you want AIOStreams to use a proxy for addon calls.
# NOTE: aiostreams runs with network_mode: "service:gluetun", so the proxy is localhost.
ADDON_PROXY=http://127.0.0.1:8888
```

**File:** `/opt/streamlab/secrets/stremthru.env`
```plaintext                                                                       
STREMTHRU_BASE_URL=http://192.168.1.20:8082
STREMTHRU_PORT=8082
STREMTHRU_PROXY_AUTH=ENTER_PASSWORD
STREMTHRU_AUTH_ADMIN=admin
STREMTHRU_DATA_DIR=/data
STREMTHRU_HTTP_PROXY=http://127.0.0.1:8888
STREMTHRU_STORE_CONTENT_PROXY=realdebrid:true
#Remove all stremthru addons to improve RAM usage
STREMTHRU_FEATURE=-dmm_hashlist,-imdb_title,-stremio_store,-stremio_torz,-stremio_list,-stremio_sidekick,-stremio_p2p,-anime,-vault
```

#### Media compose file
**File:** `/opt/streamlab/media/docker-compose.yml`

```bash
cd /opt/streamlab/media
nano /opt/streamlab/media/docker-compose.yml
```


```yaml
services:
  gluetun:
    image: qmcgaw/gluetun:latest
    container_name: gluetun
    restart: unless-stopped
    cap_add:
      - NET_ADMIN
    # LAN access 
    ports:
      - "3001:3000"
      - "8082:8082"
    env_file:
      - /opt/streamlab/secrets/gluetun.env
    networks:
      - containers_network
    healthcheck:
      test: ["CMD", "/gluetun-entrypoint", "healthcheck"]
      interval: 60s
      timeout: 10s
      retries: 3
      start_period: 30s
    labels:
      - "com.centurylinklabs.watchtower.enable=true"

  gost:
    image: ginuerzh/gost:latest
    container_name: gost
    restart: unless-stopped
    network_mode: "service:gluetun"
    depends_on:
      gluetun:
        condition: service_healthy
    command: ["-L", "http://:8888", "-L", "socks5://:1080"]
    labels:
      - "com.centurylinklabs.watchtower.enable=true"

  aiostreams:
    image: ghcr.io/viren070/aiostreams:latest
    container_name: aiostreams
    restart: unless-stopped
    network_mode: "service:gluetun"
    env_file:
      - /opt/streamlab/secrets/aiostreams.env
    volumes:
      - /opt/streamlab/data/aiostreams:/app/data
    depends_on:
      gluetun:
        condition: service_healthy
    labels:
      - "com.centurylinklabs.watchtower.enable=true"

  stremthru:
    image: muniftanjim/stremthru:latest
    container_name: stremthru
    restart: unless-stopped
    network_mode: "service:gluetun"
    env_file:
      - /opt/streamlab/secrets/stremthru.env
    volumes:
      - /opt/streamlab/data/stremthru:/data
    depends_on:
      gluetun:
        condition: service_healthy
    labels:
      - "com.centurylinklabs.watchtower.enable=true"

networks:
  containers_network:
    external: true
```

Start it:
```bash
cd /opt/streamlab/media
docker compose up -d
```

**Data folder permissions**
- Required: `/opt/streamlab/data/aiostreams` and `/opt/streamlab/data/stremthru`
- If a service can’t write, `chown` the folder to the container UID shown by `docker inspect`.

---

## 6) Operations

### 6.1 Start/stop everything
Each service group is independent:
```bash
cd /opt/streamlab/management && docker compose up -d
cd /opt/streamlab/monitoring && docker compose up -d
cd /opt/streamlab/media && docker compose up -d
```

Stop a service group:
```bash
docker compose down
```

Pause a single service (example: cloudflared):
```bash
cd /opt/streamlab/management
docker compose stop cloudflared
```

Resume it later:
```bash
cd /opt/streamlab/management
docker compose start cloudflared
```

You can also use Docker directly:
```bash
docker stop cloudflared
docker start cloudflared
```

### 6.2 Logs (first things to check)
```bash
docker logs -f cloudflared
docker logs -f gluetun
docker logs -f aiostreams
docker logs -f stremthru
docker logs -f watchtower
```

### 6.3 Confirm ports internally (quick sanity)
From the Docker VM:
```bash
curl -I http://localhost  # baseline check
curl -I http://127.0.0.1:3000  # not necessarily exposed; depends on mappings

# For LAN-only setup, hit the service by LAN IP/port.
# Later, validate via Cloudflare hostname once the tunnel mappings exist.
```

### 6.4 Updating containers
Watchtower will tell you updates exist, but it will not apply them.

Manual update pattern:
```bash
cd /opt/streamlab/<service>
docker compose pull
docker compose up -d
```

---

## 7) Git backup workflow 

### 7.0 GitHub repo + SSH key auth (server)
Do this once before pushing.

1. Create a **private** repo on GitHub (empty, no README).
2. Generate an SSH key on the server:
   ```bash
   ssh-keygen -t ed25519 -C "streamlab-server"
   ```
   Press Enter to accept the default path (`~/.ssh/id_ed25519`) and add a passphrase.
3. Add the public key to GitHub:
   ```bash
   cat ~/.ssh/id_ed25519.pub
   ```
   Copy it into GitHub → Settings → SSH and GPG keys → New SSH key.
4. Test SSH access:
   ```bash
   ssh -T git@github.com
   ```
   You should see a success message (GitHub may ask to trust the host key on first use).
5. On the server, set the remote using SSH:
   ```bash
   git remote add origin git@github.com:<USER>/<REPO>.git
   ```
6. Push normally (SSH handles auth):
   ```bash
   git push -u origin main
   ```


### 7.1 Add a `.gitignore`
**File:** `/opt/streamlab/.gitignore`

```bash 
sudo nano /opt/streamlab/.gitignore
```

```gitignore
data/
secrets/
**/.env
```

### 7.2 Store safe templates in git (I cba with this but maybe something for down the line)
Create examples in repo (tracked):
- `/opt/streamlab/secrets/`
- `/opt/streamlab/secrets/monitor.env.example`


### 7.3 Initialize repo
```bash
cd /opt/streamlab
git config --global <ENTER_USERNAME> <ENTER_PASSWORD>
git config --global <ENTER_EMAIL> <ENTER_PASSWORD>
git add -A
git commit -m "Initial ratlab services"
git push -u origin main
```

### 7.3 Create update easy function:
Below is a command that stores a script that can be run using `git_update_now` to quickly update the git backup. 
`git_update_now "added some script files, updated docker settings"`

```bash 
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
```
---

## 8) Secure access: Netbird + SSH locking + Cloudflare Tunnel + Access

### 8.1 Netbird LXC (`netbird`)
Inside the LXC:

```bash
curl -fsSL https://pkgs.netbird.io/install.sh | sh
sudo netbird up --setup-key YOUR_NETBIRD_SETUP_KEY
```

Check status / restart (if needed):
```bash
sudo systemctl status netbird
sudo systemctl restart netbird
sudo netbird status
```

### 8.2 Lock SSH behind Netbird only (Docker VM)

1) Ensure SSH is enabled:
```bash
sudo systemctl enable --now ssh
```

2) Configure UFW:
```bash
# Allow SSH from LAN until Netbird is verified everywhere
sudo ufw allow from 192.168.1.0/24 to any port 22 proto tcp

sudo ufw default deny incoming
sudo ufw default allow outgoing

# Allow SSH from Netbird CGNAT range (most setups use 100.64.0.0/10).
sudo ufw allow from 100.64.0.0/10 to any port 22 proto tcp

sudo ufw enable
sudo ufw status
```

Remove the LAN SSH rule: (Maybe, if you only want netbird access but that's a bit long if I'm at home)
```bash
sudo ufw delete allow from 192.168.1.0/24 to any port 22 proto tcp
sudo ufw status
```


---

## 9) Cloudflare hostnames + Google SSO (Cloudflare Access)

### 9.0 Cloudflare setup (domain + Zero Trust)
You have `YOUR_DOMAIN` registered, but not configured yet.

1. Add `YOUR_DOMAIN` to Cloudflare.
2. Update your registrar nameservers to Cloudflare’s. Cloudflare will give you two authoritative nameservers; set those at your domain registrar so DNS is hosted by Cloudflare (this can take a few minutes to propagate).
3. Enable **Cloudflare Zero Trust**.
4. Add **Google** as an Identity Provider (IdP) in Zero Trust. In the Zero Trust dashboard, go to **Settings → Authentication → Login methods**, choose Google, then create a Google OAuth client and paste the Client ID/Secret plus the Cloudflare-provided redirect URL so Google can hand back logins.
5. Configure Cloudflare Access so only your Google account(s) can log in.

### 9.05 Create a Cloudflare Tunnel
In Zero Trust:
- Networks → Tunnels → Create Tunnel
- Choose the “Docker” connector method
- Copy the **tunnel token** (you’ll paste this into `cloudflared`)

### 9.1 Create DNS hostnames (recommended set)
Create these hostnames (CNAMEs) in Cloudflare DNS (or configure via Tunnel directly depending on your Tunnel workflow):

- `portainer.YOUR_DOMAIN`
- `grafana.YOUR_DOMAIN`
- `prometheus.YOUR_DOMAIN` (optional exposure; you can keep it private)
- `filebrowser.YOUR_DOMAIN`
- `uptime.YOUR_DOMAIN`
- `aiostreams.YOUR_DOMAIN`
- `stremthru.YOUR_DOMAIN`

### 9.2 Cloudflare Tunnel “Public Hostnames” → internal origins
In the Tunnel settings, map each hostname to a service URL.

Because **AIOStreams/StremThru share gluetun’s network namespace**, you must point Cloudflare at **gluetun** for those ports:

- `portainer.YOUR_DOMAIN` → `http://portainer:9000`
- `grafana.YOUR_DOMAIN` → `http://grafana:3000`
- `prometheus.YOUR_DOMAIN` → `http://prometheus:9090`
- `filebrowser.YOUR_DOMAIN` → `http://filebrowser:80`
- `uptime.YOUR_DOMAIN` → `http://uptime-kuma:3001`
- `aiostreams.YOUR_DOMAIN` → `http://gluetun:3000`
- `stremthru.YOUR_DOMAIN` → `http://gluetun:8082`

### 9.3 Protect everything with Cloudflare Access (Google)
In Cloudflare Zero Trust:
1. Access → Applications → Add an application → **Self-hosted**
2. Add each hostname as an app (or group them if you prefer)
3. Add a policy:
   - Allow → include your Google email (or your Workspace)
4. (Optional) Block all other identities.

### 9.4 Allow certain aiostreams unauthenticated access
Actually can't remember how to do this, need to ask george to show me again

---

## 10) Stremio setup (Real Debrid + AIOStreams + StremThru)

### 10.1 Real Debrid: account + API token
1. Log in to Real Debrid.
2. Go to **My Account → API**.
3. Copy your **API Token** (keep it private).

### 10.2 AIOStreams configuration (env + service)
1. Generate a strong secret key (64 hex chars):
   ```bash
   openssl rand -hex 32
   ```
2. Edit `/opt/streamlab/secrets/aiostreams.env`:
   - `SECRET_KEY=...` (paste the generated hex)
   - `BASE_URL=` should be your external URL once Cloudflare is live (e.g., `https://aiostreams.YOUR_DOMAIN`).
     Use `http://192.168.1.20:3001` temporarily if you are still LAN-only.
   - `ADDON_PROXY=http://127.0.0.1:8888` to force addon traffic through the VPN.
3. Restart the media stack:
   ```bash
   cd /opt/streamlab/media
   docker compose up -d
   ```

### 10.3 AIOStreams UI: link Real Debrid
1. Open the AIOStreams UI:
   - LAN: `http://192.168.1.20:3001`
   - After Cloudflare: `https://aiostreams.YOUR_DOMAIN`
2. In the Debrid/Providers settings, add your Real Debrid API token.
3. Save and confirm it shows as connected.
4. Configure proxy setup: 
  Proxy Service: StremThru
  URL: http://gluetun:8082
  Public URL: http://192.168.1.20:8082
  Credentials: username:password (From STREMTHRU_PROXY_AUTH in stremthru.env)
  Proxied Services: Real-Debrid, None
  Proxied Addions: Torrentio, Comet, MediaFusion (or whatever addons you add)

### 10.4 StremThru configuration (if you decide to use stremthru additional features, but you've disabled this atm) 
1. Open the StremThru UI:
   - LAN: `http://192.168.1.20:8082`
   - After Cloudflare: `https://stremthru.YOUR_DOMAIN`
2. Log in with the admin credentials you set in `/opt/streamlab/secrets/stremthru.env`.
3. Add your Real Debrid API token (provider: Real Debrid).
4. Save and verify it shows as connected.

### 10.5 Add addons to the Stremio client
1. Open Stremio on your device.
2. Go to **Add-ons → Community → Add by URL**.
3. From each service UI, copy the **Install/Addon URL** and paste it into Stremio:
   - **AIOStreams** (usually ends with `/manifest.json`)
   - **StremThru** (usually ends with `/manifest.json`) (if using additional features)
4. Confirm the addons appear in Stremio and can search/play.
5. If you change `BASE_URL`, remove and re-add the addon so Stremio picks up the new manifest URL.

---
