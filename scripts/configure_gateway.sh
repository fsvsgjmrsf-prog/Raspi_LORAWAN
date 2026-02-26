#!/usr/bin/env bash
# configure_gateway.sh — Interactive EUI + TTN configuration for Elecrow LR1302 gateway
#
# This script:
#   1. Auto-generates a Gateway EUI from the eth0 MAC address
#   2. Prompts for manual entry or accepts the auto-generated EUI
#   3. Prompts for TTN region (eu1 / nam1 / au1)
#   4. Writes /etc/lorawan-gateway/local_conf.json
#
# Run after setup.sh completes, or run standalone to reconfigure.

set -euo pipefail

# --- Colors ----------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

# --- Paths -----------------------------------------------------------------
INSTALL_DIR="/opt/lorawan-gateway"
CONFIG_DIR="/etc/lorawan-gateway"
TEMPLATE="${INSTALL_DIR}/local_conf.json.template"
OUTPUT="${CONFIG_DIR}/local_conf.json"
GLOBAL_CONF="${CONFIG_DIR}/global_conf.json"

# --- Helpers ---------------------------------------------------------------

info()    { echo -e "${CYAN}[INFO]${RESET}  $*"; }
success() { echo -e "${GREEN}[OK]${RESET}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${RESET}  $*"; }
error()   { echo -e "${RED}[ERROR]${RESET} $*" >&2; }
die()     { error "$*"; exit 1; }

require_root() {
    if [[ $EUID -ne 0 ]]; then
        die "This script must be run as root. Use: sudo $0"
    fi
}

# Auto-generate EUI-64 from eth0 MAC using FFFE insertion
# MAC: AA:BB:CC:DD:EE:FF  →  EUID: AABBCCFFFEDDFF
# (flip bit 1 of first byte per EUI-64 spec, but TTN accepts non-flipped too)
generate_eui_from_mac() {
    local iface mac eui
    iface=""

    # Try common interface names
    for candidate in eth0 end0 enp0s3 ens3 eth1; do
        if ip link show "${candidate}" &>/dev/null 2>&1; then
            iface="${candidate}"
            break
        fi
    done

    if [[ -z "${iface}" ]]; then
        # Last resort: pick first non-loopback Ethernet interface
        iface=$(ip -o link show | awk -F': ' '!/lo|wlan/ {print $2; exit}' || true)
    fi

    if [[ -z "${iface}" ]]; then
        echo ""
        return
    fi

    mac=$(cat "/sys/class/net/${iface}/address" 2>/dev/null || true)
    if [[ -z "${mac}" ]]; then
        echo ""
        return
    fi

    # Strip colons and uppercase
    mac=$(echo "${mac}" | tr -d ':' | tr '[:lower:]' '[:upper:]')

    # Insert FFFE in the middle: AABBCC → AABBCCDDEEFF → AABBCCFFFEDDEEFF
    local upper="${mac:0:6}"
    local lower="${mac:6:6}"
    eui="${upper}FFFE${lower}"

    echo "${eui}"
}

validate_eui() {
    local eui=$1
    if [[ ! "${eui}" =~ ^[0-9A-Fa-f]{16}$ ]]; then
        return 1
    fi
    return 0
}

# --- TTN Region map --------------------------------------------------------

declare -A TTN_SERVERS=(
    ["eu1"]="eu1.cloud.thethings.network"
    ["nam1"]="nam1.cloud.thethings.network"
    ["au1"]="au1.cloud.thethings.network"
    ["as1"]="as1.cloud.thethings.network"
    ["in1"]="in1.cloud.thethings.network"
)

# --- Main ------------------------------------------------------------------

require_root

echo ""
echo -e "${BOLD}===========================================================${RESET}"
echo -e "${BOLD}  LoRaWAN Gateway — TTN Configuration${RESET}"
echo -e "${BOLD}===========================================================${RESET}"
echo ""

# --- Step 1: Gateway EUI ---------------------------------------------------

AUTO_EUI=$(generate_eui_from_mac)

echo -e "${BOLD}Step 1: Gateway EUI${RESET}"
echo ""

if [[ -n "${AUTO_EUI}" ]]; then
    info "Auto-generated EUI from MAC address: ${BOLD}${AUTO_EUI}${RESET}"
    echo ""
    read -rp "Use this EUI? [Y/n]: " USE_AUTO
    USE_AUTO="${USE_AUTO:-Y}"

    if [[ "${USE_AUTO,,}" == "y" || "${USE_AUTO,,}" == "yes" ]]; then
        GATEWAY_EUI="${AUTO_EUI}"
    else
        GATEWAY_EUI=""
    fi
else
    warn "Could not auto-generate EUI (no Ethernet interface found)."
    GATEWAY_EUI=""
fi

