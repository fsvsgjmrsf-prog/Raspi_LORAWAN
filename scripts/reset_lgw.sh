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

# --- GPIO backend detection -------------------------------------------------
# raspi-gpio accesses BCM hardware registers directly via /dev/gpiomem,
# bypassing kernel GPIO driver claims that cause EINVAL on sysfs export.
# It is pre-installed on Raspberry Pi OS and is the preferred backend.
USE_RASPI_GPIO=0
if command -v raspi-gpio &>/dev/null; then
    USE_RASPI_GPIO=1
fi

# --- raspi-gpio helpers -----------------------------------------------------

rg_output_low() { raspi-gpio set "$1" op dl; }
rg_drive_high()  { raspi-gpio set "$1" dh; }
rg_drive_low()   { raspi-gpio set "$1" dl; }

# --- sysfs helpers ----------------------------------------------------------

gpio_export() {
    local pin=$1
    if [ ! -d "${SYS_GPIO}/gpio${pin}" ]; then
        echo "${pin}" > "${SYS_GPIO}/export" 2>/dev/null || true
        sleep 0.1
    fi
    if [ ! -d "${SYS_GPIO}/gpio${pin}" ]; then
        echo "[reset_lgw] WARNING: sysfs export of GPIO${pin} failed — continuing anyway" >&2
    fi
}

gpio_unexport() {
    local pin=$1
    if [ -d "${SYS_GPIO}/gpio${pin}" ]; then
        echo "${pin}" > "${SYS_GPIO}/unexport" 2>/dev/null || true
    fi
}

gpio_direction() { echo "$2" > "${SYS_GPIO}/gpio$1/direction"; }
gpio_write()     { echo "$2" > "${SYS_GPIO}/gpio$1/value"; }

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
        if [[ ${USE_RASPI_GPIO} -eq 1 ]]; then
            echo "[reset_lgw] GPIO backend: raspi-gpio"
            echo "[reset_lgw] Asserting reset low, power off..."
            rg_output_low ${POWER_GPIO}
            rg_output_low ${RESET_GPIO}
            rg_output_low ${SX1261_GPIO}
            sleep 0.1

            echo "[reset_lgw] Enabling power (GPIO${POWER_GPIO} HIGH)..."
            rg_drive_high ${POWER_GPIO}
            sleep 0.1

            echo "[reset_lgw] Releasing SX1302 reset (GPIO${RESET_GPIO} HIGH)..."
            rg_drive_high ${RESET_GPIO}
            sleep 0.1

            echo "[reset_lgw] Releasing SX1261 reset (GPIO${SX1261_GPIO} HIGH)..."
            rg_drive_high ${SX1261_GPIO}
            sleep 0.05
        else
            echo "[reset_lgw] GPIO backend: sysfs"
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
        fi

        echo "[reset_lgw] Gateway powered on and reset released."
        ;;

    stop)
        if [[ ${USE_RASPI_GPIO} -eq 1 ]]; then
            echo "[reset_lgw] Asserting reset..."
            rg_drive_low ${RESET_GPIO}  2>/dev/null || true
            rg_drive_low ${SX1261_GPIO} 2>/dev/null || true
            sleep 0.05

            echo "[reset_lgw] Cutting power (GPIO${POWER_GPIO} LOW)..."
            rg_drive_low ${POWER_GPIO} 2>/dev/null || true
        else
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
        fi

        echo "[reset_lgw] Gateway powered off."
        ;;
esac
