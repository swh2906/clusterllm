#!/usr/bin/env bash
# =============================================================================
# validate_cluster.sh — Cluster-Validierung (llama.cpp RPC-Stack)
# Ausfuehren auf jedem Node als ${CLUSTER_USER}: bash validate_cluster.sh
# Die Rolle (worker/control) wird aus cluster.conf erkannt.
# =============================================================================
source "$(dirname "$0")/lib.sh"
PASS=0; FAIL=0; SKIP=0

pass() { echo -e "  ${GREEN}[PASS]${RESET} $*"; PASS=$((PASS + 1)); }
fail() { echo -e "  ${RED}[FAIL]${RESET} $*"; FAIL=$((FAIL + 1)); }
skip() { echo -e "  ${YELLOW}[SKIP]${RESET} $*"; SKIP=$((SKIP + 1)); }
check() { if eval "$2" >/dev/null 2>&1; then pass "$1"; else fail "$1"; fi; }

ENTRY=$(local_entry || true)
if [[ -z "$ENTRY" ]]; then
    echo -e "${RED}$(hostname) steht nicht in cluster.conf (weder Hostname noch Cluster-IP)${RESET}"
    exit 1
fi
NODE_NAME=$(entry_name "$ENTRY"); NODE_IP=$(entry_ip "$ENTRY"); NODE_ROLE=$(entry_role "$ENTRY")
BIN="$LLAMA_BIN_DIR"

echo -e "\n${BOLD}${CYAN}=== Validierung: ${NODE_NAME} (${NODE_IP}, ${NODE_ROLE}) ===${RESET}"

echo -e "\n${BOLD}System & Netzwerk${RESET}"
UBUNTU_VER=$(lsb_release -rs 2>/dev/null)
[[ "$UBUNTU_VER" == "22.04" ]] && pass "Ubuntu ${UBUNTU_VER}" || fail "Ubuntu ${UBUNTU_VER:-?}, erwartet 22.04"
check "Cluster-IP ${NODE_IP} konfiguriert" "ip -4 -o addr show | grep -q ' ${NODE_IP}/'"
for e in "${CLUSTER_NODES[@]}"; do
    ip=$(entry_ip "$e"); [[ "$ip" == "$NODE_IP" ]] && continue
    check "$(entry_name "$e") (${ip}) erreichbar" "ping -c1 -W2 ${ip}"
done
if sudo -n true 2>/dev/null; then
    check "UFW aktiv" "sudo -n ufw status | grep -q 'Status: active'"
else
    skip "UFW-Status (braucht sudo ohne Passwort)"
fi

echo -e "\n${BOLD}Treiber & Toolchain${RESET}"
DRV=$(nvidia-smi --query-gpu=driver_version --format=csv,noheader 2>/dev/null | head -1)
[[ "$DRV" == ${NVIDIA_DRIVER_MAJOR}.* ]] && pass "NVIDIA-Treiber ${DRV}" || fail "NVIDIA-Treiber '${DRV:-keiner}', erwartet ${NVIDIA_DRIVER_MAJOR}.x"
GPU=$(nvidia-smi --query-gpu=name,compute_cap,memory.total --format=csv,noheader 2>/dev/null | head -1)
[[ "$GPU" == *", ${CUDA_ARCH:0:1}.${CUDA_ARCH:1}"* ]] && pass "GPU: ${GPU}" || fail "GPU '${GPU:-keine}', erwartet Compute Capability ${CUDA_ARCH:0:1}.${CUDA_ARCH:1}"
check "nvidia-persistenced aktiv" "systemctl is-active --quiet nvidia-persistenced"
NVCC=$(nvcc --version 2>/dev/null | sed -n 's/.*release \([0-9.]*\).*/\1/p')
[[ "$NVCC" == "$CUDA_EXPECTED_VERSION" ]] && pass "nvcc ${NVCC}" || fail "nvcc '${NVCC:-fehlt}', erwartet ${CUDA_EXPECTED_VERSION}"
check "Host-Compiler ${HOST_CXX}" "test -x ${HOST_CXX}"

echo -e "\n${BOLD}llama.cpp Build${RESET}"
BUILT=$(cat "$LLAMA_COMMIT_FILE" 2>/dev/null)
[[ "$BUILT" == "$LLAMA_COMMIT" ]] && pass "Build-Commit ${BUILT:0:12}" || fail "Build-Commit '${BUILT:-fehlt}', erwartet ${LLAMA_COMMIT:0:12}"
SRC=$(git -C "$LLAMA_SRC_DIR" rev-parse HEAD 2>/dev/null)
[[ "$SRC" == "$LLAMA_COMMIT" ]] && pass "Quellcode-HEAD ${SRC:0:12}" || fail "Quellcode-HEAD '${SRC:-fehlt}'"
for b in ggml-rpc-server llama-cli llama-server; do check "Binary ${b}" "test -x ${BIN}/${b}"; done

