#!/usr/bin/env bash
# =============================================================================
# 04_rpc_worker.sh — ggml-rpc-server als systemd-Dienst auf einem Worker
# Ausfuehren auf JEDEM Worker: sudo bash 04_rpc_worker.sh
# (Doku 5.4) — ersetzt den manuellen Start per nohup: startet beim Booten,
# startet nach Abbruch neu, Logs ueber journalctl -u llama-rpc
# =============================================================================
set -euo pipefail
source "$(dirname "$0")/lib.sh"
require_root

banner "llama.cpp RPC-Worker"

ENTRY=$(local_entry) || error "Dieser Host steht nicht in cluster.conf — 02_network.sh ausfuehren"
NODE_NAME=$(entry_name "$ENTRY"); NODE_IP=$(entry_ip "$ENTRY")
[[ "$(entry_role "$ENTRY")" == "worker" ]] || error "${NODE_NAME} ist kein Worker (Rolle: $(entry_role "$ENTRY"))"
ip -4 -o addr show | grep -q " ${NODE_IP}/" || error "Cluster-IP ${NODE_IP} ist nicht konfiguriert — 02_network.sh ausfuehren"
check_build ggml-rpc-server
success "${NODE_NAME} · ${NODE_IP}:${RPC_PORT} · Build ${LLAMA_COMMIT:0:12}"

banner "Step 1 · Manuell gestartete RPC-Server beenden"
if pgrep -f "${LLAMA_BIN_DIR}/ggml-rpc-server" >/dev/null && ! systemctl is-active --quiet llama-rpc; then
    warn "Laufende ggml-rpc-server-Prozesse (z. B. per nohup) gefunden — werden beendet"
    pkill -f "${LLAMA_BIN_DIR}/ggml-rpc-server" || true
    sleep 2
fi
success "Port ${RPC_PORT} frei fuer den Dienst"

banner "Step 2 · systemd-Dienst llama-rpc.service"
CACHE_ARG=""
[[ "$RPC_CACHE" == "1" ]] && CACHE_ARG="-c"
cat > /etc/systemd/system/llama-rpc.service << EOF
[Unit]
Description=llama.cpp RPC-Server (${NODE_NAME} ${NODE_IP}:${RPC_PORT})
Wants=network-online.target
After=network-online.target nvidia-persistenced.service
# Nicht nach wenigen Fehlversuchen aufgeben (z. B. wenn die Cluster-IP beim Boot spaet kommt)
StartLimitIntervalSec=0

[Service]
Type=simple
User=${CLUSTER_USER}
Group=${CLUSTER_USER}
WorkingDirectory=/home/${CLUSTER_USER}
# Tensor-Cache fuer -c (spart beim erneuten Laden die Uebertragung uebers Netz)
Environment=LLAMA_CACHE=/home/${CLUSTER_USER}/.cache/llama.cpp
ExecStart=${LLAMA_BIN_DIR}/ggml-rpc-server -H ${NODE_IP} -p ${RPC_PORT} -d ${RPC_DEVICE} ${CACHE_ARG}
# ggml-rpc-server beendet sich auch bei Fehlern mit Exit-Code 0, daher "always"
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable llama-rpc >/dev/null 2>&1
systemctl restart llama-rpc
success "llama-rpc.service aktiviert und gestartet"

banner "Step 3 · Pruefen"
for i in $(seq 1 15); do
    ss -ltn | grep -q "${NODE_IP}:${RPC_PORT}" && break
    sleep 1
done
if ss -ltn | grep -q "${NODE_IP}:${RPC_PORT}"; then
    success "ggml-rpc-server lauscht auf ${NODE_IP}:${RPC_PORT}"
else
    journalctl -u llama-rpc -n 30 --no-pager
    error "ggml-rpc-server lauscht nicht — Log oben pruefen"
fi
journalctl -u llama-rpc -n 15 --no-pager | grep -E "endpoint|cache|CUDA" || true

banner "=== Worker ${NODE_NAME} bereit ==="
echo "  Status:  systemctl status llama-rpc"
echo "  Logs:    journalctl -u llama-rpc -f"
echo -e "${YELLOW}Wenn alle Worker laufen:${RESET} auf der Control Plane sudo bash 05_control_plane.sh"
