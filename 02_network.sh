#!/usr/bin/env bash
# =============================================================================
# 02_network.sh — Cluster-Netz (statische IP per Netplan) + Firewall (UFW)
# Ausfuehren auf JEDEM Node: sudo bash 02_network.sh
# (Doku 5.2 und 5.7) — vorhandene Netplan-Dateien (Internet/WLAN) bleiben unveraendert.
# =============================================================================
set -euo pipefail
source "$(dirname "$0")/lib.sh"
require_root

banner "Cluster-Netzwerk ${CLUSTER_SUBNET}"

banner "Step 1 · Node bestimmen"
ENTRY=$(local_entry || true)
if [[ -z "$ENTRY" ]]; then
    echo -n "  Hostname dieses Nodes laut cluster.conf: "
    read -r NAME
    ENTRY=$(entry_by_name "$NAME") || error "${NAME} steht nicht in cluster.conf"
fi
NODE_NAME=$(entry_name "$ENTRY"); NODE_IP=$(entry_ip "$ENTRY"); NODE_ROLE=$(entry_role "$ENTRY")
success "${NODE_NAME} · ${NODE_IP}/${CLUSTER_PREFIX} · Rolle: ${NODE_ROLE}"

banner "Step 2 · Cluster-Interface waehlen"
info "Verfuegbare Ethernet-Interfaces:"
mapfile -t IFACES < <(ip -o link show | awk -F': ' '{print $2}' | sed 's/@.*//' \
    | grep -vE '^(lo|wl|docker|br-|virbr|veth|tailscale|tun|tap)')
for i in "${!IFACES[@]}"; do
    echo "    [$i] ${IFACES[$i]}  ($(cat "/sys/class/net/${IFACES[$i]}/operstate" 2>/dev/null))"
done
CURRENT_IFACE=$(ip -4 -o addr show | awk -v ip="${NODE_IP}/" 'index($4, ip) == 1 {print $2; exit}')
DEFAULT_IFACE="${CURRENT_IFACE:-${IFACES[0]:-}}"
echo -n "  Interface fuer das Cluster-Netz [${DEFAULT_IFACE}]: "
read -r IFACE; IFACE="${IFACE:-$DEFAULT_IFACE}"
[[ "$IFACE" =~ ^[0-9]+$ ]] && IFACE="${IFACES[$IFACE]:-}"
[[ -n "$IFACE" && -e "/sys/class/net/${IFACE}" ]] || error "Interface '${IFACE}' existiert nicht"
success "Cluster-Interface: ${IFACE}"

banner "Step 3 · Netplan schreiben"
NETPLAN_FILE="/etc/netplan/60-llama-cluster.yaml"
# Andere Netplan-Dateien duerfen dieses Interface nicht ebenfalls konfigurieren
CONFLICTS=$(grep -l "^\s*${IFACE}:" /etc/netplan/*.yaml 2>/dev/null | grep -v "$NETPLAN_FILE" || true)
if [[ -n "$CONFLICTS" ]]; then
    warn "${IFACE} wird auch hier konfiguriert: ${CONFLICTS}"
    warn "Den Block '${IFACE}:' dort entfernen (sudo nano ...), sonst werden beide Konfigurationen zusammengefuehrt."
    echo -n "  Trotzdem fortfahren? (y/N): "
    read -r CONT; [[ "$CONT" =~ ^[Yy]$ ]] || exit 1
fi
# Backup ausserhalb von /etc/netplan (dort wuerde jede .yaml mit angewendet)
BACKUP_DIR="/root/netplan-backup/$(date +%Y%m%d-%H%M%S)"
mkdir -p "$BACKUP_DIR"
cp -a /etc/netplan/. "$BACKUP_DIR/" 2>/dev/null || true
info "Backup: ${BACKUP_DIR}"

# Ubuntu Server: cloud-init darf die Netzwerkkonfiguration beim Boot nicht neu erzeugen
if [[ -d /etc/cloud/cloud.cfg.d ]]; then
    echo "network: {config: disabled}" > /etc/cloud/cloud.cfg.d/99-disable-network-config.cfg
    success "cloud-init-Netzwerkverwaltung deaktiviert"
fi

cat > "$NETPLAN_FILE" << NETPLAN
# llama-cluster: Cluster-Netz ${CLUSTER_SUBNET} (ohne Gateway, Internet laeuft ueber das andere Interface)
network:
  version: 2
  ethernets:
    ${IFACE}:
      dhcp4: false
      dhcp6: false
      accept-ra: false
      link-local: []
      addresses:
        - ${NODE_IP}/${CLUSTER_PREFIX}
      optional: false
NETPLAN
chmod 600 "$NETPLAN_FILE"
netplan generate || error "Netplan-Konfiguration ungueltig: ${NETPLAN_FILE}"

if [[ -t 0 ]]; then
    info "netplan try: Mit ENTER bestaetigen, sonst wird nach 120 s automatisch zurueckgerollt."
    netplan try --timeout 120 || error "netplan try abgebrochen — Konfiguration nicht uebernommen"
else
    netplan apply
fi
success "Netplan angewendet: ${IFACE} = ${NODE_IP}/${CLUSTER_PREFIX}"

banner "Step 4 · Firewall (UFW)"
CONTROL_IP=$(control_ip)
ufw default deny incoming >/dev/null
ufw default allow outgoing >/dev/null
ufw allow OpenSSH >/dev/null
if [[ "$NODE_ROLE" == "worker" ]]; then
    # Der RPC-Server hat keine Authentifizierung: nur die Control Plane darf ihn erreichen
    ufw allow in on "$IFACE" from "$CONTROL_IP" to "$NODE_IP" port "$RPC_PORT" proto tcp \
        comment "llama RPC von Control Plane" >/dev/null
    success "RPC-Port ${RPC_PORT}/tcp nur von ${CONTROL_IP} erlaubt"
else
    ufw allow from "$SERVER_ALLOW_FROM" to any port "$SERVER_PORT" proto tcp \
        comment "llama-server API" >/dev/null
    success "API-Port ${SERVER_PORT}/tcp von ${SERVER_ALLOW_FROM} erlaubt"
fi
ufw --force enable >/dev/null
ufw status verbose

banner "Step 5 · Erreichbarkeit der anderen Nodes"
for e in "${CLUSTER_NODES[@]}"; do
    ip=$(entry_ip "$e")
    [[ "$ip" == "$NODE_IP" ]] && continue
    if ping -c 2 -W 2 "$ip" >/dev/null 2>&1; then
        success "$(entry_name "$e") (${ip}) erreichbar"
    else
        warn "$(entry_name "$e") (${ip}) nicht erreichbar (evtl. noch nicht konfiguriert)"
    fi
done

banner "=== Netzwerk abgeschlossen ==="
echo -e "${YELLOW}Naechster Schritt:${RESET} bash 03_build_llamacpp.sh   (als ${CLUSTER_USER}, ohne sudo)"
