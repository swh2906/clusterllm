#!/usr/bin/env bash
# =============================================================================
# 05_control_plane.sh — Verteilte Inferenz auf der Control Plane einrichten
# Ausfuehren auf der Control Plane, NACHDEM alle Worker laufen: sudo bash 05_control_plane.sh
# (Doku 5.5) Installiert:
#   - llama-cluster-wait-rpc  wartet, bis alle RPC-Server erreichbar sind
#   - llama-cluster-cli       der Multi-Node-Befehl aus der Doku (llama-cli)
#   - llama-server.service    OpenAI-kompatible API, dauerhaft als systemd-Dienst
# =============================================================================
set -euo pipefail
source "$(dirname "$0")/lib.sh"
require_root

banner "Control Plane — verteilte Inferenz"

ENTRY=$(local_entry) || error "Dieser Host steht nicht in cluster.conf — 02_network.sh ausfuehren"
NODE_NAME=$(entry_name "$ENTRY"); NODE_IP=$(entry_ip "$ENTRY")
[[ "$(entry_role "$ENTRY")" == "control" ]] || error "${NODE_NAME} ist nicht die Control Plane"
check_build llama-cli
check_build llama-server

RPC_LIST=$(rpc_endpoints)
DEVICES=$(device_list)
SPLIT=$(tensor_split)
N_WORKERS=$(worker_ips | wc -l)
BIND_HOST="${SERVER_HOST:-$NODE_IP}"
[[ $N_WORKERS -ge 1 ]] || error "Keine Worker in cluster.conf"
info "RPC-Server:   ${RPC_LIST}"
info "Geraete:      ${DEVICES}"
info "Tensor-Split: ${SPLIT}"

# Gemeinsame Modell-/Verteilungsparameter fuer CLI und Server (wie in Doku 5.5)
COMMON_ARGS="-hf ${MODEL_HF} \
  --rpc ${RPC_LIST} \
  --device ${DEVICES} \
  --split-mode layer --tensor-split ${SPLIT} \
  --fit off -ngl all -c ${INFER_CTX} -ctk ${INFER_KV_TYPE} -ctv ${INFER_KV_TYPE} \
  -fa on -b ${INFER_BATCH} -ub ${INFER_UBATCH} --no-mmproj"

