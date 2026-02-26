# Elecrow LR1302 HAT — Hardware Reference

## Overview

The Elecrow LR1302 HAT mounts directly on the Raspberry Pi 40-pin GPIO header.
It integrates:
- **SX1302** LoRa baseband processor (SPI interface)
- **SX1250** RF front-end (dual radio, EU868/US915/AU915 variants)
- **SX1261** auxiliary radio (for Listen-Before-Talk / LBT, optional)
- **u-blox MAX-M8Q** GPS module (UART interface)
- **DS3231** RTC module (I2C @ 0x68)
- SMA connector for LoRa antenna
- SMA connector for GPS antenna (active, 3.3V)

---

## 40-Pin GPIO Map

```
                    3V3  [ 1] [ 2]  5V
        SDA (I2C/RTC) [ 3] [ 4]  5V
        SCL (I2C/RTC) [ 5] [ 6]  GND
                       [ 7] [ 8]  UART TX → GPS RX
                   GND [ 9] [10]  UART RX ← GPS TX
                       [11] [12]  GPIO18  ← POWER ENABLE
                       [13] [14]  GND
           SX1261 RST  [15] [16]  GPIO23  ← SX1302 RESET
                    3V3 [17] [18]  (GPIO24)
         SPI0 MOSI [19] [20]  GND
         SPI0 MISO [21] [22]  (GPIO25)
          SPI0 CLK [23] [24]  GPIO8  ← SPI0 CE0
                   GND [25] [26]  (SPI0 CE1)
                       [27] [28]
                       [29] [30]  GND
                       [31] [32]
                       [33] [34]  GND
                       [35] [36]
                       [37] [38]
                   GND [39] [40]
```

---

## Signal Assignments

| Signal            | BCM GPIO | Physical Pin | Direction  | Notes                              |
|-------------------|----------|--------------|------------|------------------------------------|
| **SX1302 Reset**  | GPIO23   | Pin 16       | Output     | Active low pulse to reset SX1302   |
| **Power Enable**  | GPIO18   | Pin 12       | Output     | Pull HIGH to power on module       |
| **SX1261 Reset**  | GPIO22   | Pin 15       | Output     | LBT radio reset (optional feature) |
| **SPI0 MOSI**     | GPIO10   | Pin 19       | Output     | SPI bus to SX1302                  |
| **SPI0 MISO**     | GPIO9    | Pin 21       | Input      | SPI bus from SX1302                |
| **SPI0 CLK**      | GPIO11   | Pin 23       | Output     | SPI clock                          |
| **SPI0 CE0**      | GPIO8    | Pin 24       | Output     | Chip select → `/dev/spidev0.0`     |
| **UART TX**       | GPIO14   | Pin 8        | Output     | Pi TX → GPS RX (serial console!)   |
| **UART RX**       | GPIO15   | Pin 10       | Input      | GPS TX → Pi RX                     |
| **I2C SDA**       | GPIO2    | Pin 3        | Bi-dir     | DS3231 RTC @ I2C address 0x68      |
| **I2C SCL**       | GPIO3    | Pin 5        | Output     | I2C clock                          |

---

## Required Kernel Overlays (`/boot/config.txt`)

Add these lines to `/boot/config.txt` (or `/boot/firmware/config.txt` on Pi 4+):

```ini
# Enable SPI for SX1302
dtparam=spi=on

# Enable I2C for DS3231 RTC
dtparam=i2c_arm=on

# Enable UART (primary) for GPS
enable_uart=1

# Free UART0 from Bluetooth (Pi 3/4 with BT)
dtoverlay=disable-bt
```

**Reboot required** after modifying `config.txt`.

---

## Jumper Settings

The LR1302 module plugs into the HAT via a Hirose DF40 connector or similar.
No jumpers need to be set for standard EU868 SPI operation.

| Jumper / Header | Default State | Purpose                             |
|-----------------|---------------|-------------------------------------|
| J1 (GPS enable) | Bridged       | Connects GPS UART to Pi GPIO14/15   |
| J2 (LBT enable) | Open          | Enables SX1261 LBT — bridge if needed |
| ANT1            | Required      | LoRa SMA antenna (must be connected!) |
| ANT2 (GPS)      | Recommended   | Active GPS antenna (3.3V bias)      |

> **Warning:** Never power on the LR1302 without a LoRa antenna connected.
> Operating without an antenna can damage the RF front-end.

---

## Physical Assembly

