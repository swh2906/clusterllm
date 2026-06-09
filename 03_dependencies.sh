#!/usr/bin/env bash
# =============================================================================
# Phase 3 -- NVIDIA Drivers, CUDA, and Container Runtime
# Run locally on each node after 02_network_config.sh.
# Usage: sudo bash 03_dependencies.sh
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

REAL_USER="${SUDO_USER:-ubuntu}"

# ===========================================================================
banner "Pre-flight checks"
# ===========================================================================

# Check Ubuntu version
UBUNTU_VER=$(lsb_release -rs)
if [[ "$UBUNTU_VER" != "22.04" ]]; then
  warn "This script is designed for Ubuntu 22.04. Detected: ${UBUNTU_VER}"
  warn "Proceeding, but some steps may fail."
else
  success "Ubuntu ${UBUNTU_VER} detected."
fi

# Check Secure Boot
info "Checking Secure Boot status..."
if command -v mokutil &>/dev/null; then
  SB_STATE=$(mokutil --sb-state 2>/dev/null || echo "unknown")
else
  SB_STATE="unknown (mokutil not installed)"
fi

if echo "$SB_STATE" | grep -qi "enabled"; then
  echo ""
  echo -e "${RED}${BOLD}################################################################${RESET}"
  echo -e "${RED}${BOLD}  WARNING: SECURE BOOT IS ENABLED                              ${RESET}"
  echo -e "${RED}${BOLD}################################################################${RESET}"
  echo -e "${RED}  NVIDIA drivers require Secure Boot to be DISABLED.${RESET}"
  echo -e "${RED}  Steps to disable Secure Boot:${RESET}"
  echo -e "${RED}    1. Reboot and enter BIOS/UEFI (usually Del, F2, or F10)${RESET}"
  echo -e "${RED}    2. Navigate to Security or Boot settings${RESET}"
  echo -e "${RED}    3. Set Secure Boot to Disabled${RESET}"
  echo -e "${RED}    4. Save and exit, then re-run this script${RESET}"
  echo -e "${RED}${BOLD}################################################################${RESET}"
  echo ""
  echo -n "Continue anyway? (y/N): "
  read -r CONTINUE_SB
  if [[ ! "$CONTINUE_SB" =~ ^[Yy]$ ]]; then
    error "Aborted. Disable Secure Boot and re-run."
  fi
  warn "Continuing with Secure Boot enabled -- driver signing may be required."
else
  success "Secure Boot is disabled (or not applicable): ${SB_STATE}"
fi

# Check if nvidia-driver-535 already installed
REINSTALL_DRIVER=false
if dpkg -l | grep -q "nvidia-driver-535"; then
  warn "nvidia-driver-535 is already installed."
  echo -n "Reinstall? (y/N): "
  read -r REINSTALL_INPUT
  if [[ "$REINSTALL_INPUT" =~ ^[Yy]$ ]]; then
    REINSTALL_DRIVER=true
    info "Will reinstall nvidia-driver-535."
  else
    info "Skipping driver reinstall."
  fi
fi

# Check internet connectivity to NVIDIA servers
info "Checking connectivity to NVIDIA download servers..."
curl -sf --max-time 10 https://developer.download.nvidia.com > /dev/null   || error "Cannot reach https://developer.download.nvidia.com -- check network."
success "NVIDIA servers reachable."

# ===========================================================================
banner "Step 1 . Blacklist nouveau driver"
# ===========================================================================
NOUVEAU_CONF="/etc/modprobe.d/blacklist-nouveau.conf"

if [[ -f "$NOUVEAU_CONF" ]] && grep -q "blacklist nouveau" "$NOUVEAU_CONF"; then
  warn "nouveau already blacklisted in ${NOUVEAU_CONF} -- skipping."
else
  info "Writing ${NOUVEAU_CONF}..."
  cat > "$NOUVEAU_CONF" <<'NOUVEAU'
blacklist nouveau
options nouveau modeset=0
NOUVEAU
  info "Updating initramfs..."
  update-initramfs -u -k all
  success "nouveau blacklisted and initramfs updated."
fi

# ===========================================================================
banner "Step 2 . Add NVIDIA CUDA repository"
# ===========================================================================
CUDA_KEYRING="/usr/share/keyrings/cuda-archive-keyring.gpg"

if [[ -f "$CUDA_KEYRING" ]]; then
  warn "CUDA keyring already installed at ${CUDA_KEYRING} -- skipping download."
else
  info "Downloading CUDA keyring package..."
  wget -q -O /tmp/cuda-keyring_1.1-1_all.deb     https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2204/x86_64/cuda-keyring_1.1-1_all.deb
  info "Installing CUDA keyring..."
  dpkg -i /tmp/cuda-keyring_1.1-1_all.deb
  rm -f /tmp/cuda-keyring_1.1-1_all.deb
  success "CUDA repository keyring installed."
fi

info "Running apt update with CUDA repo..."
apt update

