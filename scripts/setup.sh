#!/usr/bin/env bash
# setup.sh — One-shot installer for Elecrow LR1302 LoRaWAN Gateway on Raspberry Pi
#
# Usage:
#   sudo bash setup.sh
#
# What this script does:
#   1. Pre-flight checks (root, RPi model, OS)
#   2. Install system dependencies
#   3. Enable SPI, I2C, UART in /boot/config.txt (or /boot/firmware/config.txt)
#   4. Clone Elecrow sx1302_hal fork and build
#   5. Install binaries + configs to /opt/lorawan-gateway and /etc/lorawan-gateway
#   6. Install systemd service
#   7. Run interactive configuration (configure_gateway.sh)
#   8. Print post-install summary

set -euo pipefail

# ---------------------------------------------------------------------------
# Colors
# ---------------------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

# ---------------------------------------------------------------------------
# Step -1: Prerequisites guard
# ---------------------------------------------------------------------------
if ! command -v git >/dev/null 2>&1 || ! command -v i2cdetect >/dev/null 2>&1; then
    echo -e "${YELLOW}[WARN]  Missing prerequisites. Running 01-prerequisites.sh first...${RESET}"
    PREREQ_SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/01-prerequisites.sh"
    if [[ -f "${PREREQ_SCRIPT}" ]]; then
        bash "${PREREQ_SCRIPT}"
    else
        echo -e "${RED}[ERROR] 01-prerequisites.sh not found. Run it manually first.${RESET}"
        exit 1
    fi
fi

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
REPO_URL="https://github.com/Elecrow-RD/LR1302_loraWAN.git"
BUILD_DIR="/tmp/lr1302_build"
INSTALL_DIR="/opt/lorawan-gateway"
CONFIG_DIR="/etc/lorawan-gateway"
SYSTEMD_DIR="/etc/systemd/system"
SERVICE_NAME="lorawan-gateway"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "${SCRIPT_DIR}")"

# ---------------------------------------------------------------------------
# Logging helpers
# ---------------------------------------------------------------------------
info()    { echo -e "${CYAN}[INFO]${RESET}  $*"; }
success() { echo -e "${GREEN}[OK]${RESET}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${RESET}  $*"; }
error()   { echo -e "${RED}[ERROR]${RESET} $*" >&2; }
die()     { error "$*"; exit 1; }

section() {
    echo ""
    echo -e "${BOLD}-----------------------------------------------------------${RESET}"
    echo -e "${BOLD}  $*${RESET}"
    echo -e "${BOLD}-----------------------------------------------------------${RESET}"
}

# ---------------------------------------------------------------------------
# Step 0: Pre-flight checks
# ---------------------------------------------------------------------------

preflight_checks() {
    section "Step 0: Pre-flight checks"

    # Must be root
    [[ $EUID -eq 0 ]] || die "Run this script as root: sudo bash $0"
    success "Running as root"

    # Must be Linux
    [[ "$(uname -s)" == "Linux" ]] || die "This installer only runs on Linux (Raspberry Pi OS)"
    success "OS: Linux"

    # Check for Raspberry Pi
    if [[ -f /proc/device-tree/model ]]; then
        RPI_MODEL=$(tr -d '\0' < /proc/device-tree/model)
        info "Detected: ${RPI_MODEL}"
        if ! echo "${RPI_MODEL}" | grep -qi "raspberry"; then
            warn "This does not appear to be a Raspberry Pi. Proceeding anyway..."
        fi
    else
        warn "/proc/device-tree/model not found — cannot verify RPi model"
    fi

    # Check OS version
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        info "OS: ${PRETTY_NAME:-unknown}"
    fi

    # Determine boot config path (Pi 4+ uses /boot/firmware/)
    if [[ -f /boot/firmware/config.txt ]]; then
        BOOT_CONFIG="/boot/firmware/config.txt"
    elif [[ -f /boot/config.txt ]]; then
        BOOT_CONFIG="/boot/config.txt"
    else
        die "Cannot find /boot/config.txt or /boot/firmware/config.txt"
    fi
    info "Boot config: ${BOOT_CONFIG}"

    success "Pre-flight checks passed"
}

# ---------------------------------------------------------------------------
# Step 1: Install dependencies
# ---------------------------------------------------------------------------

install_dependencies() {
    section "Step 1: Installing system dependencies"

    apt-get update -qq
    apt-get install -y \
        git \
        gcc \
        make \
        libusb-1.0-0-dev \
        pkg-config \
        python3 \
        i2c-tools \
        raspi-config 2>/dev/null || true

    success "Dependencies installed"
}

