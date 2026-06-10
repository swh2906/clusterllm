#!/usr/bin/env bash
# =============================================================================
# 02_network_worker.sh — Netzwerk-Konfiguration fuer Worker-Nodes (node-01+)
# Single-Interface Ethernet, Gateway = node-00 (NAT)
# Ausfuehren auf node-01, node-02, ...: sudo bash 02_network_worker.sh
# =============================================================================
set -euo pipefail
RED='\033[0;31m'; GREEN='\033[0;32m'; CYAN='\033[0;36m'
YELLOW='\033[1;33m'; BOLD='\033[1m'; RESET='\033[0m'
info()    { echo -e "${CYAN}[INFO]${RESET}  $*"; }
success() { echo -e "${GREEN}[OK]${RESET}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${RESET}  $*"; }
error()   { echo -e "${RED}[ERROR]${RESET} $*"; exit 1; }
banner()  { echo -e "\n${BOLD}${CYAN}=== $* ===${RESET}\n"; }
[[ $EUID -ne 0 ]] && error "Run with sudo: sudo bash $0"

banner "Worker-Node Netzwerk-Konfiguration"

banner "Step 1 · Ethernet-Interface erkennen"
ETH_IFACE=$(ip -o link show | awk -F': ' '$2 !~ /^lo|^wl/{print $2; exit}')
info "Erkanntes Interface: ${ETH_IFACE:-NICHT GEFUNDEN}"
echo -n "  Interface bestaetigen oder aendern [${ETH_IFACE}]: "
read -r INPUT; ETH_IFACE="${INPUT:-$ETH_IFACE}"
[[ -z "$ETH_IFACE" ]] && error "Kein Interface angegeben"

banner "Step 2 · IP-Adresse konfigurieren"
echo -n "  Hostname fuer diesen Node (z.B. node-01): "
read -r NODE_HOSTNAME
echo -n "  Statische IP (z.B. 192.168.10.11): "
read -r NODE_IP
echo -n "  Subnetz-Praefix [24]: "
read -r PREFIX; PREFIX="${PREFIX:-24}"
[[ -z "$NODE_IP" ]] && error "Keine IP angegeben"

banner "Step 3 · Netplan-Konfiguration schreiben"
cp /etc/netplan/*.yaml "/etc/netplan/backup-$(date +%Y%m%d%H%M%S).yaml" 2>/dev/null || true

cat > /etc/netplan/01-cluster.yaml << NETPLAN
network:
  version: 2
  renderer: networkd
  ethernets:
    ${ETH_IFACE}:
      dhcp4: false
      addresses:
        - ${NODE_IP}/${PREFIX}
      routes:
        - to: default
          via: 192.168.10.10
      nameservers:
        addresses: [8.8.8.8, 1.1.1.1]
NETPLAN

chmod 600 /etc/netplan/01-cluster.yaml
netplan apply
success "Netplan angewendet: ${NODE_IP}/${PREFIX} via 192.168.10.10"

banner "Step 4 · UFW Firewall"
ufw allow OpenSSH
ufw allow from 192.168.10.0/24 to any comment "Cluster-Subnet"
ufw --force enable
success "UFW konfiguriert"

banner "Step 5 · /etc/hosts — Cluster-Nodes"
if ! grep -q "node-00" /etc/hosts; then
    cat >> /etc/hosts << 'EOF'

# LLM Cluster Nodes
192.168.10.10   node-00
192.168.10.11   node-01
192.168.10.12   node-02
192.168.10.13   node-03
192.168.10.14   node-04
192.168.10.15   node-05
192.168.10.16   node-06
192.168.10.17   node-07
192.168.10.18   node-08
192.168.10.19   node-09
EOF
    success "/etc/hosts aktualisiert"
else
    warn "Cluster-Eintraege bereits vorhanden"
fi

banner "Step 6 · Verifizierung"
ip addr show "${ETH_IFACE}" | grep inet
ping -c 2 192.168.10.10 && success "node-00 erreichbar" || warn "node-00 nicht erreichbar"
ping -c 2 8.8.8.8 && success "Internet via NAT erreichbar" || warn "Internet nicht erreichbar — node-00 NAT pruefen"

banner "=== Worker Netzwerk abgeschlossen ==="
echo -e "${YELLOW}Naechster Schritt:${RESET}"
echo "  sudo bash 03_dependencies.sh"
