#!/usr/bin/env bash
# =============================================================================
# 01_system_setup.sh — System, NVIDIA-Treiber 580, CUDA-Toolkit, Build-Tools
# Ubuntu 22.04.5 LTS · Ausfuehren auf JEDEM Node: sudo bash 01_system_setup.sh
# (Doku 5.1 und 5.6)
# =============================================================================
set -euo pipefail
source "$(dirname "$0")/lib.sh"
require_root

banner "LLM-Cluster — System-Setup (Ubuntu 22.04 · ${NVIDIA_DRIVER_PKG} · CUDA ${CUDA_EXPECTED_VERSION})"

banner "Pre-flight Checks"
UBUNTU_VER=$(lsb_release -rs 2>/dev/null || echo "unknown")
if [[ "$UBUNTU_VER" != "22.04" ]]; then
    warn "Erwartet Ubuntu 22.04, gefunden: ${UBUNTU_VER}"
    echo -n "  Trotzdem fortfahren? (y/N): "
    read -r CONT; [[ "$CONT" =~ ^[Yy]$ ]] || exit 1
fi
id "$CLUSTER_USER" &>/dev/null || error "User ${CLUSTER_USER} existiert nicht"
if command -v mokutil &>/dev/null && mokutil --sb-state 2>/dev/null | grep -qi enabled; then
    warn "Secure Boot ist aktiv: Das DKMS-Modul des Treibers muss per MOK signiert werden."
    warn "apt fragt dabei nach einem MOK-Passwort, das beim naechsten Boot bestaetigt werden muss."
fi

banner "Step 1 · Hostname"
CURRENT=$(hostname)
info "Aktueller Hostname: ${CURRENT}"
info "Hostnamen laut cluster.conf: $(for e in "${CLUSTER_NODES[@]}"; do echo -n "$(entry_name "$e") "; done)"
echo -n "  Hostname fuer diesen Node [${CURRENT}]: "
read -r HOSTNAME_NEW; HOSTNAME_NEW="${HOSTNAME_NEW:-$CURRENT}"
entry_by_name "$HOSTNAME_NEW" >/dev/null || warn "${HOSTNAME_NEW} steht nicht in cluster.conf"
if [[ "$HOSTNAME_NEW" != "$CURRENT" ]]; then
    hostnamectl set-hostname "$HOSTNAME_NEW"
    if grep -q "^127\.0\.1\.1" /etc/hosts; then
        sed -i "s/^127\.0\.1\.1.*/127.0.1.1\t${HOSTNAME_NEW}/" /etc/hosts
    else
        echo -e "127.0.1.1\t${HOSTNAME_NEW}" >> /etc/hosts
    fi
fi
success "Hostname: ${HOSTNAME_NEW}"

# Cluster-Nodes in /etc/hosts (Block wird bei jedem Lauf neu geschrieben)
sed -i '/^# BEGIN llama-cluster/,/^# END llama-cluster/d' /etc/hosts
{
    echo "# BEGIN llama-cluster"
    for e in "${CLUSTER_NODES[@]}"; do echo -e "$(entry_ip "$e")\t$(entry_name "$e")"; done
    echo "# END llama-cluster"
} >> /etc/hosts
success "/etc/hosts: Cluster-Nodes eingetragen"

banner "Step 2 · System aktualisieren"
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get upgrade -y
success "System aktualisiert"

banner "Step 3 · NVIDIA-Treiber (${NVIDIA_DRIVER_PKG})"
OTHER_DRIVERS=$(dpkg-query -W -f='${db:Status-Abbrev} ${Package}\n' 'nvidia-driver-*' 2>/dev/null \
    | awk '$1 ~ /^ii/ {print $2}' | grep -v "^${NVIDIA_DRIVER_PKG}$" || true)
if [[ -n "$OTHER_DRIVERS" ]]; then
    warn "Andere Treiber-Branches installiert: ${OTHER_DRIVERS}"
    warn "Alle Nodes muessen denselben Treiber nutzen. Entfernen mit: sudo apt purge ${OTHER_DRIVERS}"