if [[ "$NODE_ROLE" == "worker" ]]; then
    echo -e "\n${BOLD}RPC-Worker${RESET}"
    check "llama-rpc.service aktiv" "systemctl is-active --quiet llama-rpc"
    check "llama-rpc.service beim Boot aktiviert" "systemctl is-enabled --quiet llama-rpc"
    check "Lauscht auf ${NODE_IP}:${RPC_PORT}" "ss -ltn | grep -q '${NODE_IP}:${RPC_PORT}'"
    N=$(pgrep -fc "${BIN}/ggml-rpc-server")
    [[ "$N" -eq 1 ]] && pass "Genau ein ggml-rpc-server-Prozess" || fail "${N} ggml-rpc-server-Prozesse (alte nohup-Instanzen?)"
else
    echo -e "\n${BOLD}Control Plane${RESET}"
    for ip in $(worker_ips); do
        check "RPC ${ip}:${RPC_PORT} erreichbar" "nc -z -w 3 ${ip} ${RPC_PORT}"
    done
    check "llama-server.service beim Boot aktiviert" "systemctl is-enabled --quiet llama-server"
    if systemctl is-active --quiet llama-server; then
        pass "llama-server.service aktiv"
        HOST="${SERVER_HOST:-$NODE_IP}"
        [[ "$HOST" == "0.0.0.0" ]] && HOST="127.0.0.1"
        check "API /health antwortet (${HOST}:${SERVER_PORT})" "curl -sf http://${HOST}:${SERVER_PORT}/health"
        skip "RPC-Geraeteliste (RPC-Server sind von llama-server belegt)"
    else
        fail "llama-server.service nicht aktiv"
        LISTED=$(timeout 60 "${BIN}/llama-cli" --rpc "$(rpc_endpoints)" --list-devices 2>&1)
        N=$(echo "$LISTED" | grep -cE '^\s+RPC[0-9]+:')
        [[ "$N" -eq $(worker_ips | wc -l) ]] && pass "${N} RPC-Geraete gelistet" || fail "${N} RPC-Geraete gelistet, erwartet $(worker_ips | wc -l)"
    fi

    # Einheitlichkeit: Treiber und Commit auf allen Nodes gleich (braucht SSH-Key-Login)
    for e in "${CLUSTER_NODES[@]}"; do
        ip=$(entry_ip "$e"); [[ "$ip" == "$NODE_IP" ]] && continue
        R=$(ssh -o BatchMode=yes -o ConnectTimeout=5 "${CLUSTER_USER}@${ip}" \
            "cat ${LLAMA_COMMIT_FILE}; nvidia-smi --query-gpu=driver_version --format=csv,noheader | head -1" 2>/dev/null)
        if [[ -z "$R" ]]; then
            skip "$(entry_name "$e"): Versionsvergleich (kein SSH-Key-Login)"
            continue
        fi
        R_COMMIT=$(sed -n 1p <<< "$R"); R_DRV=$(sed -n 2p <<< "$R")
        [[ "$R_COMMIT" == "$LLAMA_COMMIT" && "$R_DRV" == "$DRV" ]] \
            && pass "$(entry_name "$e"): gleicher Commit und Treiber ${R_DRV}" \
            || fail "$(entry_name "$e"): Commit ${R_COMMIT:0:12}, Treiber ${R_DRV} (lokal ${DRV})"
    done
fi

TOTAL=$((PASS + FAIL))
echo
echo -e "${BOLD}=== Ergebnis: ${PASS}/${TOTAL} bestanden, ${SKIP} uebersprungen ===${RESET}"
if [[ $FAIL -eq 0 ]]; then
    echo -e "${GREEN}${BOLD}Alle Checks bestanden.${RESET}"
else
    echo -e "${RED}${BOLD}${FAIL} Check(s) fehlgeschlagen.${RESET}"
    echo "  Haeufige Ursachen:"
    echo "  - Treiber: nach Installation/Update sudo reboot"
    echo "  - Build:   bash 03_build_llamacpp.sh"
    echo "  - Worker:  journalctl -u llama-rpc -n 50"
    echo "  - Server:  journalctl -u llama-server -n 50"
    echo "  - Netz:    ip -br addr; sudo ufw status"
fi
echo
exit $(( FAIL > 0 ))
