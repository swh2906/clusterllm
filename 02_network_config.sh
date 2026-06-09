#!/usr/bin/env bash
# =============================================================================
# Phase 2 -- Network Configuration
# Run locally on each node after 01_os_config.sh.
# Usage: sudo bash 02_network_config.sh
# =============================================================================
set -euo pipefail

# ---------------------------------------------------------------------------
# Colour helpers
# ---------------------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
RESET='\033[0m'

# ---------------------------------------------------------------------------
# Logging functions
# ---------------------------------------------------------------------------
info()    { echo -e "${CYAN}[INFO]${RESET}  $*"; }
success() { echo -e "${GREEN}[OK]${RESET}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${RESET}  $*"; }
error()   { echo -e "${RED}[ERROR]${RESET} $*" >&2; exit 1; }
banner()  {
  echo ""
  echo -e "${BOLD}${CYAN}================================================================${RESET}"
  echo -e "${BOLD}${CYAN}  $*${RESET}"
  echo -e "${BOLD}${CYAN}================================================================${RESET}"
  echo ""
}

# ---------------------------------------------------------------------------
# Root check
# ---------------------------------------------------------------------------
[[ $EUID -ne 0 ]] && error "Run with sudo: sudo bash $0"

# ===========================================================================
banner "Step 1 . Detect network interface"
# ===========================================================================
IFACE=$(ip -o link show | awk -F': ' '$2 !~ /^lo/ {print $2; exit}')
info "Detected interface: ${BOLD}${IFACE}${RESET}"
echo -n "Press Enter to use '${IFACE}' or type a different interface name: "
read -r IFACE_INPUT
IFACE="${IFACE_INPUT:-$IFACE}"
info "Using interface: $IFACE"

# ===========================================================================
banner "Step 2 . Configure static IP"
# ===========================================================================
echo -n "Enter static IP for this node (e.g. 192.168.10.10): "
read -r NODE_IP
[[ -z "$NODE_IP" ]] && error "Static IP cannot be empty."

echo -n "Enter subnet prefix (press Enter for /24): "
read -r PREFIX
PREFIX="${PREFIX:-24}"

echo -n "Enter gateway IP (e.g. 192.168.10.1): "
read -r GATEWAY
[[ -z "$GATEWAY" ]] && error "Gateway cannot be empty."

echo -n "Enter DNS server (press Enter for 8.8.8.8): "
read -r DNS
DNS="${DNS:-8.8.8.8}"

