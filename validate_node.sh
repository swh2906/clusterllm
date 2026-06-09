#!/usr/bin/env bash
# =============================================================================
# validate_node.sh -- Pre-flight validation for LLM cluster nodes
# Checks all prerequisites and prints a pass/fail report.
# No sudo required for most checks.
# Usage: bash validate_node.sh
# =============================================================================
set -uo pipefail

# ---------------------------------------------------------------------------
# Colour helpers
# ---------------------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
RESET='\033[0m'

# ---------------------------------------------------------------------------
# Logging functions
# ---------------------------------------------------------------------------
info()    { echo -e "${CYAN}[INFO]${RESET}  $*"; }
warn()    { echo -e "${YELLOW}[WARN]${RESET}  $*"; }
banner()  {
  echo ""
  echo -e "${BOLD}${CYAN}================================================================${RESET}"
  echo -e "${BOLD}${CYAN}  $*${RESET}"
  echo -e "${BOLD}${CYAN}================================================================${RESET}"
  echo ""
}

# ---------------------------------------------------------------------------
# Check result tracking
# ---------------------------------------------------------------------------
PASS_COUNT=0
FAIL_COUNT=0
TOTAL=19
declare -a RESULTS=()

pass() {
  local label="$1"
  local detail="${2:-}"
  PASS_COUNT=$((PASS_COUNT + 1))
  local msg
  if [[ -n "$detail" ]]; then
    msg=$(printf "${GREEN}[PASS]${RESET} %-50s %s" "$label" "$detail")
  else
    msg=$(printf "${GREEN}[PASS]${RESET} %-50s" "$label")
  fi
  RESULTS+=("$msg")
  echo -e "$msg"
}

fail() {
  local label="$1"
  local detail="${2:-}"
  FAIL_COUNT=$((FAIL_COUNT + 1))
  local msg
  if [[ -n "$detail" ]]; then
    msg=$(printf "${RED}[FAIL]${RESET} %-50s %s" "$label" "$detail")
  else
    msg=$(printf "${RED}[FAIL]${RESET} %-50s" "$label")
  fi
  RESULTS+=("$msg")
  echo -e "$msg"
}

# ===========================================================================
banner "LLM Cluster Node Validation"
# ===========================================================================
info "Running ${TOTAL} checks..."
echo ""

# ---------------------------------------------------------------------------
# Check 1: Hostname set correctly (not 'ubuntu' or empty)
# ---------------------------------------------------------------------------
CURRENT_HOSTNAME=$(hostname)
if [[ -z "$CURRENT_HOSTNAME" || "$CURRENT_HOSTNAME" == "ubuntu" ]]; then
  fail "Hostname configured" "Got: '${CURRENT_HOSTNAME}' (run 01_os_config.sh)"
else
  pass "Hostname configured" "${CURRENT_HOSTNAME}"
fi

# ---------------------------------------------------------------------------
# Check 2: Static IP configured (netplan 01-cluster.yaml exists)
# ---------------------------------------------------------------------------
if [[ -f /etc/netplan/01-cluster.yaml ]]; then
  pass "Static IP configured" "/etc/netplan/01-cluster.yaml present"
else
  fail "Static IP configured" "/etc/netplan/01-cluster.yaml not found (run 02_network_config.sh)"
fi

# ---------------------------------------------------------------------------
# Check 3: Gateway reachable
# ---------------------------------------------------------------------------
GATEWAY=""
if [[ -f /etc/netplan/01-cluster.yaml ]]; then
  GATEWAY=$(grep -oP 'via:\s*\K[0-9.]+' /etc/netplan/01-cluster.yaml 2>/dev/null | head -1 || true)
fi

if [[ -z "$GATEWAY" ]]; then
  GATEWAY=$(ip route | awk '/default/ {print $3; exit}')
fi

if [[ -n "$GATEWAY" ]] && ping -c 1 -W 2 "$GATEWAY" &>/dev/null; then
  pass "Gateway reachable" "${GATEWAY}"
else
  fail "Gateway reachable" "Cannot ping ${GATEWAY:-<no gateway detected>}"
fi

# ---------------------------------------------------------------------------
# Check 4: Internet reachable
# ---------------------------------------------------------------------------
if ping -c 1 -W 2 8.8.8.8 &>/dev/null; then
  pass "Internet reachable" "8.8.8.8 responds"
else
  fail "Internet reachable" "Cannot ping 8.8.8.8"
fi

# ---------------------------------------------------------------------------
# Check 5: DNS working
# ---------------------------------------------------------------------------
if command -v nslookup &>/dev/null && nslookup google.com &>/dev/null; then
  pass "DNS working" "nslookup google.com OK"
elif command -v dig &>/dev/null && dig +short google.com &>/dev/null; then
  pass "DNS working" "dig google.com OK"