while [[ -z "${GATEWAY_EUI}" ]] || ! validate_eui "${GATEWAY_EUI}"; do
    if [[ -n "${GATEWAY_EUI}" ]]; then
        error "Invalid EUI: '${GATEWAY_EUI}'. Must be exactly 16 hex characters (e.g. AA27EBFFFE123456)."
        echo ""
    fi
    read -rp "Enter Gateway EUI (16 hex chars, no separators): " GATEWAY_EUI
    GATEWAY_EUI=$(echo "${GATEWAY_EUI}" | tr -d ':- ' | tr '[:lower:]' '[:upper:]')
done

success "Gateway EUI: ${BOLD}${GATEWAY_EUI}${RESET}"
echo ""

# --- Step 2: TTN Region ----------------------------------------------------

echo -e "${BOLD}Step 2: TTN Region / Cluster${RESET}"
echo ""
echo "  eu1  — Europe        (eu1.cloud.thethings.network)"
echo "  nam1 — North America (nam1.cloud.thethings.network)"
echo "  au1  — Australia     (au1.cloud.thethings.network)"
echo "  as1  — Asia          (as1.cloud.thethings.network)"
echo "  in1  — India         (in1.cloud.thethings.network)"
echo ""

REGION=""
while [[ -z "${REGION}" ]]; do
    read -rp "Select region [eu1/nam1/au1/as1/in1] (default: eu1): " REGION
    REGION="${REGION:-eu1}"
    REGION="${REGION,,}"

    if [[ -z "${TTN_SERVERS[${REGION}]+_}" ]]; then
        error "Unknown region '${REGION}'. Choose from: eu1, nam1, au1, as1, in1"
        REGION=""
    fi
done

SERVER_ADDRESS="${TTN_SERVERS[${REGION}]}"
success "Server: ${BOLD}${SERVER_ADDRESS}${RESET}"
echo ""

# --- Step 3: Write local_conf.json -----------------------------------------

echo -e "${BOLD}Step 3: Writing configuration${RESET}"

mkdir -p "${CONFIG_DIR}"

cat > "${OUTPUT}" <<JSONEOF
{
    "gateway_conf": {
        "gateway_ID": "${GATEWAY_EUI}",
        "server_address": "${SERVER_ADDRESS}",
        "serv_port_up": 1700,
        "serv_port_down": 1700
    }
}
JSONEOF

success "Written: ${OUTPUT}"

# Also patch global_conf.json gateway_ID if it exists
if [[ -f "${GLOBAL_CONF}" ]]; then
    if command -v python3 &>/dev/null; then
        python3 - <<PYEOF
import json, sys
with open('${GLOBAL_CONF}', 'r') as f:
    cfg = json.load(f)
cfg.setdefault('gateway_conf', {})['gateway_ID'] = '${GATEWAY_EUI}'
# Update servers list if present
for s in cfg.get('gateway_conf', {}).get('servers', []):
    s['gateway_ID'] = '${GATEWAY_EUI}'
    s['server_address'] = '${SERVER_ADDRESS}'
with open('${GLOBAL_CONF}', 'w') as f:
    json.dump(cfg, f, indent=4)
    f.write('\n')
print('[OK]    Updated gateway_ID in global_conf.json')
PYEOF
    else
        warn "python3 not found — global_conf.json gateway_ID not patched automatically."
        warn "Edit ${GLOBAL_CONF} manually and set gateway_ID to ${GATEWAY_EUI}"
    fi
fi

# --- Step 4: Restart service if running ------------------------------------

if systemctl is-active --quiet lorawan-gateway 2>/dev/null; then
    info "Restarting lorawan-gateway service..."
    systemctl restart lorawan-gateway
    success "Service restarted."
else
    info "Service not running. Start it with: sudo systemctl start lorawan-gateway"
fi

# --- Summary ---------------------------------------------------------------

echo ""
echo -e "${BOLD}===========================================================${RESET}"
echo -e "${BOLD}  Configuration Complete${RESET}"
echo -e "${BOLD}===========================================================${RESET}"
echo ""
echo -e "  ${BOLD}Gateway EUI:${RESET}    ${GATEWAY_EUI}"
echo -e "  ${BOLD}TTN Server:${RESET}     ${SERVER_ADDRESS}:1700"
echo -e "  ${BOLD}Config file:${RESET}    ${OUTPUT}"
echo ""
echo -e "${BOLD}Next: Register your gateway in TTN Console${RESET}"
echo ""
echo -e "  1. Go to: https://console.cloud.thethings.network/"
echo -e "  2. Select cluster: ${BOLD}${REGION}${RESET}"
echo -e "  3. Gateways → Register gateway"
echo -e "  4. Gateway EUI: ${BOLD}${GATEWAY_EUI}${RESET}"
echo -e "  5. Frequency plan: ${BOLD}Europe 863-870 MHz (SF9 for RX2)${RESET}"
echo ""
echo -e "  After registration, start the service:"
echo -e "  ${CYAN}sudo systemctl start lorawan-gateway${RESET}"
echo -e "  ${CYAN}sudo journalctl -u lorawan-gateway -f${RESET}"
echo ""
