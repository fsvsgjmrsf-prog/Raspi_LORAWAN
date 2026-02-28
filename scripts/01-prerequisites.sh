#!/usr/bin/env bash
# 01-prerequisites.sh — Install prerequisites for the LoRaWAN gateway installer
#
# Run this BEFORE setup.sh on a fresh Raspberry Pi OS Lite install.
# On a clean OS, git and i2c-tools are not installed, which prevents
# cloning the repo and running pre-flight checks.
#
# Usage:
#   sudo bash scripts/01-prerequisites.sh

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
# Logging helpers
# ---------------------------------------------------------------------------
info()    { echo -e "${CYAN}[INFO]${RESET}  $*"; }
success() { echo -e "${GREEN}[OK]${RESET}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${RESET}  $*"; }
error()   { echo -e "${RED}[ERROR]${RESET} $*" >&2; }
die()     { error "$*"; exit 1; }

# ---------------------------------------------------------------------------
# Root check
# ---------------------------------------------------------------------------
[[ $EUID -eq 0 ]] || die "Run this script as root: sudo bash $0"

echo ""
echo -e "${BOLD}==========================================================${RESET}"
echo -e "${BOLD}  Elecrow LR1302 LoRaWAN Gateway — Prerequisites${RESET}"
echo -e "${BOLD}  Step 0: Install required system packages${RESET}"
echo -e "${BOLD}==========================================================${RESET}"
echo ""

# ---------------------------------------------------------------------------
# Update package lists
# ---------------------------------------------------------------------------
info "Updating package lists..."
apt-get update -y

# ---------------------------------------------------------------------------
# Upgrade installed packages (non-interactive, no recommends to stay lean)
# ---------------------------------------------------------------------------
info "Upgrading installed packages..."
apt-get upgrade -y --no-install-recommends

# ---------------------------------------------------------------------------
# Install prerequisites
# ---------------------------------------------------------------------------
info "Installing prerequisite packages..."
apt-get install -y \
    git \
    i2c-tools \
    build-essential \
    cmake \
    python3 \
    python3-pip \
    python3-dev \
    libusb-1.0-0-dev \
    raspi-gpio

success "All prerequisite packages installed"

# ---------------------------------------------------------------------------
# Make all scripts in this directory executable
# ---------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
info "Setting execute permissions on scripts in ${SCRIPT_DIR}..."
chmod +x "${SCRIPT_DIR}"/*.sh
success "Script permissions set"

# ---------------------------------------------------------------------------
# Done
# ---------------------------------------------------------------------------
echo ""
echo -e "${GREEN}${BOLD}Prerequisites installed successfully.${RESET}"
echo -e "Now run: ${CYAN}sudo bash scripts/setup.sh${RESET}"
echo ""