# ===========================================================================
banner "Step 3 . Install NVIDIA Driver 535"
# ===========================================================================
if [[ "$REINSTALL_DRIVER" == true ]] || ! dpkg -l | grep -q "nvidia-driver-535"; then
  info "Installing nvidia-driver-535..."
  DEBIAN_FRONTEND=noninteractive apt install -y nvidia-driver-535
else
  info "nvidia-driver-535 already installed -- skipping."
fi

info "Pinning nvidia-driver-535 to prevent unintended upgrades..."
cat > /etc/apt/preferences.d/nvidia-pin <<'NVPIN'
Package: nvidia-driver-*
Pin: version 535.*
Pin-Priority: 1001
NVPIN

success "NVIDIA Driver 535 installed and pinned."

# ===========================================================================
banner "Step 4 . Install CUDA Toolkit 12.3"
# ===========================================================================
info "Installing cuda-toolkit-12-3..."
DEBIAN_FRONTEND=noninteractive apt install -y cuda-toolkit-12-3

info "Pinning cuda-toolkit-12-3..."
cat >> /etc/apt/preferences.d/nvidia-pin <<'CUDAPIN'

Package: cuda-toolkit-*
Pin: version 12.3.*
Pin-Priority: 1001
CUDAPIN

info "Writing CUDA environment profile /etc/profile.d/cuda.sh..."
cat > /etc/profile.d/cuda.sh <<'CUDAENV'
# CUDA Toolkit 12.3 environment
export PATH=/usr/local/cuda-12.3/bin${PATH:+:${PATH}}
export LD_LIBRARY_PATH=/usr/local/cuda-12.3/lib64${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}
CUDAENV

success "CUDA Toolkit 12.3 installed. Source /etc/profile.d/cuda.sh or reboot to activate."

# ===========================================================================
banner "Step 5 . Install nvidia-container-toolkit"
# ===========================================================================
info "Installing nvidia-container-toolkit..."
DEBIAN_FRONTEND=noninteractive apt install -y nvidia-container-toolkit
success "nvidia-container-toolkit installed."

# ===========================================================================
banner "Step 6 . Configure containerd for NVIDIA"
# ===========================================================================
info "Configuring NVIDIA runtime for containerd..."
nvidia-ctk runtime configure --runtime=containerd
success "containerd configured with NVIDIA runtime."
info "Note: re-run this after k3s is installed (k3s uses its own containerd at /var/lib/rancher/k3s/agent/etc/containerd/config.toml)"

# ===========================================================================
banner "Step 7 . Install Docker (optional)"
# ===========================================================================
echo -n "Install Docker? (y/N): "
read -r INSTALL_DOCKER

if [[ "$INSTALL_DOCKER" =~ ^[Yy]$ ]]; then
  info "Installing Docker via get.docker.com..."
  curl -fsSL https://get.docker.com | sh
  usermod -aG docker "$REAL_USER"
  info "Configuring NVIDIA runtime for Docker..."
  nvidia-ctk runtime configure --runtime=docker
  systemctl restart docker
  success "Docker installed and configured with NVIDIA runtime."
  info "User ${REAL_USER} added to docker group (re-login required)."
else
  info "Skipping Docker installation."
fi

# ===========================================================================
banner "=== Installation Complete -- REBOOT REQUIRED ==="
# ===========================================================================
echo -e "${GREEN}${BOLD}"
echo "  Installed components:"
echo "    [+] nouveau blacklisted"
echo "    [+] CUDA repository added"
echo "    [+] NVIDIA Driver 535"
echo "    [+] CUDA Toolkit 12.3"
echo "    [+] nvidia-container-toolkit"
echo "    [+] containerd NVIDIA runtime configured"
if [[ "$INSTALL_DOCKER" =~ ^[Yy]$ ]]; then
  echo "    [+] Docker with NVIDIA runtime"
fi
echo -e "${RESET}"

echo -e "${YELLOW}${BOLD}"
echo "  ################################################################"
echo "  #                                                              #"
echo "  #   REBOOT REQUIRED before NVIDIA drivers will be active!     #"
echo "  #                                                              #"
echo "  ################################################################"
echo -e "${RESET}"

echo -e "${BOLD}Post-reboot validation commands:${RESET}"
echo "  nvidia-smi"
echo "  nvcc --version"
echo "  nvidia-container-cli info"
echo ""
echo -e "${BOLD}Expected nvidia-smi output (approximate):${RESET}"
echo "  GPU: NVIDIA T1000"
echo "  VRAM: 4096 MiB"
echo "  Driver Version: 535.x"
echo "  CUDA Version: 12.3"
echo ""

echo -n "Reboot now? (Y/n): "
read -r DO_REBOOT

if [[ ! "$DO_REBOOT" =~ ^[Nn]$ ]]; then
  info "Rebooting in 5 seconds... (Ctrl+C to cancel)"
  sleep 5
  reboot
else
  warn "Remember to reboot before proceeding to k3s setup."
fi