else
  fail "DNS working" "nslookup/dig google.com failed"
fi

# ---------------------------------------------------------------------------
# Check 6: Peer node reachable
# ---------------------------------------------------------------------------
echo ""
echo -n "Enter a peer node IP to test connectivity (or press Enter to skip): "
read -r PEER_IP

if [[ -z "$PEER_IP" ]]; then
  warn "Check 6 skipped: no peer IP provided."
  FAIL_COUNT=$((FAIL_COUNT + 1))
  RESULTS+=("$(printf "${YELLOW}[SKIP]${RESET} %-50s" "Peer node reachable")")
elif ping -c 1 -W 2 "$PEER_IP" &>/dev/null; then
  pass "Peer node reachable" "${PEER_IP} responds"
else
  fail "Peer node reachable" "Cannot ping ${PEER_IP}"
fi

# ---------------------------------------------------------------------------
# Check 7: SSH passwordless to peer
# ---------------------------------------------------------------------------
echo -n "Enter peer hostname/IP for SSH test (or press Enter to skip): "
read -r PEER_SSH

if [[ -z "$PEER_SSH" ]]; then
  warn "Check 7 skipped: no peer hostname provided."
  FAIL_COUNT=$((FAIL_COUNT + 1))
  RESULTS+=("$(printf "${YELLOW}[SKIP]${RESET} %-50s" "SSH passwordless to peer")")
elif ssh -o BatchMode=yes -o ConnectTimeout=5 -o StrictHostKeyChecking=no "$PEER_SSH" "echo ok" &>/dev/null; then
  pass "SSH passwordless to peer" "${PEER_SSH}"
else
  fail "SSH passwordless to peer" "Cannot SSH to ${PEER_SSH} without password"
fi
echo ""

# ---------------------------------------------------------------------------
# Check 8: Secure Boot disabled
# ---------------------------------------------------------------------------
if command -v mokutil &>/dev/null; then
  SB_STATE=$(mokutil --sb-state 2>/dev/null || echo "unknown")
  if echo "$SB_STATE" | grep -qi "disabled"; then
    pass "Secure Boot disabled" "${SB_STATE}"
  elif echo "$SB_STATE" | grep -qi "enabled"; then
    fail "Secure Boot disabled" "Secure Boot is ENABLED -- NVIDIA drivers require it disabled"
  else
    warn "Secure Boot status unknown: ${SB_STATE}"
    FAIL_COUNT=$((FAIL_COUNT + 1))
    RESULTS+=("$(printf "${YELLOW}[WARN]${RESET} %-50s %s" "Secure Boot disabled" "${SB_STATE}")")
  fi
else
  warn "mokutil not installed -- cannot check Secure Boot status"
  FAIL_COUNT=$((FAIL_COUNT + 1))
  RESULTS+=("$(printf "${YELLOW}[WARN]${RESET} %-50s" "Secure Boot disabled (mokutil missing)")")
fi

# ---------------------------------------------------------------------------
# Check 9: NVIDIA driver installed
# ---------------------------------------------------------------------------
if command -v nvidia-smi &>/dev/null && nvidia-smi &>/dev/null; then
  pass "NVIDIA driver installed" "nvidia-smi OK"
else
  fail "NVIDIA driver installed" "nvidia-smi not found or failed (run 03_dependencies.sh + reboot)"
fi

# ---------------------------------------------------------------------------
# Check 10: NVIDIA driver version is 535.x
# ---------------------------------------------------------------------------
if command -v nvidia-smi &>/dev/null; then
  DRIVER_VER=$(nvidia-smi --query-gpu=driver_version --format=csv,noheader 2>/dev/null | head -1 || echo "")
  if echo "$DRIVER_VER" | grep -q "^535\."; then
    pass "NVIDIA driver version 535.x" "Detected: ${DRIVER_VER}"
  else
    fail "NVIDIA driver version 535.x" "Detected: '${DRIVER_VER}' (expected 535.x)"
  fi
else
  fail "NVIDIA driver version 535.x" "nvidia-smi not available"
fi

# ---------------------------------------------------------------------------
# Check 11: CUDA toolkit installed
# ---------------------------------------------------------------------------
if command -v nvcc &>/dev/null || [[ -x /usr/local/cuda/bin/nvcc ]]; then
  NVCC_BIN=$(command -v nvcc 2>/dev/null || echo "/usr/local/cuda/bin/nvcc")
  CUDA_VER=$("$NVCC_BIN" --version 2>/dev/null | grep -oP 'release \K[0-9.]+' | head -1 || echo "unknown")
  pass "CUDA toolkit installed" "nvcc version: ${CUDA_VER}"
else
  fail "CUDA toolkit installed" "nvcc not found (run 03_dependencies.sh + reboot)"
fi

