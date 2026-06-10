#!/usr/bin/env bash
# =============================================================================
# 01_os_config.sh — OS-Konfiguration (Ubuntu 26.04 LTS)
# LLM Cluster · Lenovo P1 Gen3
# Ausfuehren auf JEDEM Node: sudo bash 01_os_config.sh
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

banner "LLM Cluster — OS-Konfiguration (Ubuntu 26.04 LTS)"

banner "Step 1 · System update & upgrade"
apt update
DEBIAN_FRONTEND=noninteractive apt upgrade -y
apt autoremove -y
success "System aktualisiert"

banner "Step 2 · Hostname setzen"
CURRENT=$(hostname)
info "Aktueller Hostname: ${CURRENT}"
echo -n "  Hostname fuer diesen Node (z.B. node-00): "
read -r HOSTNAME_NEW
if [[ -z "$HOSTNAME_NEW" ]]; then
    warn "Kein Hostname eingegeben — behalte: ${CURRENT}"
    HOSTNAME_NEW="$CURRENT"
else
    hostnamectl set-hostname "$HOSTNAME_NEW"
    echo "$HOSTNAME_NEW" > /etc/hostname
    if grep -q "127.0.1.1" /etc/hosts; then
        sed -i "s/^127\.0\.1\.1.*/127.0.1.1\t${HOSTNAME_NEW}/" /etc/hosts
    else
        echo "127.0.1.1	${HOSTNAME_NEW}" >> /etc/hosts
    fi
    success "Hostname gesetzt: ${HOSTNAME_NEW}"
fi

banner "Step 3 · Timezone setzen"
timedatectl set-timezone Europe/Berlin
success "Timezone: Europe/Berlin"

banner "Step 4 · Base Packages installieren (Ubuntu 26.04)"
apt install -y \
    curl wget git vim htop nvtop \
    build-essential cmake unzip rsync \
    net-tools dnsutils lsof jq tmux \
    ca-certificates gnupg lsb-release \
    apt-transport-https openssh-server \
    python3 python3-pip python3-venv python3-dev \
    ufw iptables iptables-persistent
success "Base Packages installiert"

banner "Step 5 · Swap deaktivieren (erforderlich fuer Ray)"
swapoff -a
sed -i '/\sswap\s/s/^/#/' /etc/fstab
success "Swap deaktiviert"
free -h | grep Swap

banner "Step 6 · Kernel-Module fuer Netzwerk laden"
cat > /etc/modules-load.d/cluster.conf << 'EOF'
overlay
br_netfilter
EOF
modprobe overlay
modprobe br_netfilter
cat > /etc/sysctl.d/99-cluster.conf << 'EOF'
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
net.core.rmem_max                   = 134217728
net.core.wmem_max                   = 134217728
EOF
sysctl --system
success "Kernel-Module geladen"

banner "Step 7 · Python Virtual Environment erstellen"
mkdir -p /opt/cluster
REAL_USER="${SUDO_USER:-ubuntu}"
chown -R "${REAL_USER}:${REAL_USER}" /opt/cluster
sudo -u "$REAL_USER" python3 -m venv /opt/cluster/venv
cat > /etc/profile.d/cluster.sh << 'EOF'
source /opt/cluster/venv/bin/activate 2>/dev/null || true
EOF
chmod 644 /etc/profile.d/cluster.sh
success "Python venv: /opt/cluster/venv"

banner "=== Phase 1 abgeschlossen ==="
echo -e "  Hostname:  ${BOLD}$(hostname)${RESET}"
echo -e "  IP:        ${BOLD}$(hostname -I | awk '{print $1}')${RESET}"
echo -e "  Python:    ${BOLD}$(python3 --version)${RESET}"
echo
echo -e "${YELLOW}Naechster Schritt:${RESET}"
echo "  node-00: sudo bash 02_network_node00.sh"
echo "  node-01+: sudo bash 02_network_worker.sh"
