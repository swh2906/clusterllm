#!/usr/bin/env bash
# =============================================================================
# 06_monitoring.sh -- Monitoring Stack + Web-Terminal
# LLM Cluster - Ubuntu 26.04 LTS - nur auf node-00 ausfuehren
#
# Installiert:
#   - Prometheus + Node Exporter (Metriken aller Nodes)
#   - Grafana (Web-Dashboard, Port 3000)
#   - NVIDIA DCGM Exporter (GPU-Metriken, Port 9400)
#   - ttyd (Web-Terminal, Port 7681)
#   - Caddy (HTTPS Reverse Proxy - alle UIs unter einer Adresse)
#
# Kein Cockpit. Kein Tailscale.
# Alle UIs erreichbar unter https://192.168.10.10/
#
# Usage: sudo bash 06_monitoring.sh
# =============================================================================
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; CYAN='\033[0;36m'
YELLOW='\033[1;33m'; BOLD='\033[1m'; RESET='\033[0m'

info()    { echo -e "${CYAN}[INFO]${RESET}  $*"; }
success() { echo -e "${GREEN}[OK]${RESET}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${RESET}  $*"; }
error()   { echo -e "${RED}[ERROR]${RESET} $*" >&2; exit 1; }
banner()  { echo -e "\n${BOLD}${CYAN}============================================${RESET}";
            echo -e "${BOLD}${CYAN}  $*${RESET}";
            echo -e "${BOLD}${CYAN}============================================${RESET}\n"; }

[[ $EUID -ne 0 ]] && error "Run with sudo: sudo bash $0"

REAL_USER="${SUDO_USER:-ubuntu}"

# =============================================================================
banner "Step 1 - Prometheus + Node Exporter"
# =============================================================================
info "Installiere Prometheus und Node Exporter..."
apt install -y prometheus prometheus-node-exporter

info "Schreibe Prometheus-Konfiguration (alle 10 Nodes vorkonfiguriert)..."
cat > /etc/prometheus/prometheus.yml << 'PROMEOF'
global:
  scrape_interval:     15s
  evaluation_interval: 15s

scrape_configs:
  - job_name: "prometheus"
    static_configs:
      - targets: ["localhost:9090"]

  - job_name: "node_exporter"
    static_configs:
      - targets:
          - "192.168.10.10:9100"
          - "192.168.10.11:9100"
          - "192.168.10.12:9100"
          - "192.168.10.13:9100"
          - "192.168.10.14:9100"
          - "192.168.10.15:9100"
          - "192.168.10.16:9100"
          - "192.168.10.17:9100"
          - "192.168.10.18:9100"
          - "192.168.10.19:9100"

  - job_name: "dcgm_exporter"
    static_configs:
      - targets:
          - "192.168.10.10:9400"
          - "192.168.10.11:9400"
          - "192.168.10.12:9400"
          - "192.168.10.13:9400"
          - "192.168.10.14:9400"
          - "192.168.10.15:9400"
          - "192.168.10.16:9400"
          - "192.168.10.17:9400"
          - "192.168.10.18:9400"
          - "192.168.10.19:9400"

  - job_name: "vllm"
    static_configs:
      - targets: ["192.168.10.10:8000"]
    metrics_path: "/metrics"
PROMEOF

systemctl enable --now prometheus prometheus-node-exporter
success "Prometheus laeuft auf :9090, Node Exporter auf :9100"

echo ""
info "Node Exporter auf Worker-Nodes installieren (von node-00 aus ausfuehren):"
echo "  for node in node-01 node-02; do"
echo "    ssh ubuntu@\$node 'sudo apt install -y prometheus-node-exporter && sudo systemctl enable --now prometheus-node-exporter'"
echo "  done"

# =============================================================================
banner "Step 2 - Grafana"
# =============================================================================
info "Fuege Grafana APT-Repository hinzu..."
mkdir -p /etc/apt/keyrings
curl -fsSL https://apt.grafana.com/gpg.key \
    | gpg --dearmor -o /etc/apt/keyrings/grafana.gpg

cat > /etc/apt/sources.list.d/grafana.list << 'EOF'
deb [signed-by=/etc/apt/keyrings/grafana.gpg] https://apt.grafana.com stable main
EOF

apt update
apt install -y grafana
systemctl enable --now grafana-server
success "Grafana laeuft auf :3000 (Standard-Login: admin / admin)"

# =============================================================================
banner "Step 3 - NVIDIA DCGM Exporter (GPU-Metriken)"
# =============================================================================
info "Installiere DCGM..."
apt install -y datacenter-gpu-manager

cat > /etc/systemd/system/dcgm-exporter.service << 'EOF'
[Unit]
Description=NVIDIA DCGM Exporter
After=network.target

[Service]
Type=simple
ExecStart=/usr/bin/dcgm-exporter --address :9400
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now dcgm-exporter
systemctl restart prometheus
success "DCGM Exporter laeuft auf :9400"

# =============================================================================
banner "Step 4 - ttyd Web-Terminal"
# =============================================================================
info "Installiere ttyd (Browser-basiertes Terminal fuer node-00)..."

