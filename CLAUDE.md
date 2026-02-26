# IOT_Gateway — Elecrow LR1302 LoRaWAN Gateway

Complete installation toolkit for a production-ready LoRaWAN gateway using the
**Elecrow LR1302 HAT** on a **Raspberry Pi 3B/B+**, connecting to **The Things Network (TTN)**
via the EU868 frequency plan. Bare-metal deployment with systemd service management.

---

## Architecture

```
  ┌─────────────────────────────────────────────────────────────┐
  │                  Raspberry Pi 3B/B+                         │
  │                                                             │
  │  ┌──────────────────────┐   SPI0     ┌──────────────────┐  │
  │  │    lora_pkt_fwd      │ ─────────► │  Elecrow LR1302  │  │
  │  │  (UDP Packet Fwd)    │            │  SX1302 + SX1250  │  │
  │  │  /opt/lorawan-       │   GPIO     │  HAT              │  │
  │  │    gateway/          │ ─────────► │  (40-pin GPIO)   │  │
  │  └──────────┬───────────┘            └────────┬─────────┘  │
  │             │                                  │            │
  │             │ UDP/1700                         │ RF         │
  │             ▼                                  ▼            │
  │      Internet / LAN                      SMA Antenna        │
  └─────────────────────────────────────────────────────────────┘
                    │
                    ▼ UDP port 1700
  ┌─────────────────────────────────────────┐
  │     The Things Network (TTN)            │
  │     eu1.cloud.thethings.network         │
  │     EU868 — 8 channels, SF7-SF12        │
  └─────────────────────────────────────────┘
```

---

## Hardware Requirements

| Component            | Specification                                  |
|----------------------|------------------------------------------------|
| SBC                  | Raspberry Pi 3B, 3B+, 4B, or Zero 2W          |
| LoRaWAN HAT          | Elecrow LR1302 (SX1302 + SX1250)               |
| OS                   | Raspberry Pi OS Lite (Bullseye or Bookworm)    |
| Power Supply         | 5V / 2.5A minimum (3A recommended)             |
| LoRa Antenna         | SMA, 868 MHz, 2–3 dBi (REQUIRED)              |
| GPS Antenna          | Active SMA, 3.3V bias (optional)               |
| Network              | Ethernet or WiFi with internet access          |
| Storage              | 8 GB+ microSD card (Class 10)                  |

---

## Prerequisites

Before running the installer:

1. **Fresh Raspberry Pi OS Lite** installed and booted
2. **SSH access** enabled (or keyboard + monitor)
3. **Internet connectivity** (Ethernet recommended for stability)
4. **TTN account** at https://console.cloud.thethings.network/
5. **LoRa antenna** physically connected to the HAT's `ANT` SMA port

---

## Hardware Setup

### 1. Physical Assembly

1. **Power off** the Raspberry Pi completely
2. Align the LR1302 HAT's 40-pin header with the Pi's GPIO header
3. Press down firmly and evenly until fully seated
4. Connect a **LoRa SMA antenna** to the `ANT` port (mandatory — never power without!)
5. Optionally connect a **GPS SMA antenna** to `ANT-GPS`
6. Power on the Pi

### 2. Verify HAT is detected

```bash
# Check SPI device (after enabling in step below)
ls /dev/spidev0.0

# Check I2C (DS3231 RTC at 0x68)
sudo i2cdetect -y 1
```

See `hardware/elecrow-lr1302-pinout.md` for full GPIO map and jumper reference.

---

## Software Installation

### Quick Install (one command)

```bash
# Clone this repository
git clone <this-repo> ~/IOT_Gateway
cd ~/IOT_Gateway

# Run the installer as root
sudo bash scripts/setup.sh
```

