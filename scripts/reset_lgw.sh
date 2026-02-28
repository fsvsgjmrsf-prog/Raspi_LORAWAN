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
#
# GPIO backends (tried in order):
#   1. pinctrl  — Raspberry Pi OS Bookworm built-in; writes BCM registers
#                 directly, bypasses kernel driver claims (replaces raspi-gpio)
#   2. sysfs    — /sys/class/gpio; may fail with EINVAL if pin is kernel-claimed

set -euo pipefail

RESET_GPIO=23       # SX1302 RESET  — BCM23, Physical Pin 16
POWER_GPIO=18       # Power Enable  — BCM18, Physical Pin 12
SX1261_GPIO=22      # SX1261 RESET  — BCM22, Physical Pin 15

SYS_GPIO=/sys/class/gpio

# --- Detect GPIO backend ---------------------------------------------------

if command -v pinctrl &>/dev/null; then
    GPIO_BACKEND="pinctrl"
else
    GPIO_BACKEND="sysfs"
fi

echo "[reset_lgw] GPIO backend: ${GPIO_BACKEND}"

# --- Backend-agnostic helpers ----------------------------------------------

gpio_output_low() {
    local pin=$1
    case "${GPIO_BACKEND}" in
        pinctrl)
            pinctrl set "${pin}" op dl
            ;;
        sysfs)
            if [ ! -d "${SYS_GPIO}/gpio${pin}" ]; then
                echo "${pin}" > "${SYS_GPIO}/export" 2>/dev/null || true
                sleep 0.1
            fi
            if [ ! -d "${SYS_GPIO}/gpio${pin}" ]; then
                echo "[reset_lgw] ERROR: Cannot export GPIO${pin}." \
                     "Install pinctrl: sudo apt install pinctrl" >&2
                return 1
            fi
            echo "out" > "${SYS_GPIO}/gpio${pin}/direction"
            echo "0"   > "${SYS_GPIO}/gpio${pin}/value"
            ;;
    esac
}

gpio_output_high() {
    local pin=$1
    case "${GPIO_BACKEND}" in
        pinctrl)
            pinctrl set "${pin}" op dh
            ;;
        sysfs)
            if [ ! -d "${SYS_GPIO}/gpio${pin}" ]; then
                echo "${pin}" > "${SYS_GPIO}/export" 2>/dev/null || true
                sleep 0.1
            fi
            if [ ! -d "${SYS_GPIO}/gpio${pin}" ]; then
                echo "[reset_lgw] ERROR: Cannot export GPIO${pin}." \
                     "Install pinctrl: sudo apt install pinctrl" >&2
                return 1
            fi
            echo "out" > "${SYS_GPIO}/gpio${pin}/direction"
            echo "1"   > "${SYS_GPIO}/gpio${pin}/value"
            ;;
    esac
}

gpio_cleanup() {
    local pin=$1
    case "${GPIO_BACKEND}" in
        pinctrl)
            # Set as input (hi-z) to release the pin
            pinctrl set "${pin}" ip 2>/dev/null || true
            ;;
        sysfs)
            if [ -d "${SYS_GPIO}/gpio${pin}" ]; then
                echo "${pin}" > "${SYS_GPIO}/unexport" 2>/dev/null || true
            fi
            ;;
    esac
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
        echo "[reset_lgw] Asserting reset low..."
        gpio_output_low  ${RESET_GPIO}
        gpio_output_low  ${SX1261_GPIO}
        sleep 0.1

        echo "[reset_lgw] Enabling power (GPIO${POWER_GPIO} HIGH)..."
        gpio_output_high ${POWER_GPIO}
        sleep 0.1

        echo "[reset_lgw] Releasing SX1302 reset (GPIO${RESET_GPIO} HIGH)..."
        gpio_output_high ${RESET_GPIO}
        sleep 0.1

        echo "[reset_lgw] Releasing SX1261 reset (GPIO${SX1261_GPIO} HIGH)..."
        gpio_output_high ${SX1261_GPIO}
        sleep 0.05

        echo "[reset_lgw] Gateway powered on and reset released."
        ;;

    stop)
        echo "[reset_lgw] Asserting reset..."
        gpio_output_low ${RESET_GPIO}  2>/dev/null || true
        gpio_output_low ${SX1261_GPIO} 2>/dev/null || true
        sleep 0.05

        echo "[reset_lgw] Cutting power (GPIO${POWER_GPIO} LOW)..."
        gpio_output_low ${POWER_GPIO}  2>/dev/null || true

        gpio_cleanup ${RESET_GPIO}  || true
        gpio_cleanup ${SX1261_GPIO} || true
        gpio_cleanup ${POWER_GPIO}  || true

        echo "[reset_lgw] Gateway powered off."
        ;;
esac
