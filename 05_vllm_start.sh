#!/usr/bin/env bash
# =============================================================================
# 05_vllm_start.sh — vLLM mit Tensor Parallelism starten
# Nur auf node-00 ausfuehren: bash 05_vllm_start.sh
# =============================================================================
set -euo pipefail
RED='\033[0;31m'; GREEN='\033[0;32m'; CYAN='\033[0;36m'
YELLOW='\033[1;33m'; BOLD='\033[1m'; RESET='\033[0m'
info()    { echo -e "${CYAN}[INFO]${RESET}  $*"; }
success() { echo -e "${GREEN}[OK]${RESET}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${RESET}  $*"; }
error()   { echo -e "${RED}[ERROR]${RESET} $*"; exit 1; }
banner()  { echo -e "\n${BOLD}${CYAN}=== $* ===${RESET}\n"; }

VENV="/opt/cluster/venv"
[[ -d "$VENV" ]] || error "Python venv nicht gefunden"
source "${VENV}/bin/activate"
python3 -c "import vllm" 2>/dev/null || error "vLLM nicht installiert — pip install vllm"

banner "vLLM Setup mit Tensor Parallelism"

banner "Step 1 · Modell herunterladen"
echo -n "  HuggingFace Modell-ID [meta-llama/Meta-Llama-3.1-8B-Instruct]: "
read -r MODEL_ID; MODEL_ID="${MODEL_ID:-meta-llama/Meta-Llama-3.1-8B-Instruct}"
MODEL_NAME=$(basename "$MODEL_ID")
MODEL_PATH="/opt/cluster/models/${MODEL_NAME}"

if [[ -d "$MODEL_PATH" ]]; then
    warn "Modell bereits vorhanden: ${MODEL_PATH}"
else
    echo -n "  HuggingFace Token (fuer Llama-Modelle erforderlich): "
    read -r HF_TOKEN
    if [[ -n "$HF_TOKEN" ]]; then
        huggingface-cli login --token "$HF_TOKEN"
    fi
    info "Lade Modell herunter: ${MODEL_ID}"
    mkdir -p /opt/cluster/models
    huggingface-cli download "$MODEL_ID" --local-dir "$MODEL_PATH"
    success "Modell heruntergeladen: ${MODEL_PATH}"
fi

banner "Step 2 · Anzahl GPUs im Ray Cluster ermitteln"
GPU_COUNT=$(python3 -c "
import ray
try:
    ray.init(address='auto', ignore_reinit_error=True)
    gpus = int(ray.cluster_resources().get('GPU', 0))
    print(gpus)
    ray.shutdown()
except Exception:
    print(1)
" 2>/dev/null)
info "GPUs im Cluster: ${GPU_COUNT}"
echo -n "  Tensor Parallel Size (= Anzahl Nodes/GPUs) [${GPU_COUNT}]: "
read -r TP_SIZE; TP_SIZE="${TP_SIZE:-$GPU_COUNT}"
[[ "$TP_SIZE" -lt 1 ]] && TP_SIZE=1
success "Tensor Parallel Size: ${TP_SIZE}"

banner "Step 3 · vLLM starten"
export NCCL_SOCKET_IFNAME=enp0s31f6
export NCCL_IB_DISABLE=1
export NCCL_P2P_DISABLE=1
export NCCL_DEBUG=WARN

# systemd Service schreiben
cat > /etc/systemd/system/vllm.service << EOF
[Unit]
Description=vLLM API Server (Tensor Parallelism TP=${TP_SIZE})
After=network.target ray-head.service

[Service]
Type=simple
User=${SUDO_USER:-ubuntu}
WorkingDirectory=/opt/cluster
Environment=NCCL_SOCKET_IFNAME=enp0s31f6
Environment=NCCL_IB_DISABLE=1
Environment=NCCL_P2P_DISABLE=1
Environment=NCCL_DEBUG=WARN
ExecStart=${VENV}/bin/python3 -m vllm.entrypoints.openai.api_server \\
  --model ${MODEL_PATH} \\
  --tensor-parallel-size ${TP_SIZE} \\
  --host 0.0.0.0 \\
  --port 8000 \\
  --max-model-len 6144 \\
  --gpu-memory-utilization 0.90 \\
  --dtype float16 \\
  --served-model-name llm
Restart=on-failure
RestartSec=30
TimeoutStartSec=300

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now vllm
success "vllm.service gestartet"

banner "Step 4 · API testen (warte auf Start...)"
for i in $(seq 1 30); do
    if curl -sf http://localhost:8000/health > /dev/null 2>&1; then
        success "vLLM API erreichbar!"
        break
    fi
    echo -n "."
    sleep 5
done
echo

curl -s http://localhost:8000/v1/models | python3 -m json.tool 2>/dev/null || warn "Modell-Liste nicht abrufbar"

banner "=== vLLM laeuft ==="
echo -e "  API Endpunkt:    ${BOLD}http://192.168.10.10:8000/v1/${RESET}"
echo -e "  Modell:          ${BOLD}${MODEL_NAME}${RESET}"
echo -e "  Tensor Parallel: ${BOLD}${TP_SIZE}${RESET}"
echo
echo "  Test:"
echo "  curl http://192.168.10.10:8000/v1/chat/completions \\"
echo "    -H 'Content-Type: application/json' \\"
echo "    -d '{\"model\":\"llm\",\"messages\":[{\"role\":\"user\",\"content\":\"Hallo!\"}],\"max_tokens\":64}'"