# ---------------------------------------------------------------------------
# Check 12: GPU VRAM is 4096 MiB
# ---------------------------------------------------------------------------
if command -v nvidia-smi &>/dev/null; then
  VRAM=$(nvidia-smi --query-gpu=memory.total --format=csv,noheader 2>/dev/null | head -1 | tr -d ' ' || echo "")
  if echo "$VRAM" | grep -q "^4096"; then
    pass "GPU VRAM is 4096 MiB" "Detected: ${VRAM}"
  else
    fail "GPU VRAM is 4096 MiB" "Detected: '${VRAM}' (expected 4096 MiB)"
  fi
else
  fail "GPU VRAM is 4096 MiB" "nvidia-smi not available"
fi

# ---------------------------------------------------------------------------
# Check 13: nvidia-container-toolkit installed
# ---------------------------------------------------------------------------
if dpkg -l 2>/dev/null | grep -q "nvidia-container-toolkit"; then
  NCT_VER=$(dpkg -l nvidia-container-toolkit 2>/dev/null | awk '/^ii/ {print $3}' | head -1)
  pass "nvidia-container-toolkit installed" "Version: ${NCT_VER}"
else
  fail "nvidia-container-toolkit installed" "Not found (run 03_dependencies.sh)"
fi

# ---------------------------------------------------------------------------
# Check 14: Swap disabled
# ---------------------------------------------------------------------------
SWAP_TOTAL=$(free -h | awk '/^Swap:/ {print $2}')
if [[ "$SWAP_TOTAL" == "0B" || "$SWAP_TOTAL" == "0" ]]; then
  pass "Swap disabled" "Swap total: ${SWAP_TOTAL}"
else
  fail "Swap disabled" "Swap total: ${SWAP_TOTAL} (run 01_os_config.sh)"
fi

# ---------------------------------------------------------------------------
# Check 15: Kernel modules loaded: overlay
# ---------------------------------------------------------------------------
if lsmod | grep -q "^overlay"; then
  pass "Kernel module: overlay" "loaded"
else
  fail "Kernel module: overlay" "not loaded (run 01_os_config.sh)"
fi

# ---------------------------------------------------------------------------
# Check 16: Kernel modules loaded: br_netfilter
# ---------------------------------------------------------------------------
if lsmod | grep -q "^br_netfilter"; then
  pass "Kernel module: br_netfilter" "loaded"
else
  fail "Kernel module: br_netfilter" "not loaded (run 01_os_config.sh)"
fi

# ---------------------------------------------------------------------------
# Check 17: UFW active
# ---------------------------------------------------------------------------
if command -v ufw &>/dev/null; then
  UFW_STATUS=$(ufw status 2>/dev/null | head -1 || echo "inactive")
  if echo "$UFW_STATUS" | grep -qi "active"; then
    pass "UFW active" "${UFW_STATUS}"
  else
    fail "UFW active" "${UFW_STATUS} (run 02_network_config.sh)"
  fi
else
  fail "UFW active" "ufw not installed"
fi

# ---------------------------------------------------------------------------
# Check 18: Python3 available
# ---------------------------------------------------------------------------
if command -v python3 &>/dev/null; then
  PY_VER=$(python3 --version 2>&1)
  pass "python3 available" "${PY_VER}"
else
  fail "python3 available" "python3 not found (run 01_os_config.sh)"
fi

# ---------------------------------------------------------------------------
# Check 19: cmake available
# ---------------------------------------------------------------------------
if command -v cmake &>/dev/null; then
  CMAKE_VER=$(cmake --version 2>&1 | head -1)
  pass "cmake available" "${CMAKE_VER}"
else
  fail "cmake available" "cmake not found (run 01_os_config.sh)"
fi

# ---------------------------------------------------------------------------
# Check 20 (bonus): git available
# ---------------------------------------------------------------------------
if command -v git &>/dev/null; then
  GIT_VER=$(git --version 2>&1)
  pass "git available" "${GIT_VER}"
else
  fail "git available" "git not found (run 01_os_config.sh)"
fi

# ===========================================================================
banner "Validation Summary"
# ===========================================================================
echo -e "${BOLD}Results: ${PASS_COUNT}/${TOTAL} checks passed${RESET}"
echo ""

if [[ $FAIL_COUNT -eq 0 ]]; then
  echo -e "${GREEN}${BOLD}"
  echo "  All checks passed!"
  echo "  Ready for k3s cluster setup."
  echo -e "${RESET}"
else
  echo -e "${RED}${BOLD}"
  echo "  ${FAIL_COUNT} check(s) failed."
  echo "  Fix the failed checks before proceeding."
  echo -e "${RESET}"
  echo -e "${BOLD}Failed checks:${RESET}"
  for result in "${RESULTS[@]}"; do
    if echo "$result" | grep -q "\[FAIL\]"; then
      echo -e "  $result"
    fi
  done
fi
echo ""
