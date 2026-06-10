#!/usr/bin/env bash
# =============================================================================
# 03_dependencies.sh — NVIDIA 560 + CUDA 12.6 + Container Toolkit
# Ubuntu 26.04 LTS · Ausfuehren auf JEDEM Node: sudo bash 03_dependencies.sh
# WICHTIG: Secure Boot muss DEAKTIVIERT sein!
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

banner "Dependencies: NVIDIA 560 + CUDA 12.6 (Ubuntu 26.04)"

banner "Pre-flight Checks"
# Ubuntu-Version
UBUNTU_VER=$(lsb_release -rs 2>/dev/null || echo "unknown")
if [[ "$UBUNTU_VER" != "26.04" ]]; then
    warn "Erwartet Ubuntu 26.04, gefunden: ${UBUNTU_VER}"
    warn "Dieses Skript ist fuer Ubuntu 26.04 optimiert"
fi

# Secure Boot
if command -v mokutil &>/dev/null; then
    SB=$(mokutil --sb-state 2>/dev/null || echo "unknown")
    if echo "$SB" | grep -qi "enabled"; then
        echo
        echo -e "${RED}╔══════════════════════════════════════════════════════════╗${RESET}"
        echo -e "${RED}║  SECURE BOOT IST AKTIV — NVIDIA-TREIBER WIRD NICHT      ║${RESET}"
        echo -e "${RED}║  GELADEN! Bitte zuerst im BIOS deaktivieren:             ║${RESET}"
        echo -e "${RED}║  1. Reboot → F1 → Security → Secure Boot → Disabled     ║${RESET}"
        echo -e "${RED}║  2. F10 speichern → Reboot → dieses Skript erneut       ║${RESET}"
        echo -e "${RED}╚══════════════════════════════════════════════════════════╝${RESET}"
        echo
        echo -n "  Trotzdem fortfahren? (y/N): "
        read -r CONT; [[ "$CONT" =~ ^[Yy]$ ]] || exit 1
    else
        success "Secure Boot: ${SB}"
    fi
fi

# Internet
info "Pruefe Internet-Verbindung..."
curl -sf --max-time 10 https://developer.download.nvidia.com > /dev/null || \
    error "Kein Zugriff auf developer.download.nvidia.com — Internet pruefen"
success "Internet erreichbar"

banner "Step 1 · Nouveau blacklisten"
if ! grep -q "blacklist nouveau" /etc/modprobe.d/blacklist-nouveau.conf 2>/dev/null; then
    cat > /etc/modprobe.d/blacklist-nouveau.conf << 'EOF'
blacklist nouveau
options nouveau modeset=0
EOF
    update-initramfs -u -k all
    success "Nouveau blacklisted"
else
    success "Nouveau bereits blacklisted"
fi

banner "Step 2 · NVIDIA CUDA Repository hinzufuegen (Ubuntu 26.04)"
KEYRING_URL="https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2604/x86_64/cuda-keyring_1.1-1_all.deb"
if [[ ! -f "/usr/share/keyrings/cuda-archive-keyring.gpg" ]]; then
    info "Lade CUDA Keyring herunter (ubuntu2604)..."
    wget -q --show-progress -O /tmp/cuda-keyring.deb "$KEYRING_URL"
    dpkg -i /tmp/cuda-keyring.deb
    rm -f /tmp/cuda-keyring.deb
    apt update
    success "CUDA Repository hinzugefuegt"
else
    success "CUDA Repository bereits vorhanden"
fi

banner "Step 3 · NVIDIA Driver 560 installieren"
DEBIAN_FRONTEND=noninteractive apt install -y nvidia-driver-560
cat > /etc/apt/preferences.d/nvidia-pin << 'EOF'
Package: nvidia-driver-*
Pin: version 560.*
Pin-Priority: 1001
Package: cuda-toolkit-*
Pin: version 12.6.*
Pin-Priority: 1001
EOF
success "NVIDIA Driver 560 installiert und gepinnt"

banner "Step 4 · CUDA Toolkit 12.6 installieren"
DEBIAN_FRONTEND=noninteractive apt install -y cuda-toolkit-12-6
cat > /etc/profile.d/cuda.sh << 'EOF'
export PATH=/usr/local/cuda/bin:$PATH
export LD_LIBRARY_PATH=/usr/local/cuda/lib64:$LD_LIBRARY_PATH
EOF
chmod 644 /etc/profile.d/cuda.sh
success "CUDA 12.6 installiert"

banner "Step 5 · nvidia-container-toolkit installieren"
DEBIAN_FRONTEND=noninteractive apt install -y nvidia-container-toolkit
nvidia-ctk runtime configure --runtime=containerd 2>/dev/null || \
    warn "containerd-Konfiguration wird nach k3s-Installation angewendet"
success "nvidia-container-toolkit installiert"

banner "=== Installation abgeschlossen — REBOOT ERFORDERLICH ==="
echo -e "  ${GREEN}[OK]${RESET} NVIDIA Driver 560"
echo -e "  ${GREEN}[OK]${RESET} CUDA Toolkit 12.6"
echo -e "  ${GREEN}[OK]${RESET} nvidia-container-toolkit"
echo
echo -e "${YELLOW}╔══════════════════════════════════════════════════════════╗${RESET}"
echo -e "${YELLOW}║  REBOOT ERFORDERLICH um NVIDIA-Kernel-Modul zu laden    ║${RESET}"
echo -e "${YELLOW}╚══════════════════════════════════════════════════════════╝${RESET}"
echo
echo "  Nach dem Reboot validieren:"
echo "    nvidia-smi          # Quadro T1000, 4096 MiB, Driver 560.x"
echo "    nvcc --version      # release 12.6"
echo
echo "  Dann Python-Packages installieren:"
echo "    source /opt/cluster/venv/bin/activate"
echo "    pip install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu126"
echo "    pip install 'ray[default]' 'ray[serve]' vllm"
echo "    pip install transformers accelerate datasets peft bitsandbytes trl deepspeed huggingface_hub"
echo
echo -n "  Jetzt neu starten? (Y/n): "
read -r DO_REBOOT
if [[ ! "$DO_REBOOT" =~ ^[Nn]$ ]]; then
    info "Neustart in 5 Sekunden..."
    sleep 5
    reboot
else
    warn "Bitte manuell neu starten: sudo reboot"
fi
