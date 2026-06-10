#!/usr/bin/env bash
# =============================================================================
# validate_cluster.sh — 25-Punkt Cluster-Validierung
# Ausfuehren auf jedem Node: bash validate_cluster.sh
# =============================================================================
RED='\033[0;31m'; GREEN='\033[0;32m'; CYAN='\033[0;36m'
YELLOW='\033[1;33m'; BOLD='\033[1m'; RESET='\033[0m'
PASS=0; FAIL=0

check() {
    local desc="$1"; local cmd="$2"
    if eval "$cmd" > /dev/null 2>&1; then
        echo -e "  ${GREEN}[PASS]${RESET} ${desc}"
        ((PASS++))
    else
        echo -e "  ${RED}[FAIL]${RESET} ${desc}"
        ((FAIL++))
    fi
}

check_val() {
    local desc="$1"; local cmd="$2"; local expected="$3"
    local result
    result=$(eval "$cmd" 2>/dev/null || echo "")
    if echo "$result" | grep -q "$expected"; then
        echo -e "  ${GREEN}[PASS]${RESET} ${desc}: ${result}"
        ((PASS++))
    else
        echo -e "  ${RED}[FAIL]${RESET} ${desc}: got '${result}', expected '${expected}'"
        ((FAIL++))
    fi
}

echo -e "\n${BOLD}${CYAN}=== LLM Cluster Validierung: $(hostname) ===${RESET}\n"

# 1. Hostname
check "Hostname gesetzt (nicht 'ubuntu')" "[[ '$(hostname)' != 'ubuntu' && -n '$(hostname)' ]]"

# 2. Statische IP
check "Netplan 01-cluster.yaml vorhanden" "test -f /etc/netplan/01-cluster.yaml"

# 3. Gateway erreichbar
GW=$(ip route | awk '/default/{print $3; exit}')
check "Gateway erreichbar (${GW})" "ping -c1 -W2 ${GW:-192.168.10.1}"

# 4. Internet
check "Internet erreichbar (8.8.8.8)" "ping -c1 -W3 8.8.8.8"

# 5. DNS
check "DNS funktioniert" "nslookup google.com"

# 6. Peer-Node
echo -n "  Peer-Node IP eingeben (Enter zum Ueberspringen): "
read -r PEER_IP
if [[ -n "$PEER_IP" ]]; then
    check "Peer-Node erreichbar (${PEER_IP})" "ping -c1 -W2 ${PEER_IP}"
else
    echo -e "  ${YELLOW}[SKIP]${RESET} Peer-Node Test uebersprungen"
fi

# 7. SSH passwordless
echo -n "  Peer-Hostname fuer SSH-Test (Enter zum Ueberspringen): "
read -r PEER_HOST
if [[ -n "$PEER_HOST" ]]; then
    check "SSH passwordless zu ${PEER_HOST}" "ssh -o BatchMode=yes -o ConnectTimeout=5 ${PEER_HOST} hostname"
else
    echo -e "  ${YELLOW}[SKIP]${RESET} SSH-Test uebersprungen"
fi

# 8. Secure Boot
check "Secure Boot deaktiviert" "mokutil --sb-state 2>/dev/null | grep -qi disabled"

# 9. NVIDIA driver
check "NVIDIA Driver installiert (nvidia-smi)" "nvidia-smi"

# 10. Driver Version 560
check_val "NVIDIA Driver Version" "nvidia-smi --query-gpu=driver_version --format=csv,noheader 2>/dev/null | head -1" "560"

# 11. CUDA
check "CUDA Toolkit installiert (nvcc)" "nvcc --version"

# 12. CUDA Version 12.6
check_val "CUDA Version" "nvcc --version 2>/dev/null | grep release" "12.6"

# 13. GPU VRAM 4096 MiB
check_val "GPU VRAM" "nvidia-smi --query-gpu=memory.total --format=csv,noheader 2>/dev/null | head -1" "4096"

# 14. nvidia-container-toolkit
check "nvidia-container-toolkit installiert" "dpkg -l nvidia-container-toolkit 2>/dev/null | grep -q '^ii'"

# 15. Swap deaktiviert
check "Swap deaktiviert" "[[ \$(free -m | awk '/Swap/{print \$2}') -eq 0 ]]"

# 16. Kernel-Module
check "Kernel-Modul: overlay" "lsmod | grep -q '^overlay'"
check "Kernel-Modul: br_netfilter" "lsmod | grep -q 'br_netfilter'"

# 17. IP-Forwarding
check "IP-Forwarding aktiv" "[[ \$(sysctl -n net.ipv4.ip_forward) -eq 1 ]]"

# 18. UFW aktiv
check "UFW aktiv" "sudo ufw status 2>/dev/null | grep -q 'Status: active'"

# 19. Python venv
check "Python venv vorhanden (/opt/cluster/venv)" "test -d /opt/cluster/venv"

# 20. PyTorch mit CUDA
check "PyTorch mit CUDA verfuegbar" "/opt/cluster/venv/bin/python3 -c 'import torch; assert torch.cuda.is_available()'"

# 21. Ray installiert
check "Ray installiert" "/opt/cluster/venv/bin/python3 -c 'import ray'"

# 22. vLLM installiert
check "vLLM installiert" "/opt/cluster/venv/bin/python3 -c 'import vllm'"

# 23. DeepSpeed installiert
check "DeepSpeed installiert" "/opt/cluster/venv/bin/python3 -c 'import deepspeed'"

# 24. Ray Cluster laeuft
check "Ray Cluster aktiv" "/opt/cluster/venv/bin/ray status 2>/dev/null | grep -q 'Ray runtime started'"

# 25. vLLM API antwortet
check "vLLM API antwortet (Port 8000)" "curl -sf http://localhost:8000/health"

# Zusammenfassung
TOTAL=$((PASS + FAIL))
echo
echo -e "${BOLD}=== Ergebnis: ${PASS}/${TOTAL} Checks bestanden ===${RESET}"
echo
if [[ $FAIL -eq 0 ]]; then
    echo -e "${GREEN}${BOLD}Alle Checks bestanden — Cluster bereit fuer LLM-Workloads!${RESET}"
else
    echo -e "${RED}${BOLD}${FAIL} Check(s) fehlgeschlagen — bitte beheben bevor fortgefahren wird.${RESET}"
    echo
    echo "  Haeufige Loesungen:"
    echo "  - Secure Boot: BIOS -> Security -> Secure Boot -> Disabled -> Reboot"
    echo "  - NVIDIA: sudo reboot (nach Treiber-Installation)"
    echo "  - NAT: sudo iptables -t nat -L (MASQUERADE-Regel pruefen)"
    echo "  - Ray: sudo systemctl start ray-head (node-00) oder ray-worker"
    echo "  - vLLM: sudo systemctl start vllm"
fi
echo