banner "Step 1 · Hilfsskripte"
cat > /usr/local/bin/llama-cluster-wait-rpc << EOF
#!/usr/bin/env bash
# Wartet bis zu \${1:-120} s, bis alle RPC-Server (${RPC_LIST}) Verbindungen annehmen
deadline=\$(( SECONDS + \${1:-120} ))
for ep in ${RPC_LIST//,/ }; do
    until nc -z -w 2 "\${ep%:*}" "\${ep#*:}" 2>/dev/null; do
        if (( SECONDS >= deadline )); then
            echo "RPC-Server \${ep} nicht erreichbar" >&2
            exit 1
        fi
        sleep 2
    done
    echo "RPC-Server \${ep} erreichbar"
done
EOF
chmod 755 /usr/local/bin/llama-cluster-wait-rpc

cat > /usr/local/bin/llama-cluster-cli << EOF
#!/usr/bin/env bash
# Multi-Node-Inferenz mit llama-cli (Doku 5.5). Zusaetzliche Argumente werden angehaengt, z. B.:
#   llama-cluster-cli -p "was ist 2 + 2" -n 256 --seed 42 --temp 0
# Hinweis: Jeder RPC-Server bedient nur einen Client gleichzeitig —
# vorher den Dienst stoppen: sudo systemctl stop llama-server
if systemctl is-active --quiet llama-server; then
    echo "llama-server.service belegt die RPC-Server. Erst stoppen: sudo systemctl stop llama-server" >&2
    exit 1
fi
llama-cluster-wait-rpc 30 >/dev/null || exit 1
exec ${LLAMA_BIN_DIR}/llama-cli ${COMMON_ARGS} "\$@"
EOF
chmod 755 /usr/local/bin/llama-cluster-cli
success "/usr/local/bin/llama-cluster-wait-rpc, /usr/local/bin/llama-cluster-cli"

banner "Step 2 · RPC-Geraete pruefen"
systemctl stop llama-server 2>/dev/null || true
/usr/local/bin/llama-cluster-wait-rpc 60 || error "Nicht alle Worker erreichbar — auf den Workern: systemctl status llama-rpc"
LISTED=$(timeout 60 sudo -u "$CLUSTER_USER" -H "${LLAMA_BIN_DIR}/llama-cli" --rpc "$RPC_LIST" --list-devices 2>&1 || true)
echo "$LISTED" | sed -n '/Available devices/,$p'
N_RPC=$(echo "$LISTED" | grep -cE '^\s+RPC[0-9]+:' || true)
[[ "$N_RPC" -eq "$N_WORKERS" ]] || error "${N_RPC} RPC-Geraete gefunden, erwartet ${N_WORKERS}"
echo "$LISTED" | grep -qE '^\s+CUDA0:' || error "Lokale GPU CUDA0 nicht gefunden"
success "${N_RPC} RPC-Geraete + CUDA0 verfuegbar"

banner "Step 3 · API-Key"
mkdir -p "$(dirname "$SERVER_API_KEY_FILE")"
if [[ ! -s "$SERVER_API_KEY_FILE" ]]; then
    echo "# llama-server API-Keys, einer pro Zeile" > "$SERVER_API_KEY_FILE"
    echo "sk-$(openssl rand -hex 24)" >> "$SERVER_API_KEY_FILE"
    success "Neuer API-Key erzeugt"
else
    success "Vorhandene API-Keys werden verwendet"
fi
chown root:"$CLUSTER_USER" "$SERVER_API_KEY_FILE"
chmod 640 "$SERVER_API_KEY_FILE"

banner "Step 4 · systemd-Dienst llama-server.service"
cat > /etc/systemd/system/llama-server.service << EOF
[Unit]
Description=llama.cpp Server (verteilt ueber ${N_WORKERS} RPC-Worker + lokale GPU)
Wants=network-online.target
After=network-online.target nvidia-persistenced.service
StartLimitIntervalSec=0

[Service]
Type=simple
User=${CLUSTER_USER}
Group=${CLUSTER_USER}
WorkingDirectory=/home/${CLUSTER_USER}
Environment=LLAMA_CACHE=/home/${CLUSTER_USER}/.cache/llama.cpp
# Erst starten, wenn alle Worker erreichbar sind (nach Stromausfall booten nicht alle gleich schnell)
ExecStartPre=/usr/local/bin/llama-cluster-wait-rpc 300
ExecStart=${LLAMA_BIN_DIR}/llama-server ${COMMON_ARGS} \\
  --host ${BIND_HOST} --port ${SERVER_PORT} \\
  --parallel ${SERVER_PARALLEL} \\
  --api-key-file ${SERVER_API_KEY_FILE}
# Faellt ein Worker aus, bricht llama-server ab und verbindet sich nach dem Neustart neu
Restart=always
RestartSec=10
TimeoutStartSec=360

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable llama-server >/dev/null 2>&1
systemctl restart llama-server
success "llama-server.service aktiviert und gestartet"

banner "Step 5 · Auf Modell warten"
info "Beim ersten Start wird das Modell heruntergeladen — das kann mehrere Minuten dauern."
info "Fortschritt: journalctl -u llama-server -f"
READY=0
for i in $(seq 1 180); do
    if curl -sf "http://${BIND_HOST}:${SERVER_PORT}/health" >/dev/null 2>&1; then READY=1; break; fi
    echo -n "."
    sleep 5
done
echo
if [[ $READY -eq 1 ]]; then
    success "llama-server bereit"
else
    journalctl -u llama-server -n 40 --no-pager
    warn "Nach 15 Minuten noch nicht bereit — Log oben pruefen"
fi

API_KEY=$(grep -v '^#' "$SERVER_API_KEY_FILE" | head -1)
banner "=== Control Plane bereit ==="
echo -e "  API:       ${BOLD}http://${BIND_HOST}:${SERVER_PORT}/v1/${RESET}"
echo -e "  API-Key:   ${BOLD}${SERVER_API_KEY_FILE}${RESET}"
echo -e "  Logs:      journalctl -u llama-server -f"
echo
echo "  Test:"
echo "  curl http://${BIND_HOST}:${SERVER_PORT}/v1/chat/completions \\"
echo "    -H 'Authorization: Bearer ${API_KEY}' -H 'Content-Type: application/json' \\"
echo "    -d '{\"messages\":[{\"role\":\"user\",\"content\":\"was ist 2 + 2\"}],\"max_tokens\":64,\"temperature\":0}'"
echo
echo "  CLI (Doku-Befehl): sudo systemctl stop llama-server && llama-cluster-cli -p \"was ist 2 + 2\" -n 256 --seed 42 --temp 0"