# ---------------------------------------------------------------------------
# Step 2: Configure /boot/config.txt
# ---------------------------------------------------------------------------

configure_boot() {
    section "Step 2: Configuring boot parameters (SPI, I2C, UART)"

    local cfg="${BOOT_CONFIG}"

    # Backup
    cp "${cfg}" "${cfg}.bak.$(date +%Y%m%d_%H%M%S)"
    info "Backup: ${cfg}.bak.*"

    # Helper: add line if not already present
    add_if_missing() {
        local line=$1
        if ! grep -qF "${line}" "${cfg}"; then
            echo "${line}" >> "${cfg}"
            info "Added: ${line}"
        else
            info "Already present: ${line}"
        fi
    }

    add_if_missing "dtparam=spi=on"
    add_if_missing "dtparam=i2c_arm=on"
    add_if_missing "enable_uart=1"
    add_if_missing "dtoverlay=disable-bt"

    success "Boot config updated: ${cfg}"
    warn "A reboot is required for SPI/I2C/UART changes to take effect."
    warn "The installer will continue, but the gateway service won't start until after reboot."
}

# ---------------------------------------------------------------------------
# Step 3: Clone and build sx1302_hal (Elecrow fork)
# ---------------------------------------------------------------------------

build_sx1302_hal() {
    section "Step 3: Building sx1302_hal (Elecrow fork)"

    # Clean previous build
    if [[ -d "${BUILD_DIR}" ]]; then
        info "Removing previous build directory: ${BUILD_DIR}"
        rm -rf "${BUILD_DIR}"
    fi

    info "Cloning: ${REPO_URL}"
    git clone --depth 1 "${REPO_URL}" "${BUILD_DIR}"

    info "Building..."

    # The Elecrow fork does not have a root Makefile; build subdirectories in order.
    if [[ -f "${BUILD_DIR}/Makefile" ]]; then
        make -C "${BUILD_DIR}" -j"$(nproc)"
    else
        # Build libloragw (HAL library) first — packet_forwarder depends on it
        if [[ -f "${BUILD_DIR}/libloragw/Makefile" ]]; then
            info "Building libloragw..."
            make -C "${BUILD_DIR}/libloragw" -j"$(nproc)"
        fi

        if [[ -f "${BUILD_DIR}/packet_forwarder/Makefile" ]]; then
            info "Building packet_forwarder..."
            make -C "${BUILD_DIR}/packet_forwarder" -j"$(nproc)"
        else
            # Last resort: find the first Makefile in the tree
            local found_makefile
            found_makefile=$(find "${BUILD_DIR}" -name "Makefile" -maxdepth 3 -type f | head -1 || true)
            if [[ -n "${found_makefile}" ]]; then
                warn "No standard Makefile structure found. Attempting build in: $(dirname "${found_makefile}")"
                make -C "$(dirname "${found_makefile}")" -j"$(nproc)"
            else
                die "No Makefile found in ${BUILD_DIR}. Cannot build the sx1302_hal."
            fi
        fi
    fi

    success "Build complete"
}

# ---------------------------------------------------------------------------
# Step 4: Install binaries and configs
# ---------------------------------------------------------------------------

install_files() {
    section "Step 4: Installing files"

    # Create directories
    mkdir -p "${INSTALL_DIR}"
    mkdir -p "${CONFIG_DIR}"

    # Install packet forwarder binary
    local pkt_fwd="${BUILD_DIR}/packet_forwarder/lora_pkt_fwd"
    if [[ -f "${pkt_fwd}" ]]; then
        cp "${pkt_fwd}" "${INSTALL_DIR}/lora_pkt_fwd"
        chmod +x "${INSTALL_DIR}/lora_pkt_fwd"
        success "Installed: ${INSTALL_DIR}/lora_pkt_fwd"
    else
        # Fallback: search for it
        local found
        found=$(find "${BUILD_DIR}" -name "lora_pkt_fwd" -type f | head -1 || true)
        if [[ -n "${found}" ]]; then
            cp "${found}" "${INSTALL_DIR}/lora_pkt_fwd"
            chmod +x "${INSTALL_DIR}/lora_pkt_fwd"
            success "Installed: ${INSTALL_DIR}/lora_pkt_fwd (found at ${found})"
        else
            die "lora_pkt_fwd binary not found after build. Check build output."
        fi
    fi

    # Install reset script
    cp "${SCRIPT_DIR}/reset_lgw.sh" "${INSTALL_DIR}/reset_lgw.sh"
    chmod +x "${INSTALL_DIR}/reset_lgw.sh"
    success "Installed: ${INSTALL_DIR}/reset_lgw.sh"

    # Install local_conf.json.template
    cp "${PROJECT_DIR}/config/local_conf.json.template" "${INSTALL_DIR}/local_conf.json.template"
    success "Installed: ${INSTALL_DIR}/local_conf.json.template"

    # Install global_conf.json to /etc/lorawan-gateway (if not already present)
    if [[ ! -f "${CONFIG_DIR}/global_conf.json" ]]; then
        cp "${PROJECT_DIR}/config/global_conf.json" "${CONFIG_DIR}/global_conf.json"
        success "Installed: ${CONFIG_DIR}/global_conf.json"
    else
        info "Keeping existing: ${CONFIG_DIR}/global_conf.json"
    fi

    # Install additional Elecrow configs if present
    for conf_suffix in "sx1250.EU868" "sx1250.US915" "sx1250.AU915"; do
        local src="${BUILD_DIR}/packet_forwarder/global_conf.json.${conf_suffix}"
        if [[ -f "${src}" ]]; then
            cp "${src}" "${CONFIG_DIR}/global_conf.json.${conf_suffix}"
            info "Installed: ${CONFIG_DIR}/global_conf.json.${conf_suffix}"
        fi
    done

    success "Files installed to ${INSTALL_DIR} and ${CONFIG_DIR}"
}

