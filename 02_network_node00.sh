#!/usr/bin/env bash
# =============================================================================
# 02_network_node00.sh — Netzwerk-Konfiguration fuer node-00
# Dual-Interface: WiFi (Internet) + Ethernet (Cluster) + NAT-Gateway
# Nur auf node-00 ausfuehren: sudo bash 02_network_node00.sh
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

banner "node-00 Netzwerk-Konfiguration (Dual-Interface + NAT)"

banner "Step 1 · Netzwerk-Interfaces erkennen"
ETH_IFACE=$(ip -o link show | awk -F': ' '$2 !~ /^lo|^wl/{print $2; exit}')
WIFI_IFACE=$(ip -o link show | awk -F': ' '$2 ~ /^wl/{print $2; exit}')
info "Erkanntes Ethernet-Interface: ${ETH_IFACE:-NICHT GEFUNDEN}"
info "Erkanntes WiFi-Interface:     ${WIFI_IFACE:-NICHT GEFUNDEN}"
echo
echo -n "  Ethernet-Interface bestaetigen oder aendern [${ETH_IFACE}]: "
read -r INPUT; ETH_IFACE="${INPUT:-$ETH_IFACE}"
echo -n "  WiFi-Interface bestaetigen oder aendern [${WIFI_IFACE}]: "
read -r INPUT; WIFI_IFACE="${INPUT:-$WIFI_IFACE}"
[[ -z "$ETH_IFACE" ]] && error "Kein Ethernet-Interface angegeben"
[[ -z "$WIFI_IFACE" ]] && error "Kein WiFi-Interface angegeben"
success "Ethernet: ${ETH_IFACE}  |  WiFi: ${WIFI_IFACE}"

banner "Step 2 · Cluster-IP konfigurieren"
echo -n "  Cluster-IP fuer node-00 [192.168.10.10]: "
read -r NODE_IP; NODE_IP="${NODE_IP:-192.168.10.10}"
echo -n "  Subnetz-Praefix [24]: "
read -r PREFIX; PREFIX="${PREFIX:-24}"
success "Cluster-IP: ${NODE_IP}/${PREFIX}"

banner "Step 3 · Netplan-Konfiguration schreiben"
mkdir -p /etc/netplan
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
      nameservers:
        addresses: [8.8.8.8, 1.1.1.1]
  wifis:
    ${WIFI_IFACE}:
      dhcp4: true
      access-points:
        "DEIN_WLAN_SSID":
          password: "DEIN_WLAN_PASSWORT"
      nameservers:
        addresses: [8.8.8.8, 1.1.1.1]
NETPLAN

chmod 600 /etc/netplan/01-cluster.yaml
echo
echo -e "${YELLOW}WICHTIG: WiFi-Zugangsdaten eintragen!${RESET}"
echo "  sudo nano /etc/netplan/01-cluster.yaml"
echo "  'DEIN_WLAN_SSID' und 'DEIN_WLAN_PASSWORT' ersetzen"
echo
echo -n "  WiFi-Konfiguration jetzt bearbeiten? (Y/n): "
read -r EDIT_WIFI
if [[ ! "$EDIT_WIFI" =~ ^[Nn]$ ]]; then
    nano /etc/netplan/01-cluster.yaml
fi
netplan apply
success "Netplan angewendet"

banner "Step 4 · IP-Forwarding aktivieren"
cat > /etc/sysctl.d/99-forwarding.conf << 'EOF'
net.ipv4.ip_forward = 1
EOF
sysctl -p /etc/sysctl.d/99-forwarding.conf
success "IP-Forwarding aktiv"

banner "Step 5 · NAT (iptables MASQUERADE) konfigurieren"
iptables -t nat -A POSTROUTING -s 192.168.10.0/24 -o "${WIFI_IFACE}" -j MASQUERADE
iptables -A FORWARD -i "${ETH_IFACE}" -o "${WIFI_IFACE}" -j ACCEPT
iptables -A FORWARD -i "${WIFI_IFACE}" -o "${ETH_IFACE}" -m state --state RELATED,ESTABLISHED -j ACCEPT
mkdir -p /etc/iptables
iptables-save > /etc/iptables/rules.v4
systemctl enable netfilter-persistent 2>/dev/null || true
success "NAT konfiguriert und gespeichert"

banner "Step 6 · UFW Firewall"
sed -i 's/DEFAULT_FORWARD_POLICY="DROP"/DEFAULT_FORWARD_POLICY="ACCEPT"/' /etc/default/ufw
ufw allow OpenSSH
ufw allow from 192.168.10.0/24 to any comment "Cluster-Subnet"
ufw allow 8000/tcp comment "vLLM API"
ufw allow 8265/tcp comment "Ray Dashboard"
ufw allow 9090/tcp comment "Cockpit"
ufw allow 3000/tcp comment "Grafana"
ufw allow 443/tcp comment "HTTPS Caddy"
ufw allow 80/tcp comment "HTTP Caddy"
ufw --force enable
success "UFW konfiguriert"

banner "Step 7 · /etc/hosts — Cluster-Nodes"
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
    warn "Cluster-Eintraege bereits in /etc/hosts"
fi

banner "Step 8 · SSH-Key generieren"
REAL_USER="${SUDO_USER:-ubuntu}"
REAL_HOME=$(getent passwd "$REAL_USER" | cut -d: -f6)
SSH_KEY="${REAL_HOME}/.ssh/id_ed25519"
if [[ -f "$SSH_KEY" ]]; then
    warn "SSH-Key existiert bereits: ${SSH_KEY}"
else
    sudo -u "$REAL_USER" ssh-keygen -t ed25519 -f "$SSH_KEY" -N ''
    success "SSH-Key generiert"
fi
chmod 700 "${REAL_HOME}/.ssh"
chmod 600 "$SSH_KEY" 2>/dev/null || true
chmod 644 "${SSH_KEY}.pub" 2>/dev/null || true
echo
echo -e "${BOLD}Dein SSH Public Key (auf alle Worker-Nodes kopieren):${RESET}"
echo "────────────────────────────────────────────────────"
cat "${SSH_KEY}.pub"
echo "────────────────────────────────────────────────────"
echo
info "Key auf Worker kopieren: ssh-copy-id ${REAL_USER}@node-01"

banner "Step 9 · Verifizierung"
info "Ethernet-Interface:"
ip addr show "${ETH_IFACE}" | grep inet || warn "Keine IP auf ${ETH_IFACE}"
info "WiFi-Interface:"
ip addr show "${WIFI_IFACE}" | grep inet || warn "Keine IP auf ${WIFI_IFACE} — WiFi-Zugangsdaten pruefen"
info "NAT-Regeln:"
iptables -t nat -L POSTROUTING -n -v | grep MASQUERADE || warn "Keine MASQUERADE-Regel gefunden"
ping -c 2 8.8.8.8 && success "Internet erreichbar" || warn "Internet nicht erreichbar — WiFi-Konfiguration pruefen"

banner "=== node-00 Netzwerk abgeschlossen ==="
echo -e "${YELLOW}Naechster Schritt:${RESET}"
echo "  sudo bash 03_dependencies.sh"