1. **Power off the Raspberry Pi completely** before installing the HAT.
2. Align the HAT's 40-pin header with the Pi's GPIO header.
3. Press down firmly and evenly until seated. No screws required for testing,
   but use M2.5 standoffs + screws for permanent installation.
4. Connect the **LoRa SMA antenna** to the `ANT` port (required).
5. Optionally connect a **GPS SMA antenna** to `ANT-GPS` (active, 3.3V supply).
6. Power on the Pi via the USB-C / micro-USB port.

---

## SPI Device Verification

After enabling SPI and rebooting, verify the SPI device exists:

```bash
ls -la /dev/spidev0.*
# Expected: /dev/spidev0.0  /dev/spidev0.1
```

If not present, check:
```bash
lsmod | grep spi
dmesg | grep spi
```

---

## GPS UART Configuration

The GPS module uses the Pi's primary UART (`/dev/ttyS0` on Pi 3, `/dev/ttyAMA0` on Pi 4+).

**Conflict: serial console**
By default, Raspberry Pi OS attaches a serial console to UART0.
This conflicts with GPS. Disable it:

```bash
sudo raspi-config
# → Interface Options → Serial Port
# → "Would you like a login shell to be accessible over the serial port?" → No
# → "Would you like the serial port hardware to be enabled?" → Yes
```

Or edit `/boot/cmdline.txt` and remove `console=serial0,115200`.

Verify GPS UART:
```bash
sudo stty -F /dev/ttyS0 9600
sudo cat /dev/ttyS0
# Should see NMEA sentences: $GPGGA, $GPRMC, etc.
```

---

## I2C RTC Verification

```bash
sudo i2cdetect -y 1
# Expected output includes '68' at row 6, column 8 (address 0x68 = DS3231)
```

---

## Power Requirements

| Component         | Voltage | Current (typical) |
|-------------------|---------|-------------------|
| Raspberry Pi 3B   | 5V      | 500–700 mA        |
| LR1302 HAT (idle) | 5V      | ~150 mA           |
| LR1302 HAT (TX)   | 5V      | ~400 mA peak      |
| GPS module        | 3.3V    | ~25 mA (from Pi)  |
| **Total**         | **5V**  | **~1.0–1.5 A**    |

**Recommended power supply:** 5V / 2.5A (official Pi PSU or equivalent).
Insufficient power is a common cause of SPI errors and gateway instability.

---

## Known Issues

### 1. Serial console conflicts with GPS
**Symptom:** GPS UART produces garbage or no data.
**Fix:** Disable serial login shell via `raspi-config` (see GPS section above).

### 2. SPI not found (`/dev/spidev0.0 not found`)
**Symptom:** `lora_pkt_fwd` fails with "failed to open SPI device".
**Fix:** Ensure `dtparam=spi=on` is in `config.txt` and Pi has been rebooted.

### 3. Permission denied on `/dev/spidev0.0`
**Symptom:** Non-root user gets permission error.
**Fix:** Run gateway service as root (default), or add user to `spi` group:
```bash
sudo usermod -aG spi $USER
```

### 4. GPIO export fails ("Device or resource busy")
**Symptom:** `reset_lgw.sh` fails on GPIO export.
**Fix:** Unexport lingering GPIOs:
```bash
echo 23 > /sys/class/gpio/unexport
echo 18 > /sys/class/gpio/unexport
echo 22 > /sys/class/gpio/unexport
```

### 5. No uplink packets in TTN Console
**Checklist:**
- [ ] LoRa antenna connected to `ANT` port
- [ ] Gateway EUI registered in TTN Console
- [ ] Correct frequency plan selected (EU868 for Europe)
- [ ] `journalctl -u lorawan-gateway -f` shows "PUSH_ACK" responses
- [ ] End device is in range and configured for EU868
- [ ] `global_conf.json` has correct `gateway_ID`

---

## Reference Links

- [Elecrow LR1302 Wiki](https://www.elecrow.com/wiki/index.php?title=LR1302_LoRaWAN_Gateway_Module)
- [Elecrow sx1302_hal fork](https://github.com/Elecrow-RD/LR1302_loraWAN)
- [Semtech sx1302_hal upstream](https://github.com/Lora-net/sx1302_hal)
- [TTN Console](https://console.cloud.thethings.network/)
- [TTN Gateway Registration Guide](https://www.thethingsindustries.com/docs/gateways/adding-gateways/)
- [Raspberry Pi GPIO Pinout](https://pinout.xyz/)