# ---------------------------------------------------------------------------
# Step 5: Install systemd service
# ---------------------------------------------------------------------------

install_service() {
    section "Step 5: Installing systemd service"

    local svc_src="${PROJECT_DIR}/systemd/lorawan-gateway.service"
    local svc_dst="${SYSTEMD_DIR}/${SERVICE_NAME}.service"

    cp "${svc_src}" "${svc_dst}"
    success "Installed: ${svc_dst}"

    systemctl daemon-reload
    systemctl enable "${SERVICE_NAME}"
    success "Service enabled: ${SERVICE_NAME}"
    info "Start with: sudo systemctl start ${SERVICE_NAME}"
}

# ---------------------------------------------------------------------------
# Step 6: Run interactive gateway configuration
# ---------------------------------------------------------------------------

run_configure() {
    section "Step 6: Gateway EUI + TTN configuration"

    local cfg_script="${SCRIPT_DIR}/configure_gateway.sh"
    chmod +x "${cfg_script}"
    bash "${cfg_script}"
}

# ---------------------------------------------------------------------------
# Step 7: Final summary
# ---------------------------------------------------------------------------

print_summary() {
    section "Installation Complete"

    echo ""
    echo -e "${BOLD}  Installed files:${RESET}"
    echo -e "    ${INSTALL_DIR}/lora_pkt_fwd"
    echo -e "    ${INSTALL_DIR}/reset_lgw.sh"
    echo -e "    ${CONFIG_DIR}/global_conf.json"
    echo -e "    ${CONFIG_DIR}/local_conf.json"
    echo -e "    ${SYSTEMD_DIR}/${SERVICE_NAME}.service"
    echo ""
    echo -e "${BOLD}  Service management:${RESET}"
    echo -e "    ${CYAN}sudo systemctl start ${SERVICE_NAME}${RESET}"
    echo -e "    ${CYAN}sudo systemctl stop ${SERVICE_NAME}${RESET}"
    echo -e "    ${CYAN}sudo systemctl status ${SERVICE_NAME}${RESET}"
    echo -e "    ${CYAN}sudo journalctl -u ${SERVICE_NAME} -f${RESET}"
    echo ""
    echo -e "${BOLD}  Logs:${RESET}"
    echo -e "    ${CYAN}sudo journalctl -u ${SERVICE_NAME} --since today${RESET}"
    echo ""
    echo -e "${YELLOW}  IMPORTANT: Reboot required for SPI/I2C/UART to be active!${RESET}"
    echo -e "    ${CYAN}sudo reboot${RESET}"
    echo ""
    echo -e "  After reboot, the service will start automatically."
    echo -e "  Monitor with: ${CYAN}sudo journalctl -u ${SERVICE_NAME} -f${RESET}"
    echo ""
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

main() {
    echo ""
    echo -e "${BOLD}==========================================================${RESET}"
    echo -e "${BOLD}  Elecrow LR1302 LoRaWAN Gateway — Installer${RESET}"
    echo -e "${BOLD}  Target: Raspberry Pi 3/4, EU868, TTN${RESET}"
    echo -e "${BOLD}==========================================================${RESET}"
    echo ""

    preflight_checks
    install_dependencies
    configure_boot
    build_sx1302_hal
    install_files
    install_service
    run_configure
    print_summary
}

main "$@"