TTYD_VERSION="1.7.7"
TTYD_URL="https://github.com/tsl0922/ttyd/releases/download/${TTYD_VERSION}/ttyd.x86_64"

if [[ -f /usr/local/bin/ttyd ]]; then
    warn "ttyd bereits installiert -- ueberspringe Download"
else
    wget -q --show-progress -O /usr/local/bin/ttyd "${TTYD_URL}"
    chmod +x /usr/local/bin/ttyd
    success "ttyd Binary installiert: /usr/local/bin/ttyd"
fi

# ttyd als systemd Service (laeuft als normaler User, nicht root)
cat > /etc/systemd/system/ttyd.service << TTYDEOF
[Unit]
Description=ttyd Web Terminal
After=network.target

[Service]
Type=simple
User=${REAL_USER}
ExecStart=/usr/local/bin/ttyd \\
  --port 7681 \\
  --interface 127.0.0.1 \\
  --credential admin:cluster \\
  --writable \\
  bash
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
TTYDEOF

systemctl daemon-reload
systemctl enable --now ttyd
success "ttyd Web-Terminal laeuft auf localhost:7681 (nur intern, via Caddy erreichbar)"
warn "Standard-Passwort: admin:cluster -- BITTE AENDERN:"
warn "  sudo nano /etc/systemd/system/ttyd.service"
warn "  --credential admin:NEUES_PASSWORT"
warn "  sudo systemctl daemon-reload && sudo systemctl restart ttyd"

# =============================================================================
banner "Step 5 - Caddy HTTPS Reverse Proxy"
# =============================================================================
info "Fuege Caddy APT-Repository hinzu..."
curl -fsSL https://dl.cloudsmith.io/public/caddy/stable/gpg.key \
    | gpg --dearmor -o /etc/apt/keyrings/caddy-stable.gpg

cat > /etc/apt/sources.list.d/caddy-stable.list << 'EOF'
deb [signed-by=/etc/apt/keyrings/caddy-stable.gpg] https://dl.cloudsmith.io/public/caddy/stable/deb/debian any-version main
EOF

apt update
apt install -y caddy

info "Schreibe /etc/caddy/Caddyfile..."
cat > /etc/caddy/Caddyfile << 'EOF'
:443 {
    tls internal

    # Ray Dashboard
    handle /ray/* {
        uri strip_prefix /ray
        reverse_proxy localhost:8265
    }

    # Grafana
    handle /grafana/* {
        uri strip_prefix /grafana
        reverse_proxy localhost:3000
    }

    # vLLM API (OpenAI-kompatibel)
    handle /api/* {
        uri strip_prefix /api
        reverse_proxy localhost:8000
    }

    # llama.cpp Fallback
    handle /llama/* {
        uri strip_prefix /llama
        reverse_proxy localhost:8080
    }

    # Web-Terminal (ttyd) -- passwortgeschuetzt
    handle /terminal/* {
        uri strip_prefix /terminal
        reverse_proxy localhost:7681
    }

    # Prometheus (intern)
    handle /prometheus/* {
        uri strip_prefix /prometheus
        reverse_proxy localhost:9090
    }

    # Status-Seite
    handle {
        respond "LLM Cluster node-00 -- alle Dienste aktiv" 200
    }
}
EOF

systemctl enable --now caddy
success "Caddy HTTPS Reverse Proxy laeuft auf :443"

# =============================================================================
banner "=== Monitoring Stack vollstaendig ==="
# =============================================================================
echo -e "${GREEN}${BOLD}"
echo "  Installierte Dienste:"
echo "  OK  Prometheus      :9090  (intern)"
echo "  OK  Node Exporter   :9100  (alle Nodes)"
echo "  OK  Grafana         :3000  (intern)"
echo "  OK  DCGM Exporter   :9400  (GPU-Metriken)"
echo "  OK  ttyd Terminal   :7681  (intern, via Caddy)"
echo "  OK  Caddy HTTPS     :443   (alle UIs gebuendelt)"
echo -e "${RESET}"
echo -e "${CYAN}${BOLD}Alle UIs erreichbar unter https://192.168.10.10/:${RESET}"
echo -e "  /ray/        -> Ray Dashboard"
echo -e "  /grafana/    -> Grafana  (admin/admin -- bitte aendern!)"
echo -e "  /api/        -> vLLM API (OpenAI-kompatibel)"
echo -e "  /llama/      -> llama.cpp Fallback"
echo -e "  /terminal/   -> Web-Terminal  (admin:cluster -- bitte aendern!)"
echo -e "  /prometheus/ -> Prometheus"
echo ""
echo -e "${YELLOW}Grafana Setup:${RESET}"
echo -e "  1. https://192.168.10.10/grafana/ oeffnen -> admin/admin"
echo -e "  2. Prometheus Data Source: http://localhost:9090"
echo -e "  3. NVIDIA DCGM Dashboard importieren: ID 12239"
echo -e "  4. Node Exporter Dashboard importieren: ID 1860"
echo ""
echo -e "${CYAN}Naechster Schritt:${RESET} bash validate_cluster.sh"
