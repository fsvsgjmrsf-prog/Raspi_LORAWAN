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
#   sudo ./reset_lgw.sh stop    # Assert reset and cut power

set -euo pipefail

RESET_GPIO=23       # SX1302 RESET  — BCM23, Physical Pin 16
POWER_GPIO=18       # Power Enable  — BCM18, Physical Pin 12
SX1261_GPIO=22      # SX1261 RESET  — BCM22, Physical Pin 15

SYS_GPIO=/sys/class/gpio

# --- GPIO backend detection ------------------------------------------------
# pinctrl (Raspberry Pi OS Bookworm) writes directly to BCM hardware registers,
# bypassing kernel driver claims that cause EINVAL on sysfs export.

if command -v pinctrl > /dev/null 2>&1; then
    GPIO_BACKEND="pinctrl"
else
    GPIO_BACKEND="sysfs"
fi

echo "[reset_lgw] GPIO backend: ${GPIO_BACKEND}"

# --- Helpers ---------------------------------------------------------------

# gpio_set <pin> <0|1> [strict]
# Set a GPIO pin as output and drive it low (0) or high (1).
# If strict=true (default in start path), failures are fatal.
gpio_set() {
    local pin=$1 level=$2 strict=${3:-true}
    local dir
    [[ "${level}" == "1" ]] && dir="dh" || dir="dl"

    if [[ "${GPIO_BACKEND}" == "pinctrl" ]]; then
        if [[ "${strict}" == "true" ]]; then
            pinctrl set "${pin}" op "${dir}"
        else
            pinctrl set "${pin}" op "${dir}" 2>/dev/null || true
        fi
    else
        # sysfs fallback
        if [ ! -d "${SYS_GPIO}/gpio${pin}" ]; then
            echo "${pin}" > "${SYS_GPIO}/export" 2>/dev/null || true
            sleep 0.1
        fi
        if [ -d "${SYS_GPIO}/gpio${pin}" ]; then
            echo "out" > "${SYS_GPIO}/gpio${pin}/direction" 2>/dev/null || true
            echo "${level}" > "${SYS_GPIO}/gpio${pin}/value" 2>/dev/null || true
        elif [[ "${strict}" == "true" ]]; then
            echo "[reset_lgw] ERROR: Cannot control GPIO${pin} — pin may be claimed by a kernel overlay" >&2
            return 1
        fi
    fi
}

gpio_unexport() {
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

case "$1" in
    start)
        # Step 1: Cut power and assert resets for a clean power cycle.
        # This is critical: if the module was previously powered, we must
        # cut power and wait for capacitors to discharge before re-initialising.
        echo "[reset_lgw] Power-cycling module (GPIO${POWER_GPIO} LOW)..."
        gpio_set ${POWER_GPIO}  0
        gpio_set ${RESET_GPIO}  0
        gpio_set ${SX1261_GPIO} 0
        sleep 0.5   # Allow power rails and capacitors to discharge

        # Step 2: Enable power and let it stabilise before releasing resets.
        echo "[reset_lgw] Enabling power (GPIO${POWER_GPIO} HIGH)..."
        gpio_set ${POWER_GPIO} 1
        sleep 0.2   # Wait for 3.3V rail to be stable

        # Step 3: Hold reset low so the SX1302/SX1250 are in a defined state
        # while power stabilises further.
        echo "[reset_lgw] Asserting reset low..."
        gpio_set ${RESET_GPIO}  0
        gpio_set ${SX1261_GPIO} 0
        sleep 0.5   # Hold reset for at least 100 ms (use 500 ms for reliability)

        # Step 4: Release SX1302 reset — chip starts its internal boot sequence.
        echo "[reset_lgw] Releasing SX1302 reset (GPIO${RESET_GPIO} HIGH)..."
        gpio_set ${RESET_GPIO} 1
        sleep 0.5   # Give SX1302 + SX1250 time to complete internal boot

        # Step 5: Release SX1261 reset (LBT radio, optional).
        echo "[reset_lgw] Releasing SX1261 reset (GPIO${SX1261_GPIO} HIGH)..."
        gpio_set ${SX1261_GPIO} 1
        sleep 0.1

        echo "[reset_lgw] Gateway powered on and reset released."
        ;;

    stop)
        echo "[reset_lgw] Asserting reset..."
        gpio_set ${RESET_GPIO}  0 false
        gpio_set ${SX1261_GPIO} 0 false
        sleep 0.05

        echo "[reset_lgw] Cutting power (GPIO${POWER_GPIO} LOW)..."
        gpio_set ${POWER_GPIO} 0 false

        # Clean up sysfs exports (no-op for pinctrl backend)
        if [[ "${GPIO_BACKEND}" == "sysfs" ]]; then
            gpio_unexport ${RESET_GPIO}
            gpio_unexport ${SX1261_GPIO}
            gpio_unexport ${POWER_GPIO}
        fi

        echo "[reset_lgw] Gateway powered off."
        ;;
esac