The installer will:
1. Check your Raspberry Pi model and OS
2. Install required packages (`git`, `gcc`, `make`, `libusb-1.0-0-dev`, etc.)
3. Enable SPI, I2C, and UART in `/boot/config.txt`
4. Clone and build the [Elecrow sx1302_hal fork](https://github.com/Elecrow-RD/LR1302_loraWAN)
5. Install binaries to `/opt/lorawan-gateway/`
6. Install configuration to `/etc/lorawan-gateway/`
7. Install and enable the systemd service
8. Run the interactive Gateway EUI + TTN configuration
9. Print the post-install summary

### Reboot Required

After installation, reboot to activate SPI/I2C/UART:

```bash
sudo reboot
```

After reboot, the `lorawan-gateway` service starts automatically.

---

## TTN Console Registration

1. Log in at https://console.cloud.thethings.network/
2. Select the **eu1** cluster (Europe)
3. Navigate to **Gateways** → **Register gateway**
4. Fill in:
   - **Gateway EUI**: (printed by `configure_gateway.sh`, also in `/etc/lorawan-gateway/local_conf.json`)
   - **Gateway ID**: any unique lowercase string (e.g. `my-rpi-lorawan-gw`)
   - **Frequency plan**: `Europe 863-870 MHz (SF9 for RX2 — recommended)`
5. Click **Register gateway**
6. Start the service and monitor logs (see below)

---

## Post-Install Verification

### 1. Check service status

```bash
sudo systemctl status lorawan-gateway
```

### 2. Follow live logs

```bash
sudo journalctl -u lorawan-gateway -f
```

Expected healthy output:
```
[INFO] concentrator started, packet can now be received
[INFO] PUSH_ACK received in X ms
[INFO] # TX requests    0   # TX rejected    0
```

### 3. Verify SPI communication

```bash
# Should show spidev0.0 and spidev0.1
ls -la /dev/spidev0.*
```

### 4. Verify GPIO exports during operation

```bash
ls /sys/class/gpio/
# Should show gpio18, gpio22, gpio23 while service is running
```

### 5. Check TTN Console

In TTN Console → your gateway → **Live data** tab.
Within a minute of starting the service you should see a **Gateway connected** event.

---

## Systemd Service Management

```bash
# Start the gateway
sudo systemctl start lorawan-gateway

# Stop the gateway
sudo systemctl stop lorawan-gateway

# Restart (after config change)
sudo systemctl restart lorawan-gateway

# Enable auto-start on boot (already done by installer)
sudo systemctl enable lorawan-gateway

# Disable auto-start
sudo systemctl disable lorawan-gateway

# Check status
sudo systemctl status lorawan-gateway

# View logs (all time)
sudo journalctl -u lorawan-gateway

# View logs (since last boot)
sudo journalctl -u lorawan-gateway -b

# Follow live logs
sudo journalctl -u lorawan-gateway -f
```

---

## Reconfiguration

To change the Gateway EUI or TTN server:

```bash
sudo bash scripts/configure_gateway.sh
sudo systemctl restart lorawan-gateway
```

---

## File Reference

```
IOT_Gateway/
├── CLAUDE.md                          ← This file
├── .gitignore                         ← Standard ignores (local_conf.json excluded)
│
├── scripts/
│   ├── setup.sh                       ← One-shot installer (run as root)
│   ├── configure_gateway.sh           ← Interactive EUI + TTN config
│   └── reset_lgw.sh                   ← GPIO reset (used by systemd service)
│
├── config/
│   ├── global_conf.json               ← EU868 UDP packet forwarder config
│   └── local_conf.json.template       ← Template for local EUI overrides
│
├── systemd/
│   └── lorawan-gateway.service        ← Systemd unit file
│
└── hardware/
    └── elecrow-lr1302-pinout.md       ← GPIO map, jumpers, hardware notes
```

### Installed Paths (after `setup.sh`)

| Source                          | Installed To                                |
|---------------------------------|---------------------------------------------|
| `scripts/reset_lgw.sh`          | `/opt/lorawan-gateway/reset_lgw.sh`         |
| `config/global_conf.json`       | `/etc/lorawan-gateway/global_conf.json`     |
| (generated by configure_gateway)| `/etc/lorawan-gateway/local_conf.json`      |
| (built from Elecrow repo)       | `/opt/lorawan-gateway/lora_pkt_fwd`         |
| `systemd/lorawan-gateway.service`| `/etc/systemd/system/lorawan-gateway.service`|

---

## Troubleshooting

### SPI device not found

```
ERROR: failed to open SPI device /dev/spidev0.0
```

- Ensure `dtparam=spi=on` is in `/boot/config.txt` (or `/boot/firmware/config.txt`)
- Reboot: `sudo reboot`
- Verify: `ls /dev/spidev0.*`

### Permission denied on SPI

```
ERROR: /dev/spidev0.0: Permission denied
```

- The service runs as root by default — check the unit file
- Or: `sudo usermod -aG spi $USER && logout`

### GPIO export error ("Device or resource busy")

```bash
echo 23 > /sys/class/gpio/unexport
echo 18 > /sys/class/gpio/unexport
echo 22 > /sys/class/gpio/unexport
sudo systemctl restart lorawan-gateway
```

### GPS UART garbage / no data

- Disable serial console: `sudo raspi-config` → Interface Options → Serial Port → No login shell → Yes hardware
- Remove `console=serial0,115200` from `/boot/cmdline.txt`
- Reboot

### Service crashes immediately

```bash
sudo journalctl -u lorawan-gateway -n 50
```

Common causes:
- HAT not properly seated on GPIO header
- No LoRa antenna connected (RF damage risk!)
- SPI not enabled (reboot needed after config.txt edit)
- Wrong SPI device path in `global_conf.json`

### No packets in TTN Console after gateway connected

- Ensure LoRa antenna is connected
- Verify end device is configured for EU868
- Check gateway EUI matches TTN registration
- Confirm frequency plan = `Europe 863-870 MHz`
- Try moving the end device closer to the gateway

### Build fails (sx1302_hal)

```bash
# Install missing dependencies
sudo apt-get install -y gcc make libusb-1.0-0-dev pkg-config git

# Retry build
cd /tmp/lr1302_build && make clean && make
```

---

## Reference Links

- [Elecrow LR1302 Product Page](https://www.elecrow.com/lr1302-lorawan-gateway-module-spi-868m.html)
- [Elecrow LR1302 Wiki](https://www.elecrow.com/wiki/index.php?title=LR1302_LoRaWAN_Gateway_Module)
- [Elecrow sx1302_hal GitHub](https://github.com/Elecrow-RD/LR1302_loraWAN)
- [Semtech sx1302_hal Upstream](https://github.com/Lora-net/sx1302_hal)
- [TTN Console](https://console.cloud.thethings.network/)
- [TTN Gateway Registration Docs](https://www.thethingsindustries.com/docs/gateways/adding-gateways/)
- [EU868 Frequency Plan](https://www.thethingsnetwork.org/docs/lorawan/frequency-plans/)
- [Raspberry Pi GPIO Pinout](https://pinout.xyz/)
