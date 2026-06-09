#!/usr/bin/env bash
# =============================================================================
# Phase 1 -- OS Configuration
# Run locally on each node after Ubuntu Server 22.04 install.
# Usage: sudo bash 01_os_config.sh
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
banner "Step 1 . System update & upgrade"
# ===========================================================================
info "Running apt update..."
apt update

info "Running apt upgrade (non-interactive)..."
DEBIAN_FRONTEND=noninteractive apt upgrade -y

info "Removing unused packages..."
apt autoremove -y

success "System packages up to date."

# ===========================================================================
banner "Step 2 . Set hostname"
# ===========================================================================
CURRENT_HOSTNAME=$(hostname)
info "Current hostname: ${BOLD}${CURRENT_HOSTNAME}${RESET}"
echo -n "Enter hostname for this node (e.g. node-00) [press Enter to keep '${CURRENT_HOSTNAME}']: "
read -r HOSTNAME_NEW

if [[ -z "$HOSTNAME_NEW" ]]; then
  HOSTNAME_NEW="$CURRENT_HOSTNAME"
  warn "Keeping current hostname: $HOSTNAME_NEW"
else
  hostnamectl set-hostname "$HOSTNAME_NEW"
  echo "$HOSTNAME_NEW" > /etc/hostname

  # Update or insert the 127.0.1.1 line in /etc/hosts
  if grep -q "^127\.0\.1\.1" /etc/hosts; then
    sed -i "s/^127\.0\.1\.1.*/127.0.1.1\t${HOSTNAME_NEW}/" /etc/hosts
  else
    echo -e "127.0.1.1\t${HOSTNAME_NEW}" >> /etc/hosts
  fi

  success "Hostname set to: $HOSTNAME_NEW"
fi

# ===========================================================================
banner "Step 3 . Set timezone"
# ===========================================================================
timedatectl set-timezone Europe/Berlin
success "Timezone set to Europe/Berlin ($(timedatectl show -p Timezone --value))"

# ===========================================================================
banner "Step 4 . Firmware update check"
# ===========================================================================
if ! command -v fwupdmgr &>/dev/null; then
  info "Installing fwupd..."
  apt install -y fwupd
fi

info "Refreshing firmware metadata..."
fwupdmgr refresh --force || warn "fwupdmgr refresh failed -- continuing."

info "Checking for firmware updates..."
fwupdmgr get-updates 2>/dev/null || warn "No firmware updates found or check failed."

warn "Firmware NOT auto-applied. Review the output above and run:"
warn "  sudo fwupdmgr update"

# ===========================================================================
banner "Step 5 . Install base packages"
# ===========================================================================
BASE_PACKAGES=(
  curl wget git vim htop nvtop
  build-essential cmake unzip rsync
  net-tools dnsutils lsof jq tmux
  ca-certificates gnupg lsb-release
  apt-transport-https openssh-server
  python3 python3-pip python3-venv python3-dev
  ufw
)

info "Installing base packages: ${BASE_PACKAGES[*]}"
apt install -y "${BASE_PACKAGES[@]}"
success "Base packages installed."

# ===========================================================================
banner "Step 6 . Disable swap"
# ===========================================================================
info "Disabling swap immediately..."
swapoff -a

info "Commenting out swap entries in /etc/fstab..."
sed -i '/\bswap\b/s/^/#/' /etc/fstab

success "Swap disabled. Verify with: free -h"

# ===========================================================================
banner "Step 7 . Load kernel modules for Kubernetes"
# ===========================================================================
info "Writing /etc/modules-load.d/k3s.conf..."
cat > /etc/modules-load.d/k3s.conf <<'KMOD'
overlay
br_netfilter
KMOD

info "Loading modules now..."
modprobe overlay
modprobe br_netfilter

info "Writing /etc/sysctl.d/99-k3s.conf..."
cat > /etc/sysctl.d/99-k3s.conf <<'SYSCTL'
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
SYSCTL

info "Applying sysctl settings..."
sysctl --system

success "Kernel modules and sysctl settings applied."

# ===========================================================================
banner "=== Phase 1 Complete ==="
# ===========================================================================
NODE_IP=$(hostname -I | awk '{print $1}')
TZ_NOW=$(timedatectl show -p Timezone --value)

echo -e "${GREEN}${BOLD}"
echo "  Hostname  : $(hostname)"
echo "  IP        : ${NODE_IP}"
echo "  Timezone  : ${TZ_NOW}"
echo -e "${RESET}"
info "Next step --> run: ${BOLD}sudo bash 02_network_config.sh${RESET}"