# Backup existing netplan configs
NETPLAN_DIR="/etc/netplan"
BACKUP_DIR="${NETPLAN_DIR}/backup-$(date +%Y%m%d-%H%M%S)"
if ls "${NETPLAN_DIR}"/*.yaml &>/dev/null 2>&1; then
  info "Backing up existing netplan configs to ${BACKUP_DIR}..."
  mkdir -p "$BACKUP_DIR"
  cp "${NETPLAN_DIR}"/*.yaml "$BACKUP_DIR/" 2>/dev/null || true
fi

info "Writing /etc/netplan/01-cluster.yaml..."
cat > /etc/netplan/01-cluster.yaml <<NETPLAN
network:
  version: 2
  renderer: networkd
  ethernets:
    ${IFACE}:
      dhcp4: false
      addresses:
        - ${NODE_IP}/${PREFIX}
      routes:
        - to: default
          via: ${GATEWAY}
      nameservers:
        addresses:
          - ${DNS}
          - 1.1.1.1
NETPLAN

chmod 600 /etc/netplan/01-cluster.yaml

info "Applying netplan configuration..."
netplan apply

success "Static IP ${NODE_IP}/${PREFIX} applied on ${IFACE}."

# ===========================================================================
banner "Step 3 . Update /etc/hosts"
# ===========================================================================
info "Current /etc/hosts:"
cat /etc/hosts
echo ""

CLUSTER_HOSTS_BLOCK="# --- LLM Cluster Nodes ---
192.168.10.10  node-00
192.168.10.11  node-01
192.168.10.12  node-02
192.168.10.13  node-03
192.168.10.14  node-04
192.168.10.15  node-05
192.168.10.16  node-06
192.168.10.17  node-07
192.168.10.18  node-08
192.168.10.19  node-09
# --- End LLM Cluster Nodes ---"

info "Cluster hosts block to add:"
echo "$CLUSTER_HOSTS_BLOCK"
echo ""

if grep -q "node-00" /etc/hosts; then
  warn "Cluster entries already present in /etc/hosts -- skipping."
else
  echo "" >> /etc/hosts
  echo "$CLUSTER_HOSTS_BLOCK" >> /etc/hosts
  success "Cluster host entries appended to /etc/hosts."
fi

# ===========================================================================
banner "Step 4 . Configure UFW firewall"
# ===========================================================================
info "Configuring UFW rules..."

ufw allow OpenSSH
ufw allow from 192.168.10.0/24 to any port 22    comment "SSH cluster"
ufw allow from 192.168.10.0/24 to any port 6443  comment "k3s API"
ufw allow from 192.168.10.0/24 to any port 10250 comment "kubelet"
ufw allow from 192.168.10.0/24 to any port 8472  comment "Flannel VXLAN"
ufw allow from 192.168.10.0/24 to any port 2379:2380/tcp comment "etcd"
ufw allow from 192.168.10.0/24 to any port 8080  comment "llama-server"
ufw allow from 192.168.10.0/24 to any port 9090  comment "Prometheus"
ufw allow from 192.168.10.0/24 to any port 3000  comment "Grafana"

ufw --force enable
echo ""
ufw status numbered
success "UFW configured and enabled."

# ===========================================================================
banner "Step 5 . SSH key setup"
# ===========================================================================
REAL_USER="${SUDO_USER:-ubuntu}"
REAL_HOME=$(getent passwd "$REAL_USER" | cut -d: -f6)
SSH_DIR="$REAL_HOME/.ssh"
SSH_KEY="$SSH_DIR/id_ed25519"

mkdir -p "$SSH_DIR"

if [[ -f "$SSH_KEY" ]]; then
  warn "SSH key already exists at $SSH_KEY -- skipping generation."
else
  info "Generating ed25519 SSH key for user $REAL_USER..."
  sudo -u "$REAL_USER" ssh-keygen -t ed25519 -f "$SSH_KEY" -N ''
  success "SSH key generated."
fi

# Fix permissions
chmod 700 "$SSH_DIR"
chmod 600 "$SSH_KEY"
chmod 644 "${SSH_KEY}.pub"
chown -R "$REAL_USER:$REAL_USER" "$SSH_DIR"

echo ""
echo -e "${BOLD}${CYAN}================================================================${RESET}"
echo -e "${BOLD}  Public key for ${REAL_USER}:${RESET}"
echo -e "${BOLD}${CYAN}================================================================${RESET}"
cat "${SSH_KEY}.pub"
echo -e "${BOLD}${CYAN}================================================================${RESET}"
echo ""
info "Copy this key to other nodes with:"
info "  ssh-copy-id ${REAL_USER}@<other-node-ip>"

# ===========================================================================
banner "Step 6 . Verify network"
# ===========================================================================
info "Pinging gateway ${GATEWAY}..."
ping -c 3 "$GATEWAY" || warn "Cannot reach gateway $GATEWAY"

info "Pinging internet (8.8.8.8)..."
ping -c 3 8.8.8.8 || warn "Cannot reach internet (8.8.8.8)"

info "Interface ${IFACE} addresses:"
ip addr show "$IFACE" | grep inet

# ===========================================================================
banner "=== Phase 2 Complete ==="
# ===========================================================================
echo -e "${GREEN}${BOLD}"
echo "  IP        : ${NODE_IP}/${PREFIX}"
echo "  Gateway   : ${GATEWAY}"
echo "  Hostname  : $(hostname)"
echo -e "${RESET}"
info "Next step --> run: ${BOLD}sudo bash 03_dependencies.sh${RESET}"
