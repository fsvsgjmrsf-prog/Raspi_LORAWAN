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

# --- Detect GPIO backend ---------------------------------------------------
#
# Raspberry Pi OS Bookworm replaced raspi-gpio with pinctrl.
# Both access BCM hardware registers directly via /dev/gpiomem, bypassing
# kernel driver claims that cause EINVAL on sysfs /sys/class/gpio/export.
# Fall back to sysfs only when neither tool is available.

if command -v pinctrl &>/dev/null; then
    GPIO_BACKEND="pinctrl"
elif command -v raspi-gpio &>/dev/null; then
    GPIO_BACKEND="raspi-gpio"
else
    GPIO_BACKEND="sysfs"
fi

# --- Backend helpers -------------------------------------------------------

gpio_set() {
    # gpio_set <pin> <op>   op = "op" (output), "dh" (drive high), "dl" (drive low)
    local pin=$1 op=$2
    case "${GPIO_BACKEND}" in
        pinctrl)   pinctrl set "${pin}" "${op}" ;;
        raspi-gpio) raspi-gpio set "${pin}" "${op}" ;;
        sysfs)     _sysfs_set "${pin}" "${op}" ;;
    esac
}

_sysfs_set() {
    local pin=$1 op=$2
    if [ ! -d "${SYS_GPIO}/gpio${pin}" ]; then
        echo "${pin}" > "${SYS_GPIO}/export" 2>/dev/null || true
        sleep 0.1
    fi
    if [ ! -d "${SYS_GPIO}/gpio${pin}" ]; then
        echo "[reset_lgw] ERROR: Cannot export GPIO${pin} — pin may be claimed by a kernel overlay" >&2
        return 1
    fi
    case "${op}" in
        op) echo "out" > "${SYS_GPIO}/gpio${pin}/direction" ;;
        dh) echo "out" > "${SYS_GPIO}/gpio${pin}/direction"
            echo "1"   > "${SYS_GPIO}/gpio${pin}/value" ;;
        dl) echo "out" > "${SYS_GPIO}/gpio${pin}/direction"
            echo "0"   > "${SYS_GPIO}/gpio${pin}/value" ;;
    esac
}

gpio_unexport_sysfs() {
    local pin=$1
    if [ -d "${SYS_GPIO}/gpio${pin}" ]; then
        echo "${pin}" > "${SYS_GPIO}/unexport" 2>/dev/null || true
    fi
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

echo "[reset_lgw] GPIO backend: ${GPIO_BACKEND}"

case "$1" in
    start)
        echo "[reset_lgw] Asserting reset low..."
        gpio_set ${RESET_GPIO}  op
        gpio_set ${SX1261_GPIO} op
        gpio_set ${RESET_GPIO}  dl
        gpio_set ${SX1261_GPIO} dl
        sleep 0.1

        echo "[reset_lgw] Enabling power (GPIO${POWER_GPIO} HIGH)..."
        gpio_set ${POWER_GPIO} op
        gpio_set ${POWER_GPIO} dh
        sleep 0.1

        echo "[reset_lgw] Releasing SX1302 reset (GPIO${RESET_GPIO} HIGH)..."
        gpio_set ${RESET_GPIO} dh
        sleep 0.1

        echo "[reset_lgw] Releasing SX1261 reset (GPIO${SX1261_GPIO} HIGH)..."
        gpio_set ${SX1261_GPIO} dh
        sleep 0.05

        echo "[reset_lgw] Gateway powered on and reset released."
        ;;

    stop)
        echo "[reset_lgw] Asserting reset..."
        gpio_set ${RESET_GPIO}  op 2>/dev/null || true
        gpio_set ${SX1261_GPIO} op 2>/dev/null || true
        gpio_set ${RESET_GPIO}  dl 2>/dev/null || true
        gpio_set ${SX1261_GPIO} dl 2>/dev/null || true
        sleep 0.05

        echo "[reset_lgw] Cutting power (GPIO${POWER_GPIO} LOW)..."
        gpio_set ${POWER_GPIO} op 2>/dev/null || true
        gpio_set ${POWER_GPIO} dl 2>/dev/null || true

        if [[ "${GPIO_BACKEND}" == "sysfs" ]]; then
            gpio_unexport_sysfs ${RESET_GPIO}
            gpio_unexport_sysfs ${SX1261_GPIO}
            gpio_unexport_sysfs ${POWER_GPIO}
        fi

        echo "[reset_lgw] Gateway powered off."
        ;;
esac
