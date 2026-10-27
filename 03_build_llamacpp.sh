#!/usr/bin/env bash
# =============================================================================
# 03_build_llamacpp.sh — llama.cpp mit CUDA + RPC an festem Commit bauen
# Ausfuehren auf JEDEM Node als ${CLUSTER_USER} (ohne sudo): bash 03_build_llamacpp.sh
# (Doku 5.3 und 5.6) — ein gemeinsamer Build fuer Worker (ggml-rpc-server)
# und Control Plane (llama-cli, llama-server).
# =============================================================================
set -euo pipefail
source "$(dirname "$0")/lib.sh"
require_cluster_user

banner "llama.cpp Build · Commit ${LLAMA_COMMIT:0:12} · CUDA-Arch ${CUDA_ARCH}"

banner "Pre-flight Checks"
command -v nvcc >/dev/null || error "nvcc fehlt — zuerst sudo bash 01_system_setup.sh"
[[ -x "$HOST_CC" && -x "$HOST_CXX" ]] || error "${HOST_CC} / ${HOST_CXX} fehlen — sudo apt install gcc-10 g++-10"
nvidia-smi >/dev/null 2>&1 || warn "nvidia-smi funktioniert nicht (Reboot nach Treiberinstallation?)"
for svc in llama-rpc llama-server; do
    if systemctl is-active --quiet "$svc" 2>/dev/null; then
        error "${svc}.service laeuft — vor dem Neubau stoppen: sudo systemctl stop ${svc}"
    fi
done
success "nvcc $(nvcc --version | sed -n 's/.*release \([0-9.]*\).*/\1/p') · $($HOST_CXX --version | head -1)"

banner "Step 1 · Quellcode auf Commit ${LLAMA_COMMIT:0:12}"
mkdir -p "$(dirname "$LLAMA_SRC_DIR")"
if [[ ! -d "${LLAMA_SRC_DIR}/.git" ]]; then
    git init -q "$LLAMA_SRC_DIR"
    git -C "$LLAMA_SRC_DIR" remote add origin "$LLAMA_REPO"
fi
if [[ -n "$(git -C "$LLAMA_SRC_DIR" status --porcelain --untracked-files=no)" ]]; then
    error "Lokale Aenderungen in ${LLAMA_SRC_DIR} — sichern oder mit 'git -C ${LLAMA_SRC_DIR} checkout -- .' verwerfen"
fi
# Nur genau diesen Commit holen (schneller als ein voller Clone)
git -C "$LLAMA_SRC_DIR" fetch --depth 1 origin "$LLAMA_COMMIT"
git -C "$LLAMA_SRC_DIR" -c advice.detachedHead=false checkout -q "$LLAMA_COMMIT"
HEAD_SHA=$(git -C "$LLAMA_SRC_DIR" rev-parse HEAD)
[[ "$HEAD_SHA" == "$LLAMA_COMMIT" ]] || error "HEAD ist ${HEAD_SHA}, erwartet ${LLAMA_COMMIT}"
success "Quellcode: ${LLAMA_SRC_DIR} @ ${HEAD_SHA}"

banner "Step 2 · CMake konfigurieren"
cmake -S "$LLAMA_SRC_DIR" \
    -B "$LLAMA_BUILD_DIR" \
    -DCMAKE_BUILD_TYPE=Release \
    -DGGML_CUDA=ON \
    -DGGML_RPC=ON \
    -DCMAKE_CUDA_ARCHITECTURES="$CUDA_ARCH" \
    -DCMAKE_CUDA_COMPILER="$(command -v nvcc)" \
    -DCMAKE_C_COMPILER="$HOST_CC" \
    -DCMAKE_CXX_COMPILER="$HOST_CXX" \
    -DCMAKE_CUDA_HOST_COMPILER="$HOST_CXX" \
    -DLLAMA_BUILD_TESTS=OFF \
    -DLLAMA_BUILD_EXAMPLES=OFF
success "CMake konfiguriert: ${LLAMA_BUILD_DIR}"

banner "Step 3 · Kompilieren"
JOBS="${BUILD_JOBS:-$(nproc)}"
info "Baue mit ${JOBS} Jobs (dauert mit CUDA einige Minuten)..."
cmake --build "$LLAMA_BUILD_DIR" --config Release -j"$JOBS"
success "Build abgeschlossen"

banner "Step 4 · Binaries pruefen"
for bin in ggml-rpc-server llama-cli llama-server; do
    [[ -x "${LLAMA_BIN_DIR}/${bin}" ]] || error "${bin} wurde nicht gebaut"
    success "${LLAMA_BIN_DIR}/${bin}"
done
"${LLAMA_BIN_DIR}/llama-cli" --version 2>&1 | grep -iE "version|built" || true
echo
info "Lokale Geraete:"
DEVICES=$("${LLAMA_BIN_DIR}/llama-cli" --list-devices 2>&1 || true)
echo "$DEVICES" | sed -n '/Available devices/,$p'
echo "$DEVICES" | grep -q "CUDA0" && success "CUDA0 erkannt" || warn "CUDA0 nicht erkannt — Treiber/CUDA pruefen"

# Commit erst nach erfolgreichem Build festhalten
echo "$LLAMA_COMMIT" > "$LLAMA_COMMIT_FILE"
success "Commit gespeichert: ${LLAMA_COMMIT_FILE}"

banner "=== Build abgeschlossen ==="
echo -e "${YELLOW}Naechster Schritt:${RESET}"
echo "  Worker:        sudo bash 04_rpc_worker.sh"
echo "  Control Plane: sudo bash 05_control_plane.sh   (erst wenn alle Worker laufen)"
