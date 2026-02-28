#!/usr/bin/env bash
# reset_lgw.sh — GPIO reset script for Elecrow LR1302 HAT (SX1302-based)
#
# Pin assignments (BCM numbering):
#   GPIO23 — SX1302 Reset     (active low pulse)
#   GPIO18 — Power Enable     (pull HIGH to power on module)
#   GPIO22 — SX1261 Reset     (LBT radio, optional)
#
# Usage:
#   sudo ./reset_lgw.sh start   # Power on and release reset
#   sudo ./reset_lgw.sh stop    # Assert reset and power off

set -euo pipefail

RESET_GPIO=23       # SX1302 RESET  — BCM23, Physical Pin 16
POWER_GPIO=18       # Power Enable  — BCM18, Physical Pin 12
SX1261_GPIO=22      # SX1261 RESET  — BCM22, Physical Pin 15

SYS_GPIO=/sys/class/gpio

# --- Helpers ---------------------------------------------------------------

gpio_export() {
    local pin=$1
    if [ ! -d "${SYS_GPIO}/gpio${pin}" ]; then
        echo "${pin}" > "${SYS_GPIO}/export" 2>/dev/null || true
        sleep 0.1   # Give the kernel time to create the gpio directory
    fi
    if [ ! -d "${SYS_GPIO}/gpio${pin}" ]; then
        echo "[reset_lgw] ERROR: Cannot export GPIO${pin} — pin may be claimed by a kernel overlay" >&2
        return 1
    fi
}

gpio_unexport() {
    local pin=$1
    if [ -d "${SYS_GPIO}/gpio${pin}" ]; then
        echo "${pin}" > "${SYS_GPIO}/unexport"
    fi
}

gpio_direction() {
    local pin=$1 dir=$2
    echo "${dir}" > "${SYS_GPIO}/gpio${pin}/direction"
}

gpio_write() {
    local pin=$1 val=$2
    echo "${val}" > "${SYS_GPIO}/gpio${pin}/value"
}

# --- Main ------------------------------------------------------------------

if [[ $# -ne 1 ]] || [[ "$1" != "start" && "$1" != "stop" ]]; then
    echo "Usage: $0 {start|stop}" >&2
    exit 1
fi

if [[ $EUID -ne 0 ]]; then
    echo "Error: this script must be run as root (use sudo)" >&2
    exit 1
fi

case "$1" in
    start)
        echo "[reset_lgw] Exporting GPIOs..."
        gpio_export  ${POWER_GPIO}
        gpio_export  ${RESET_GPIO}
        gpio_export  ${SX1261_GPIO}

        gpio_direction ${POWER_GPIO}  out
        gpio_direction ${RESET_GPIO}  out
        gpio_direction ${SX1261_GPIO} out

        echo "[reset_lgw] Asserting reset low..."
        gpio_write ${RESET_GPIO}  0
        gpio_write ${SX1261_GPIO} 0
        sleep 0.1

        echo "[reset_lgw] Enabling power (GPIO${POWER_GPIO} HIGH)..."
        gpio_write ${POWER_GPIO} 1
        sleep 0.1

        echo "[reset_lgw] Releasing SX1302 reset (GPIO${RESET_GPIO} HIGH)..."
        gpio_write ${RESET_GPIO} 1
        sleep 0.1

        echo "[reset_lgw] Releasing SX1261 reset (GPIO${SX1261_GPIO} HIGH)..."
        gpio_write ${SX1261_GPIO} 1
        sleep 0.05

        echo "[reset_lgw] Gateway powered on and reset released."
        ;;

    stop)
        echo "[reset_lgw] Asserting reset..."
        gpio_export  ${RESET_GPIO}  || true
        gpio_export  ${SX1261_GPIO} || true
        gpio_export  ${POWER_GPIO}  || true

        gpio_direction ${RESET_GPIO}  out 2>/dev/null || true
        gpio_direction ${SX1261_GPIO} out 2>/dev/null || true
        gpio_direction ${POWER_GPIO}  out 2>/dev/null || true

        gpio_write ${RESET_GPIO}  0 2>/dev/null || true
        gpio_write ${SX1261_GPIO} 0 2>/dev/null || true
        sleep 0.05

        echo "[reset_lgw] Cutting power (GPIO${POWER_GPIO} LOW)..."
        gpio_write ${POWER_GPIO} 0 2>/dev/null || true

        gpio_unexport ${RESET_GPIO}  || true
        gpio_unexport ${SX1261_GPIO} || true
        gpio_unexport ${POWER_GPIO}  || true

        echo "[reset_lgw] Gateway powered off."
        ;;
esac
