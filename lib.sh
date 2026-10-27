#!/usr/bin/env bash
# =============================================================================
# lib.sh — Gemeinsame Funktionen fuer alle Cluster-Skripte (wird per source geladen)
# =============================================================================
RED='\033[0;31m'; GREEN='\033[0;32m'; CYAN='\033[0;36m'
YELLOW='\033[1;33m'; BOLD='\033[1m'; RESET='\033[0m'
info()    { echo -e "${CYAN}[INFO]${RESET}  $*"; }
success() { echo -e "${GREEN}[OK]${RESET}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${RESET}  $*"; }
error()   { echo -e "${RED}[ERROR]${RESET} $*" >&2; exit 1; }
banner()  { echo -e "\n${BOLD}${CYAN}=== $* ===${RESET}\n"; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[[ -f "${SCRIPT_DIR}/cluster.conf" ]] || error "cluster.conf nicht gefunden in ${SCRIPT_DIR}"
# shellcheck source=cluster.conf
source "${SCRIPT_DIR}/cluster.conf"

require_root() { [[ $EUID -eq 0 ]] || error "Mit sudo ausfuehren: sudo bash $0"; }

require_cluster_user() {
    [[ "$(id -un)" == "$CLUSTER_USER" ]] || error "Als ${CLUSTER_USER} ausfuehren (nicht root): bash $0"
}

# --- Node-Tabelle ------------------------------------------------------------
entry_name() { cut -d: -f1 <<< "$1"; }
entry_ip()   { cut -d: -f2 <<< "$1"; }
entry_role() { cut -d: -f3 <<< "$1"; }

entry_by_name() {
    local e
    for e in "${CLUSTER_NODES[@]}"; do
        [[ "$(entry_name "$e")" == "$1" ]] && { echo "$e"; return 0; }
    done
    return 1
}

# Eintrag dieses Hosts: zuerst ueber eine konfigurierte Cluster-IP, sonst ueber den Hostnamen
local_entry() {
    local e
    for e in "${CLUSTER_NODES[@]}"; do
        ip -4 -o addr show | grep -q " $(entry_ip "$e")/" && { echo "$e"; return 0; }
    done
    entry_by_name "$(hostname)"
}

control_ip() {
    local e
    for e in "${CLUSTER_NODES[@]}"; do
        [[ "$(entry_role "$e")" == "control" ]] && { entry_ip "$e"; return 0; }
    done
    error "Kein Node mit Rolle 'control' in cluster.conf"
}

worker_ips() {
    local e
    for e in "${CLUSTER_NODES[@]}"; do
        [[ "$(entry_role "$e")" == "worker" ]] && entry_ip "$e"
    done
}

# "10.10.10.6:50052,10.10.10.7:50052,..."
rpc_endpoints() {
    local ip out=()
    for ip in $(worker_ips); do out+=("${ip}:${RPC_PORT}"); done
    (IFS=,; echo "${out[*]}")
}

# "RPC0,RPC1,...,CUDA0" — Geraete-Reihenfolge wie in der Doku (Worker zuerst, lokale GPU zuletzt)
device_list() {
    local i n out=()
    n=$(worker_ips | wc -l)
    for ((i = 0; i < n; i++)); do out+=("RPC${i}"); done
    out+=("CUDA0")
    (IFS=,; echo "${out[*]}")
}

# "1,1,...,1" — gleichmaessige Aufteilung auf alle Geraete
tensor_split() {
    local i n out=()
    n=$(( $(worker_ips | wc -l) + 1 ))
    for ((i = 0; i < n; i++)); do out+=("1"); done
    (IFS=,; echo "${out[*]}")
}

# Prueft, ob der gebaute Stand dem konfigurierten Commit entspricht
check_build() {
    [[ -x "${LLAMA_BIN_DIR}/$1" ]] || error "${LLAMA_BIN_DIR}/$1 fehlt — zuerst 03_build_llamacpp.sh ausfuehren"
    local built
    built=$(cat "$LLAMA_COMMIT_FILE" 2>/dev/null || true)
    [[ "$built" == "$LLAMA_COMMIT" ]] || \
        error "Build-Commit (${built:-unbekannt}) != cluster.conf (${LLAMA_COMMIT}) — 03_build_llamacpp.sh erneut ausfuehren"
}