fi
DRIVER_NEW=0
if dpkg-query -W -f='${Status}' "$NVIDIA_DRIVER_PKG" 2>/dev/null | grep -q "install ok installed"; then
    success "${NVIDIA_DRIVER_PKG} bereits installiert"
else
    apt-get install -y "$NVIDIA_DRIVER_PKG"
    DRIVER_NEW=1
    success "${NVIDIA_DRIVER_PKG} installiert"
fi

# Unattended-Upgrades duerfen den Treiber nicht im laufenden Betrieb tauschen
# (sonst: "Failed to initialize NVML: Driver/library version mismatch" bis zum Reboot)
cat > /etc/apt/apt.conf.d/51-llama-cluster-nvidia << 'EOF'
// llama-cluster: NVIDIA-Pakete nur manuell aktualisieren (auf allen Nodes gleichzeitig + Reboot)
Unattended-Upgrade::Package-Blacklist {
    "nvidia-";
    "libnvidia-";
    "xserver-xorg-video-nvidia-";
};
EOF
success "NVIDIA-Pakete von unattended-upgrades ausgenommen"

banner "Step 4 · CUDA-Toolkit, Build-Werkzeuge, Hilfsprogramme"
apt-get install -y \
    nvidia-cuda-toolkit \
    python3 python3-venv cmake build-essential git \
    gcc-10 g++-10 \
    libcurl4-openssl-dev libssl-dev \
    btop nvtop pipx \
    netcat-openbsd curl ufw
sudo -u "$CLUSTER_USER" -H pipx install nvitop >/dev/null 2>&1 || true
sudo -u "$CLUSTER_USER" -H pipx ensurepath >/dev/null 2>&1 || true
success "Pakete installiert"

NVCC_VER=$(nvcc --version 2>/dev/null | sed -n 's/.*release \([0-9.]*\).*/\1/p')
if [[ "$NVCC_VER" == "$CUDA_EXPECTED_VERSION" ]]; then
    success "nvcc ${NVCC_VER}"
else
    warn "nvcc-Version ${NVCC_VER:-nicht gefunden}, erwartet ${CUDA_EXPECTED_VERSION}"
fi
[[ -x "$HOST_CC" && -x "$HOST_CXX" ]] && success "Host-Compiler: $($HOST_CXX --version | head -1)" \
    || error "${HOST_CC} / ${HOST_CXX} fehlen"

banner "Step 5 · NVIDIA Persistence Daemon"
# Haelt den Treiber geladen: schnellere CUDA-Initialisierung, stabilere Dienste
if systemctl list-unit-files nvidia-persistenced.service &>/dev/null; then
    systemctl enable nvidia-persistenced >/dev/null 2>&1 || true
    systemctl start nvidia-persistenced 2>/dev/null || true
    success "nvidia-persistenced aktiviert"
else
    warn "nvidia-persistenced.service nicht gefunden"
fi

banner "Step 6 · Zeitzone"
timedatectl set-timezone Europe/Berlin
success "Zeitzone: Europe/Berlin"

banner "=== System-Setup abgeschlossen ==="
if [[ $DRIVER_NEW -eq 1 ]] || ! nvidia-smi &>/dev/null; then
    echo -e "${YELLOW}REBOOT ERFORDERLICH, damit das NVIDIA-Kernelmodul geladen wird.${RESET}"
    echo "  Danach pruefen: nvidia-smi   (Treiber ${NVIDIA_DRIVER_MAJOR}.x)"
    echo "  Weiter mit:     sudo bash 02_network.sh"
    echo
    echo -n "  Jetzt neu starten? (Y/n): "
    read -r DO_REBOOT
    if [[ ! "$DO_REBOOT" =~ ^[Nn]$ ]]; then
        info "Neustart in 5 Sekunden..."
        sleep 5
        reboot
    fi
    warn "Bitte manuell neu starten: sudo reboot"
else
    nvidia-smi --query-gpu=name,driver_version,memory.total --format=csv,noheader
    echo -e "${YELLOW}Naechster Schritt:${RESET} sudo bash 02_network.sh"
fi
