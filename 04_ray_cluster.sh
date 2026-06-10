#!/usr/bin/env bash
# =============================================================================
# 04_ray_cluster.sh — Ray Cluster starten
# node-00: Head Node | node-01+: Worker Nodes
# Ausfuehren nach 03_dependencies.sh + Reboot
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
[[ -d "$VENV" ]] || error "Python venv nicht gefunden: ${VENV} — 01_os_config.sh zuerst ausfuehren"
source "${VENV}/bin/activate"
python3 -c "import ray" 2>/dev/null || error "Ray nicht installiert — pip install 'ray[default]' ausfuehren"

banner "Ray Cluster Setup"
echo -n "  Ist dies node-00 (Head Node)? (Y/n): "
read -r IS_HEAD

if [[ ! "$IS_HEAD" =~ ^[Nn]$ ]]; then
    # ── HEAD NODE ──────────────────────────────────────────────────────────────
    banner "Ray Head Node starten (node-00)"
    HEAD_IP="192.168.10.10"
    export NCCL_SOCKET_IFNAME=enp0s31f6
    export NCCL_IB_DISABLE=1
    export NCCL_P2P_DISABLE=1

    ray start \
        --head \
        --node-ip-address="${HEAD_IP}" \
        --port=6379 \
        --dashboard-host=0.0.0.0 \
        --dashboard-port=8265 \
        --object-store-memory=21474836480 \
        --num-gpus=1

    success "Ray Head Node gestartet"

    # systemd Service
    cat > /etc/systemd/system/ray-head.service << EOF
[Unit]
Description=Ray Head Node
After=network.target

[Service]
Type=forking
User=${SUDO_USER:-ubuntu}
Environment=NCCL_SOCKET_IFNAME=enp0s31f6
Environment=NCCL_IB_DISABLE=1
Environment=NCCL_P2P_DISABLE=1
ExecStart=${VENV}/bin/ray start --head --node-ip-address=${HEAD_IP} --port=6379 --dashboard-host=0.0.0.0 --dashboard-port=8265 --object-store-memory=21474836480 --num-gpus=1
ExecStop=${VENV}/bin/ray stop
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable ray-head
    success "ray-head.service installiert und aktiviert"

    # Cluster-Status
    sleep 3
    python3 -c "
import ray
ray.init(address='auto')
r = ray.cluster_resources()
print(f'GPUs im Cluster: {r.get(\"GPU\",0)}')
print(f'CPUs im Cluster: {r.get(\"CPU\",0)}')
print(f'RAM im Cluster:  {r.get(\"memory\",0)/1e9:.1f} GB')
ray.shutdown()
"
    echo
    echo -e "${BOLD}Ray Dashboard:${RESET} http://192.168.10.10:8265"
    echo
    echo -e "${YELLOW}Worker-Nodes joinen:${RESET}"
    echo "  Auf node-01+: sudo bash 04_ray_cluster.sh (als Worker)"

else
    # ── WORKER NODE ────────────────────────────────────────────────────────────
    banner "Ray Worker Node joinen"
    echo -n "  Head Node IP [192.168.10.10]: "
    read -r HEAD_IP; HEAD_IP="${HEAD_IP:-192.168.10.10}"
    echo -n "  Ray Port [6379]: "
    read -r RAY_PORT; RAY_PORT="${RAY_PORT:-6379}"

    export NCCL_SOCKET_IFNAME=enp0s31f6
    export NCCL_IB_DISABLE=1
    export NCCL_P2P_DISABLE=1

    ray start \
        --address="${HEAD_IP}:${RAY_PORT}" \
        --num-gpus=1

    success "Ray Worker gestartet — verbunden mit ${HEAD_IP}:${RAY_PORT}"

    cat > /etc/systemd/system/ray-worker.service << EOF
[Unit]
Description=Ray Worker Node
After=network.target

[Service]
Type=forking
User=${SUDO_USER:-ubuntu}
Environment=NCCL_SOCKET_IFNAME=enp0s31f6
Environment=NCCL_IB_DISABLE=1
Environment=NCCL_P2P_DISABLE=1
ExecStart=${VENV}/bin/ray start --address=${HEAD_IP}:${RAY_PORT} --num-gpus=1
ExecStop=${VENV}/bin/ray stop
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable ray-worker
    success "ray-worker.service installiert und aktiviert"
    echo
    info "Auf node-00 pruefen: ray status"
fi
