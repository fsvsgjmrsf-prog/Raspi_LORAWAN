# Elecrow LR1302 LoRaWAN Gateway — Installation Guide

**Complete step-by-step installation guide for a production-ready LoRaWAN gateway**
using the Elecrow LR1302 HAT on a Raspberry Pi 3B/B+, connected to The Things Network (TTN)
via the EU868 frequency plan.

By the end of this guide you will have:
- A running `lora_pkt_fwd` UDP packet forwarder, managed as a systemd service
- A gateway registered on TTN Console and receiving uplinks from nearby LoRaWAN devices
- Persistent operation with automatic restart on failure

**Estimated time:** ~30 minutes active work + ~10–15 minutes for the sx1302_hal build

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

## Quick Navigation

| Section | Topic |
|---------|-------|
| [2. Hardware Prerequisites](#2-hardware-prerequisites) | BOM, GPIO map, antenna warning |
| [3. OS Preparation](#3-os-preparation) | Flash, SSH, enable SPI/I2C/UART |
| [4. Repository Setup](#4-repository-setup) | Clone or transfer repo to Pi |
| [5. Running setup.sh](#5-running-setupsh) | One-command installer walkthrough |
| [6. Gateway Configuration](#6-gateway-configuration) | EUI generation, TTN server, local_conf.json |
| [7. Systemd Service](#7-systemd-service) | Service file, lifecycle commands |
| [8. GPIO Reset Script](#8-gpio-reset-script) | Power sequencing, manual usage |
| [9. TTN Console Registration](#9-ttn-console-registration) | Register gateway in TTN |
| [10. Post-Install Verification](#10-post-installation-verification) | Checklists, log analysis |
| [11. Maintenance](#11-maintenance) | Reconfigure, update binary, log mgmt |
| [12. Troubleshooting](#12-troubleshooting) | Common failures, fixes |
| [13. Reference](#13-reference) | File table, external links |

---

## 2. Hardware Prerequisites

### 2.1 Bill of Materials

| Component | Specification | Required? |
|-----------|---------------|-----------|
| Single-board computer | Raspberry Pi 3B, 3B+, 4B, or Zero 2W | **Yes** |
| LoRaWAN HAT | Elecrow LR1302 (SX1302 + SX1250, EU868 variant) | **Yes** |
| LoRa antenna | SMA female, 868 MHz, 2–3 dBi | **REQUIRED** |
| Power supply | 5V / 2.5A minimum (3A recommended) | **Yes** |
| microSD card | 8 GB minimum, Class 10 or better | **Yes** |
| Network cable | Ethernet (recommended) or WiFi | **Yes** |
| GPS antenna | Active SMA, 3.3V bias-T | Optional |

> **CRITICAL: Never power on the LR1302 HAT without a LoRa antenna connected to the ANT port.
> Operating without an antenna can permanently damage the SX1250 RF front-end.**

### 2.2 GPIO / HAT Connection Diagram

The LR1302 HAT uses the full 40-pin Raspberry Pi GPIO header:

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

### 2.3 Signal Reference Table

| Signal | BCM GPIO | Physical Pin | Direction | Notes |
|--------|----------|-------------|-----------|-------|
| **SX1302 Reset** | GPIO23 | Pin 16 | Output | Active-low pulse to reset SX1302 |
| **Power Enable** | GPIO18 | Pin 12 | Output | Pull HIGH to power on module |
| **SX1261 Reset** | GPIO22 | Pin 15 | Output | LBT radio reset (optional) |
| **SPI0 MOSI** | GPIO10 | Pin 19 | Output | SPI bus to SX1302 |
| **SPI0 MISO** | GPIO9 | Pin 21 | Input | SPI bus from SX1302 |
| **SPI0 CLK** | GPIO11 | Pin 23 | Output | SPI clock |
| **SPI0 CE0** | GPIO8 | Pin 24 | Output | Chip select → `/dev/spidev0.0` |
| **UART TX** | GPIO14 | Pin 8 | Output | Pi TX → GPS RX |
| **UART RX** | GPIO15 | Pin 10 | Input | GPS TX → Pi RX |
| **I2C SDA** | GPIO2 | Pin 3 | Bi-dir | DS3231 RTC @ I2C 0x68 |
| **I2C SCL** | GPIO3 | Pin 5 | Output | I2C clock |

### 2.4 Antenna Warning

> **WARNING — RF Damage Risk**
>
> Always connect a LoRa SMA antenna to the `ANT` port **before** powering on.
> Transmitting into an open-circuit antenna port creates reflected power that can
> permanently destroy the SX1250 RF front-end. This damage is not covered under warranty.
>
> A 2–3 dBi 868 MHz stub antenna is sufficient. Avoid cheap WiFi antennas — they are
> tuned for 2.4 GHz, not 868 MHz.

### 2.5 Power Requirements

| Component | Voltage | Current (typical) |
|-----------|---------|-------------------|
| Raspberry Pi 3B | 5V | 500–700 mA |
| LR1302 HAT (idle) | 5V | ~150 mA |
| LR1302 HAT (TX peak) | 5V | ~400 mA |
| GPS module | 3.3V (from Pi) | ~25 mA |
| **Total** | **5V** | **~1.0–1.5 A** |

Use the official Raspberry Pi power supply (5V/2.5A) or equivalent. Insufficient power
is a common cause of SPI communication errors and random gateway crashes.

### 2.6 Jumper Settings

| Jumper | Default State | Purpose |
|--------|---------------|---------|
| J1 (GPS enable) | Bridged | Connects GPS UART to GPIO14/GPIO15 |
| J2 (LBT enable) | Open | Enables SX1261 LBT — bridge only if needed |
| ANT1 | Required | LoRa SMA antenna (must be connected!) |
| ANT2 (GPS) | Recommended | Active GPS antenna (3.3V bias) |

No jumper changes are needed for standard EU868 SPI operation.

---

## 3. OS Preparation

### 3.1 Flash Raspberry Pi OS

**Required:** Raspberry Pi OS Lite (Bullseye or Bookworm). The full desktop image works
but wastes resources on a headless gateway.

1. Download [Raspberry Pi Imager](https://www.raspberrypi.com/software/)
2. Select **Raspberry Pi OS Lite (32-bit)** — the 64-bit version is also supported
3. Click the gear icon (⚙) to configure:
   - Set hostname (e.g. `lorawan-gw`)
   - Enable SSH with password or public key
   - Set username and password
   - Configure WiFi if not using Ethernet
4. Flash to your microSD card
5. Insert card into Pi, connect Ethernet, power on

### 3.2 First Boot Checklist

Before running the installer, verify:

- [ ] Pi boots without kernel panics (solid green LED activity)
- [ ] SSH access works: `ssh pi@<ip-address>`
- [ ] Internet is reachable: `ping -c 3 8.8.8.8`
- [ ] System is up to date: `sudo apt-get update && sudo apt-get upgrade -y`

### 3.3 Enable SPI / I2C / UART

> **Note:** `setup.sh` performs this step automatically. Only do this manually if you
> are not using the installer.

Edit the boot configuration file. On **Raspberry Pi 3B/B+**:

```bash
sudo nano /boot/config.txt
```

On **Raspberry Pi 4B or later** (Bookworm):

```bash
sudo nano /boot/firmware/config.txt
```

Add these lines at the end of the file:

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

Save and exit (`Ctrl+O`, `Enter`, `Ctrl+X`). A reboot is required for these changes
to take effect.

### 3.4 Disable Serial Console (for GPS)

The GPS module communicates via the Pi's UART. By default, Raspberry Pi OS uses this
same UART for a serial login console, which conflicts with GPS data. Disable the
serial console:

**Via raspi-config (recommended):**

```bash
sudo raspi-config
```

Navigate: `Interface Options` → `Serial Port`
- "Would you like a login shell to be accessible over the serial port?" → **No**
- "Would you like the serial port hardware to be enabled?" → **Yes**

**Via cmdline.txt (manual alternative):**

```bash
sudo nano /boot/cmdline.txt
```

Remove the string `console=serial0,115200` from the line (keep everything else).
The line should remain a single line.

### 3.5 Verify Interfaces (after reboot)

After rebooting, verify the interfaces are available:

```bash
# SPI device (requires spi=on and reboot)
ls /dev/spidev0.*
# Expected: /dev/spidev0.0  /dev/spidev0.1

# I2C — DS3231 RTC should appear at address 0x68
sudo i2cdetect -y 1
# Expected: '68' visible in the grid

# Kernel modules
lsmod | grep spi_bcm
# Expected: spi_bcm2835 or spi_bcm2708 listed

# dmesg for SPI init
dmesg | grep -i spi
```

---

## 4. Repository Setup

### 4.1 Clone via Git (recommended)

On the Raspberry Pi:

```bash
git clone https://github.com/<your-repo>/IOT_Gateway.git ~/IOT_Gateway
cd ~/IOT_Gateway
```

### 4.2 Transfer via SCP (alternative)

From your workstation (if the repo is local):

```bash
scp -r ./IOT_Gateway pi@<pi-ip-address>:~/IOT_Gateway
```

Then SSH into the Pi:

```bash
ssh pi@<pi-ip-address>
cd ~/IOT_Gateway
```

### 4.3 Repository Structure

```
IOT_Gateway/
├── CLAUDE.md                          ← Project instructions and architecture
├── INSTALLATION_GUIDE.md              ← This file
├── .gitignore                         ← Standard ignores (local_conf.json excluded)
│
├── scripts/
│   ├── setup.sh                       ← One-shot installer (run as root)
│   ├── configure_gateway.sh           ← Interactive EUI + TTN configuration
│   └── reset_lgw.sh                   ← GPIO power/reset sequencer
│
├── config/
│   ├── global_conf.json               ← EU868 radio configuration (8 channels)
│   └── local_conf.json.template       ← Template for EUI and server overrides
│
├── systemd/
│   └── lorawan-gateway.service        ← Systemd unit file
│
└── hardware/
    └── elecrow-lr1302-pinout.md       ← GPIO map, signal table, jumpers
```

### 4.4 Make Scripts Executable

```bash
chmod +x ~/IOT_Gateway/scripts/*.sh
```

---

## 5. Running setup.sh

### 5.0 Invocation

```bash
cd ~/IOT_Gateway
sudo bash scripts/setup.sh
```

The script must run as root (`sudo`). It uses `set -euo pipefail`, so any command
failure halts the installer immediately. The colored output uses `[INFO]` (cyan),
`[OK]` (green), `[WARN]` (yellow), and `[ERROR]` (red) prefixes.

**Overview of what setup.sh does:**
1. Pre-flight checks (root, model, OS, boot config path)
2. Install system dependencies
3. Configure `/boot/config.txt` (SPI, I2C, UART)
4. Clone and build Elecrow sx1302_hal fork
5. Install binaries and configs
6. Install systemd service
7. Run interactive gateway configuration
8. Print post-install summary

### 5.1 Step 0 — Pre-flight Checks

The script verifies:

- **Running as root** — exits if `$EUID != 0`
- **Linux OS** — checks `uname -s`
- **Raspberry Pi model** — reads `/proc/device-tree/model` and prints the model string
  (e.g. `Raspberry Pi 3 Model B Plus Rev 1.3`); warns but does not exit if not a Pi
- **OS version** — sources `/etc/os-release` and prints `$PRETTY_NAME`
- **Boot config path** — auto-detects:
  - `/boot/firmware/config.txt` (Raspberry Pi 4+ with Bookworm)
  - `/boot/config.txt` (Raspberry Pi 3, Bullseye)
  - Dies if neither is found

Example output:
```
-----------------------------------------------------------
  Step 0: Pre-flight checks
-----------------------------------------------------------
[OK]    Running as root
[OK]    OS: Linux
[INFO]  Detected: Raspberry Pi 3 Model B Plus Rev 1.3
[INFO]  OS: Debian GNU/Linux 11 (bullseye)
[INFO]  Boot config: /boot/config.txt
[OK]    Pre-flight checks passed
```

### 5.2 Step 1 — Install Dependencies

```
-----------------------------------------------------------
  Step 1: Installing system dependencies
-----------------------------------------------------------
```

Packages installed via `apt-get install -y`:

| Package | Purpose |
|---------|---------|
| `git` | Clone Elecrow sx1302_hal repository |
| `gcc` | Compile C source code |
| `make` | Build system for sx1302_hal |
| `libusb-1.0-0-dev` | USB library (required by sx1302_hal Makefile) |
| `pkg-config` | Library path resolution during build |
| `python3` | Patch `gateway_ID` in JSON config files |
| `i2c-tools` | `i2cdetect` for RTC verification |
| `raspi-config` | Serial console configuration |

### 5.3 Step 2 — Configure Boot Parameters

```
-----------------------------------------------------------
  Step 2: Configuring boot parameters (SPI, I2C, UART)
-----------------------------------------------------------
```

The script:
1. **Creates a timestamped backup** of config.txt: `config.txt.bak.YYYYMMDD_HHMMSS`
2. Idempotently adds four lines (skips any line already present):
   - `dtparam=spi=on`
   - `dtparam=i2c_arm=on`
   - `enable_uart=1`
   - `dtoverlay=disable-bt`
3. Issues a `[WARN]` that a reboot is required (but continues without rebooting)

The installer does **not** reboot mid-run. The service cannot start until you reboot
(see Section 5.8).

### 5.4 Step 3 — Build sx1302_hal

```
-----------------------------------------------------------
  Step 3: Building sx1302_hal (Elecrow fork)
-----------------------------------------------------------
```

Build steps:
1. Remove any previous build at `/tmp/lr1302_build`
2. `git clone --depth 1 https://github.com/Elecrow-RD/LR1302_loraWAN.git /tmp/lr1302_build`
3. `cd /tmp/lr1302_build && make -j$(nproc)`

**Build time:** ~10–15 minutes on Raspberry Pi 3B at default clock speed.
The `-j$(nproc)` flag parallelizes across all available CPU cores (4 on Pi 3).

If the build fails, see Section 12.7 — Build fails.

### 5.5 Step 4 — Install Files

```
-----------------------------------------------------------
  Step 4: Installing files
-----------------------------------------------------------
```

Files installed:

| Source | Destination |
|--------|-------------|
| `/tmp/lr1302_build/packet_forwarder/lora_pkt_fwd` | `/opt/lorawan-gateway/lora_pkt_fwd` |
| `scripts/reset_lgw.sh` | `/opt/lorawan-gateway/reset_lgw.sh` |
| `config/local_conf.json.template` | `/opt/lorawan-gateway/local_conf.json.template` |
| `config/global_conf.json` | `/etc/lorawan-gateway/global_conf.json` |

Both `/opt/lorawan-gateway/` and `/etc/lorawan-gateway/` directories are created
if they do not exist. The `lora_pkt_fwd` binary is made executable with `chmod +x`.

The `global_conf.json` is only copied if `/etc/lorawan-gateway/global_conf.json`
does not already exist (preserves manual edits on reinstall).

### 5.6 Step 5 — Install Systemd Service

```
-----------------------------------------------------------
  Step 5: Installing systemd service
-----------------------------------------------------------
```

1. Copies `systemd/lorawan-gateway.service` to `/etc/systemd/system/`
2. Runs `systemctl daemon-reload`
3. Runs `systemctl enable lorawan-gateway`

The service is **enabled** (auto-starts on boot) but **not started** yet.
It cannot start until after the required reboot (SPI is not yet active).

### 5.7 Step 6 — Gateway Configuration

```
-----------------------------------------------------------
  Step 6: Gateway EUI + TTN configuration
-----------------------------------------------------------
```

This step calls `configure_gateway.sh` interactively.
See Section 6 for a full walkthrough of this step.

### 5.8 Step 7 — Summary and Reboot

After configuration, the installer prints a summary of all installed files and
service management commands, then reminds you to reboot:

```
  IMPORTANT: Reboot required for SPI/I2C/UART to be active!
    sudo reboot
```

**Reboot now:**

```bash
sudo reboot
```

After reboot, the `lorawan-gateway` service starts automatically. Monitor it with:

```bash
sudo journalctl -u lorawan-gateway -f
```

### 5.9 Error Handling

`setup.sh` uses `set -euo pipefail`:
- `-e` — exits immediately on any command failure
- `-u` — treats unset variables as errors
- `-o pipefail` — catches failures in piped commands

If the installer stops unexpectedly, the last `[ERROR]` line explains the cause.
Common failures are covered in Section 12.

---

## 6. Gateway Configuration

### 6.1 What configure_gateway.sh Does

The script performs three steps:
1. **Auto-generate a Gateway EUI** from the Ethernet MAC address (FFFE insertion)
2. **Prompt for TTN region** selection
3. **Write `/etc/lorawan-gateway/local_conf.json`** and patch `global_conf.json`

Run standalone at any time to reconfigure:

```bash
sudo bash ~/IOT_Gateway/scripts/configure_gateway.sh
```

### 6.2 EUI-64 from MAC Address (FFFE Insertion)

The Gateway EUI is a 64-bit identifier derived from the Ethernet MAC address using
the IEEE EUI-64 method:

1. Take the 48-bit MAC address: `B8:27:EB:12:34:56`
2. Split into upper (OUI) and lower halves: `B827EB` | `123456`
3. Insert `FFFE` between the halves: `B827EB` + `FFFE` + `123456`
4. Result (uppercase, no separators): `B827EBFFFE123456`

The script tries these interfaces in order: `eth0`, `end0`, `enp0s3`, `ens3`, `eth1`.
If none are found, it falls back to the first non-loopback, non-WiFi interface.

**Example output:**

```
[INFO]  Auto-generated EUI from MAC address: B827EBFFFE123456

Use this EUI? [Y/n]: Y
[OK]    Gateway EUI: B827EBFFFE123456
```

### 6.3 Interactive Session Walkthrough

```
===========================================================
  LoRaWAN Gateway — TTN Configuration
===========================================================

Step 1: Gateway EUI

[INFO]  Auto-generated EUI from MAC address: B827EBFFFE123456

Use this EUI? [Y/n]: Y              ← Press Enter to accept
[OK]    Gateway EUI: B827EBFFFE123456

Step 2: TTN Region / Cluster

  eu1  — Europe        (eu1.cloud.thethings.network)
  nam1 — North America (nam1.cloud.thethings.network)
  au1  — Australia     (au1.cloud.thethings.network)
  as1  — Asia          (as1.cloud.thethings.network)
  in1  — India         (in1.cloud.thethings.network)

Select region [eu1/nam1/au1/as1/in1] (default: eu1): eu1    ← Press Enter for eu1
[OK]    Server: eu1.cloud.thethings.network

Step 3: Writing configuration
[OK]    Written: /etc/lorawan-gateway/local_conf.json
[OK]    Updated gateway_ID in global_conf.json
```

### 6.4 Output: local_conf.json

The script writes `/etc/lorawan-gateway/local_conf.json` with your EUI and server:

```json
{
    "gateway_conf": {
        "gateway_ID": "B827EBFFFE123456",
        "server_address": "eu1.cloud.thethings.network",
        "serv_port_up": 1700,
        "serv_port_down": 1700
    }
}
```

This file **overrides** matching keys in `global_conf.json`. The packet forwarder
merges both files at startup; `local_conf.json` takes precedence.

### 6.5 global_conf.json Patching

After writing `local_conf.json`, the script uses Python3 to patch `global_conf.json`:

```python
import json
with open('/etc/lorawan-gateway/global_conf.json', 'r') as f:
    cfg = json.load(f)
cfg.setdefault('gateway_conf', {})['gateway_ID'] = 'B827EBFFFE123456'
# Also updates server_address in the servers[] array
for s in cfg.get('gateway_conf', {}).get('servers', []):
    s['gateway_ID'] = 'B827EBFFFE123456'
    s['server_address'] = 'eu1.cloud.thethings.network'
with open('/etc/lorawan-gateway/global_conf.json', 'w') as f:
    json.dump(cfg, f, indent=4)
```

If `python3` is not available, a warning is printed and you must edit `global_conf.json`
manually.

### 6.6 Manual Alternative

If you prefer not to use the interactive script:

```bash
# 1. Copy the template
sudo cp /opt/lorawan-gateway/local_conf.json.template \
        /etc/lorawan-gateway/local_conf.json

# 2. Edit it
sudo nano /etc/lorawan-gateway/local_conf.json
```

Replace `GATEWAY_EUI_HERE` with your 16-character hex EUI and set `server_address`
to your TTN cluster server.

### 6.7 EUI Validation

The script validates EUI with a bash regex:

```bash
[[ "${eui}" =~ ^[0-9A-Fa-f]{16}$ ]]
```

Rules:
- Exactly 16 hexadecimal characters
- No colons, dashes, or spaces
- Case-insensitive (script normalizes to uppercase)

Invalid examples: `B8:27:EB:FF:FE:12:34:56` (has colons), `B827EB123456` (only 12 chars)

### 6.8 TTN Server Map

| Region code | Server address | Coverage |
|-------------|---------------|----------|
| `eu1` | `eu1.cloud.thethings.network` | Europe |
| `nam1` | `nam1.cloud.thethings.network` | North America |
| `au1` | `au1.cloud.thethings.network` | Australia |
| `as1` | `as1.cloud.thethings.network` | Asia |
| `in1` | `in1.cloud.thethings.network` | India |

All servers use UDP port 1700 for both uplink and downlink.

---

## 7. Systemd Service

### 7.1 Service File Annotated

`/etc/systemd/system/lorawan-gateway.service`:

```ini
[Unit]
Description=LoRaWAN UDP Packet Forwarder (Elecrow LR1302)
After=network-online.target          # Wait for full network connectivity
Wants=network-online.target          # Express soft dependency on network

[Service]
Type=simple                          # Process stays in foreground
User=root                            # Required: SPI and GPIO need root access
WorkingDirectory=/etc/lorawan-gateway # CWD for config file resolution

# Power on and release reset before starting
ExecStartPre=/opt/lorawan-gateway/reset_lgw.sh start

# Start the UDP packet forwarder with explicit config path
ExecStart=/opt/lorawan-gateway/lora_pkt_fwd -c /etc/lorawan-gateway/global_conf.json

# Assert reset and cut power after stopping
ExecStopPost=/opt/lorawan-gateway/reset_lgw.sh stop

# Restart on failure, wait 10 seconds between attempts
Restart=on-failure
RestartSec=10

# Allow up to 5 restart attempts per 120-second window
StartLimitInterval=120
StartLimitBurst=5

# Send all output to systemd journal
StandardOutput=journal
StandardError=journal
SyslogIdentifier=lorawan-gateway

[Install]
WantedBy=multi-user.target
```

**Key design decisions:**
- `After=network-online.target` — prevents startup race where DNS is not yet available
- `ExecStartPre` runs `reset_lgw.sh start` to power-cycle the HAT before every start
- `ExecStopPost` runs `reset_lgw.sh stop` to cut power cleanly on stop/crash
- `Restart=on-failure` + `StartLimitBurst=5` — automatic recovery with a hard cap to
  prevent rapid restart loops that could indicate a deeper hardware failure

### 7.2 Manual Installation (without setup.sh)

If you are not using the installer:

```bash
# Copy the unit file
sudo cp ~/IOT_Gateway/systemd/lorawan-gateway.service \
        /etc/systemd/system/lorawan-gateway.service

# Reload systemd
sudo systemctl daemon-reload

# Enable auto-start on boot
sudo systemctl enable lorawan-gateway

# Start immediately
sudo systemctl start lorawan-gateway
```

### 7.3 Service Lifecycle Commands

| Action | Command |
|--------|---------|
| Start the gateway | `sudo systemctl start lorawan-gateway` |
| Stop the gateway | `sudo systemctl stop lorawan-gateway` |
| Restart (after config change) | `sudo systemctl restart lorawan-gateway` |
| Enable auto-start on boot | `sudo systemctl enable lorawan-gateway` |
| Disable auto-start | `sudo systemctl disable lorawan-gateway` |
| Check current status | `sudo systemctl status lorawan-gateway` |
| View all logs | `sudo journalctl -u lorawan-gateway` |
| View logs since last boot | `sudo journalctl -u lorawan-gateway -b` |
| Follow live logs | `sudo journalctl -u lorawan-gateway -f` |
| View logs since today | `sudo journalctl -u lorawan-gateway --since today` |
| Reset failed restart counter | `sudo systemctl reset-failed lorawan-gateway` |

### 7.4 Configuration Override Mechanism

The packet forwarder is started with:

```
lora_pkt_fwd -c /etc/lorawan-gateway/global_conf.json
```

At startup, `lora_pkt_fwd` also looks for `local_conf.json` in its working directory
(`/etc/lorawan-gateway/`). Settings in `local_conf.json` override matching keys in
`global_conf.json`. This means:

- `global_conf.json` — radio configuration, channel plan, RF parameters (rarely changes)
- `local_conf.json` — gateway identity and server (changes per deployment)

To change the server or EUI, only `local_conf.json` needs to be updated.

---

## 8. GPIO Reset Script

### 8.1 Purpose and Interface

`reset_lgw.sh` controls the LR1302 HAT power and reset lines via the Linux sysfs GPIO
interface (`/sys/class/gpio/`). It does not use libgpiod or WiringPi, making it
compatible with all Raspberry Pi OS versions without additional dependencies.

GPIO assignments:
- **GPIO18** (Pin 12) — Power Enable (active high)
- **GPIO23** (Pin 16) — SX1302 Reset (active low pulse)
- **GPIO22** (Pin 15) — SX1261 Reset (active low pulse, LBT radio)

Usage:
```bash
sudo /opt/lorawan-gateway/reset_lgw.sh start   # Power on + release reset
sudo /opt/lorawan-gateway/reset_lgw.sh stop    # Assert reset + power off
```

### 8.2 Start Sequence (Annotated)

```bash
# 1. Export GPIO pins to userspace sysfs
echo 18 > /sys/class/gpio/export    # Power Enable
echo 23 > /sys/class/gpio/export    # SX1302 Reset
echo 22 > /sys/class/gpio/export    # SX1261 Reset

# 2. Set all to output direction
echo out > /sys/class/gpio/gpio18/direction
echo out > /sys/class/gpio/gpio23/direction
echo out > /sys/class/gpio/gpio22/direction

# 3. Assert resets LOW (hold chips in reset)
echo 0 > /sys/class/gpio/gpio23/value   # SX1302 RST LOW
echo 0 > /sys/class/gpio/gpio22/value   # SX1261 RST LOW
sleep 0.1

# 4. Enable power (GPIO18 HIGH)
echo 1 > /sys/class/gpio/gpio18/value
sleep 0.1

# 5. Release SX1302 from reset (GPIO23 HIGH)
echo 1 > /sys/class/gpio/gpio23/value
sleep 0.1

# 6. Release SX1261 from reset (GPIO22 HIGH)
echo 1 > /sys/class/gpio/gpio22/value
sleep 0.05
```

The 100 ms delays allow the SX1302 power rails to stabilize before releasing reset.

### 8.3 Stop Sequence (Annotated)

```bash
# 1. Assert resets LOW (chip back in reset)
echo 0 > /sys/class/gpio/gpio23/value
echo 0 > /sys/class/gpio/gpio22/value
sleep 0.05

# 2. Cut power (GPIO18 LOW)
echo 0 > /sys/class/gpio/gpio18/value

# 3. Unexport GPIOs (release sysfs resources)
echo 23 > /sys/class/gpio/unexport
echo 22 > /sys/class/gpio/unexport
echo 18 > /sys/class/gpio/unexport
```

The stop sequence resets before cutting power to prevent SX1302 from entering an
undefined state, which could cause "SPI device busy" errors on the next start.

### 8.4 Manual Usage

The script is normally called automatically by systemd (`ExecStartPre`/`ExecStopPost`).
You can also call it manually:

```bash
# Power on the HAT manually
sudo /opt/lorawan-gateway/reset_lgw.sh start

# Power off the HAT manually
sudo /opt/lorawan-gateway/reset_lgw.sh stop

# Or from the project directory during development
sudo bash ~/IOT_Gateway/scripts/reset_lgw.sh start
```

### 8.5 When to Call Manually

- **GPIO "Device or resource busy" error** — GPIOs were not unexported after a crash.
  Run `stop` first, then clear any stuck exports, then run `start`.
- **Manual power-cycle for debugging** — stop the service, run `stop`, wait 2 seconds,
  run `start`, then start the service.
- **Testing the HAT** — verify the HAT powers on and SPI is accessible before starting
  the full service.

---

## 9. TTN Console Registration

### 9.1 Prerequisites

Before registering:
- [ ] TTN account created at [console.cloud.thethings.network](https://console.cloud.thethings.network/)
- [ ] Gateway EUI known (from `configure_gateway.sh` output or step below)
- [ ] Gateway is connected to the internet

**Find your Gateway EUI at any time:**

```bash
sudo cat /etc/lorawan-gateway/local_conf.json | grep gateway_ID
# Output: "gateway_ID": "B827EBFFFE123456",
```

Or from the global config:

```bash
sudo python3 -c "
import json
with open('/etc/lorawan-gateway/global_conf.json') as f:
    c = json.load(f)
print(c['gateway_conf']['gateway_ID'])
"
```

### 9.2 Registration Step-by-Step

1. Go to [console.cloud.thethings.network](https://console.cloud.thethings.network/)
2. Select the **eu1** cluster (top-right cluster selector — match your region)
3. In the left sidebar, click **Gateways**
4. Click **+ Register gateway**
5. Fill in the form:
   - **Gateway EUI**: paste your 16-character EUI (e.g. `B827EBFFFE123456`)
   - **Gateway ID**: a unique lowercase string (e.g. `my-rpi-lorawan-gw`)
     — used in API calls, can differ from EUI, must be globally unique
   - **Gateway name**: human-readable label (optional)
   - **Frequency plan**: select `Europe 863-870 MHz (SF9 for RX2 — recommended)`
6. Click **Register gateway**

### 9.3 Frequency Plan Selection

For EU868, select exactly:
```
Europe 863-870 MHz (SF9 for RX2 — recommended)
```

This matches the 8 channels configured in `global_conf.json`:
- 8 multi-SF channels (SF7–SF12) centered on radio_0 @ 867.5 MHz and radio_1 @ 868.5 MHz
- 1 LoRa standard channel (250 kHz, SF7) on radio_1
- 1 FSK channel (125 kHz, 50 kbps) on radio_1

### 9.4 Expected TTN Events

After the gateway connects, the TTN Console → your gateway → **Live data** tab shows:

| Event | Meaning |
|-------|---------|
| `gs.gateway.connect` | Gateway successfully authenticated with TTN |
| `gs.up.receive` | Gateway received an uplink from a LoRaWAN device |
| `gs.down.send` | TTN sent a downlink to the gateway |
| `gs.gateway.disconnect` | Gateway disconnected (network loss, restart) |

A `gs.gateway.connect` event should appear within 30–60 seconds of starting the service.

---

## 10. Post-Installation Verification

### 10.1 Ordered Verification Checklist

Work through these in order — each step depends on the previous:

- [ ] **SPI device exists**: `ls /dev/spidev0.0`
- [ ] **Service is active**: `sudo systemctl status lorawan-gateway` shows `active (running)`
- [ ] **No errors in logs**: `sudo journalctl -u lorawan-gateway -b` — no `[ERROR]` lines
- [ ] **Concentrator started**: logs show `concentrator started, packet can now be received`
- [ ] **PUSH_ACK received**: logs show `PUSH_ACK received in X ms` from TTN server
- [ ] **GPIO exported**: `ls /sys/class/gpio/` shows `gpio18`, `gpio22`, `gpio23`
- [ ] **TTN connected**: TTN Console shows `gs.gateway.connect` event
- [ ] **Uplinks received**: bring a LoRaWAN device nearby and verify `gs.up.receive` events

### 10.2 Healthy Log Output

```bash
sudo journalctl -u lorawan-gateway -f
```

Expected healthy output (annotated):

```
Feb 26 10:30:01 lorawan-gw systemd[1]: Starting LoRaWAN UDP Packet Forwarder...
Feb 26 10:30:01 lorawan-gw reset_lgw[1234]: [reset_lgw] Exporting GPIOs...
Feb 26 10:30:01 lorawan-gw reset_lgw[1234]: [reset_lgw] Enabling power (GPIO18 HIGH)...
Feb 26 10:30:01 lorawan-gw reset_lgw[1234]: [reset_lgw] Releasing SX1302 reset (GPIO23 HIGH)...
Feb 26 10:30:01 lorawan-gw reset_lgw[1234]: [reset_lgw] Gateway powered on and reset released.
Feb 26 10:30:02 lorawan-gw lorawan-gateway[1235]: [INFO] concentrator started, packet can now be received
Feb 26 10:30:02 lorawan-gw lorawan-gateway[1235]: [INFO] host: lorawan-gw, IP: 192.168.1.x
Feb 26 10:30:12 lorawan-gw lorawan-gateway[1235]: [INFO] PUSH_ACK received in 12 ms
Feb 26 10:30:42 lorawan-gw lorawan-gateway[1235]: [INFO] # RF packets received by concentrator: 0
Feb 26 10:30:42 lorawan-gw lorawan-gateway[1235]: [INFO] # TX requests    0   # TX rejected    0
Feb 26 10:30:42 lorawan-gw lorawan-gateway[1235]: [INFO] PUSH_ACK received in 11 ms
```

Key indicators of healthy operation:
- `concentrator started` — SPI communication with SX1302 is working
- `PUSH_ACK received in X ms` — TTN server is reachable and responding
- Statistics lines print every 30 seconds (configurable via `stat_interval`)

### 10.3 SPI Verification

```bash
# SPI character devices
ls -la /dev/spidev0.*
# Expected: crw-rw---- ... spidev0.0   crw-rw---- ... spidev0.1

# Kernel module
lsmod | grep spi_bcm
# Expected: spi_bcm2835        or  spi_bcm2708

# dmesg for SPI probe
dmesg | grep -i spi
# Expected lines including: spi_master spi0: ..., spi0.0: ...
```

### 10.4 GPIO State During Operation

While the service is running, the GPIO exports should be visible:

```bash
ls /sys/class/gpio/
# Should include: gpio18  gpio22  gpio23

# Power Enable should be HIGH (1) while running
cat /sys/class/gpio/gpio18/value
# Expected: 1

# SX1302 Reset should be HIGH (released) while running
cat /sys/class/gpio/gpio23/value
# Expected: 1

# SX1261 Reset should be HIGH (released) while running
cat /sys/class/gpio/gpio22/value
# Expected: 1
```

After stopping the service, all three GPIOs are unexported (the directories disappear).

### 10.5 GPS UART Check (Optional)

If you connected a GPS antenna:

```bash
# Set baud rate
sudo stty -F /dev/ttyS0 9600

# Capture 10 seconds of UART data
sudo timeout 10 cat /dev/ttyS0
```

You should see NMEA sentences:
```
$GPGGA,102030.00,4012.12345,N,00345.12345,W,1,08,1.2,50.0,M,...
$GPRMC,102030.00,A,4012.12345,N,00345.12345,W,...
$GPGSV,...
```

If you see garbage characters, the serial console is still active. See Section 12.4.

---

## 11. Maintenance

### 11.1 Reconfigure (Change EUI or TTN Server)

To change the Gateway EUI or TTN cluster:

```bash
sudo bash ~/IOT_Gateway/scripts/configure_gateway.sh
sudo systemctl restart lorawan-gateway
```

The script rewrites `/etc/lorawan-gateway/local_conf.json` and patches `global_conf.json`.
Update the TTN Console registration if you change the EUI.

### 11.2 Update the sx1302_hal Binary

When Elecrow releases an updated firmware:

```bash
# Stop the service
sudo systemctl stop lorawan-gateway

# Remove old build
sudo rm -rf /tmp/lr1302_build

# Clone and build fresh
git clone --depth 1 https://github.com/Elecrow-RD/LR1302_loraWAN.git /tmp/lr1302_build
cd /tmp/lr1302_build && make -j$(nproc)

# Install updated binary
sudo cp /tmp/lr1302_build/packet_forwarder/lora_pkt_fwd /opt/lorawan-gateway/lora_pkt_fwd
sudo chmod +x /opt/lorawan-gateway/lora_pkt_fwd

# Start service
sudo systemctl start lorawan-gateway
sudo journalctl -u lorawan-gateway -f
```

### 11.3 Log Management

```bash
# View all logs for this unit
sudo journalctl -u lorawan-gateway

# Logs since last boot
sudo journalctl -u lorawan-gateway -b

# Logs since a specific time
sudo journalctl -u lorawan-gateway --since "2026-02-26 10:00:00"

# Last 100 lines
sudo journalctl -u lorawan-gateway -n 100

# Follow live
sudo journalctl -u lorawan-gateway -f
```

### 11.4 Monitoring PUSH_ACK Health

Count successful PUSH_ACK responses in the last hour to verify TTN connectivity:

```bash
sudo journalctl -u lorawan-gateway --since "1 hour ago" | grep -c "PUSH_ACK"
```

A healthy gateway sends a STAT packet every 30 seconds (`stat_interval` in global_conf.json),
so you expect approximately 120 PUSH_ACK responses per hour.

Check the service runtime state:

```bash
sudo systemctl show lorawan-gateway --property=ActiveState,SubState,ExecMainPID,NRestarts
# Healthy: ActiveState=active, SubState=running, NRestarts=0
```

A non-zero `NRestarts` indicates the service has crashed and recovered automatically.
Investigate with `sudo journalctl -u lorawan-gateway -b` for crash context.

---

## 12. Troubleshooting

### Quick Reference Table

| Symptom | Likely Cause | Quick Fix |
|---------|-------------|-----------|
| `failed to open SPI device /dev/spidev0.0` | SPI not enabled or no reboot | Add `dtparam=spi=on` to config.txt, reboot |
| `/dev/spidev0.0: Permission denied` | Service not running as root | Check `User=root` in service file |
| `GPIO export failed: Device or resource busy` | GPIOs not unexported after crash | Manually unexport (see 12.3) |
| GPS UART produces garbage | Serial console conflict | Disable via raspi-config (see 12.4) |
| Service exits immediately | HAT not seated, no antenna, SPI disabled | Check hardware, verify SPI (see 12.5) |
| No packets in TTN Console | EUI mismatch or wrong frequency plan | Verify EUI in local_conf.json vs TTN |
| `make: *** [all] Error 1` | Missing build dependencies | Install `gcc make libusb-1.0-0-dev` |
| Service restart loop | StartLimitBurst=5 hit | `systemctl reset-failed lorawan-gateway` |

---

### 12.1 SPI Device Not Found

**Symptom:**
```
ERROR: failed to open SPI device /dev/spidev0.0
ls: cannot access '/dev/spidev0.*': No such file or directory
```

**Causes and fixes:**

1. `dtparam=spi=on` missing from config.txt:
```bash
grep spi /boot/config.txt        # Pi 3
# or
grep spi /boot/firmware/config.txt  # Pi 4+
# If no output, the line is missing
sudo bash -c 'echo "dtparam=spi=on" >> /boot/config.txt'
sudo reboot
```

2. Pi has not been rebooted since adding the config:
```bash
sudo reboot
```

3. SPI module not loading:
```bash
lsmod | grep spi
# If empty:
sudo modprobe spi_bcm2835
# Then add to /etc/modules for persistence:
echo spi_bcm2835 | sudo tee -a /etc/modules
```

**Verify fix:**
```bash
ls /dev/spidev0.*
# Expected: /dev/spidev0.0  /dev/spidev0.1
```

---

### 12.2 Permission Denied on SPI

**Symptom:**
```
ERROR: /dev/spidev0.0: Permission denied
```

**Fix 1 — Verify the service runs as root** (default configuration):
```bash
grep User /etc/systemd/system/lorawan-gateway.service
# Expected: User=root
```

**Fix 2 — Add your user to the spi group** (for manual testing only):
```bash
sudo usermod -aG spi $USER
# Then log out and back in
groups
# Should now include: spi
```

---

### 12.3 GPIO Export "Device or Resource Busy"

**Symptom:**
```
reset_lgw.sh: echo 23 > /sys/class/gpio/export: Device or resource busy
```

This happens when GPIOs were exported by a previous run but not unexported (e.g. after
a crash or `SIGKILL`).

**Fix:**
```bash
# Unexport all three GPIOs manually
echo 23 > /sys/class/gpio/unexport 2>/dev/null || true
echo 18 > /sys/class/gpio/unexport 2>/dev/null || true
echo 22 > /sys/class/gpio/unexport 2>/dev/null || true

# Verify they are gone
ls /sys/class/gpio/
# gpio18, gpio22, gpio23 should NOT be listed

# Restart the service
sudo systemctl restart lorawan-gateway
```

---

### 12.4 GPS UART Garbage / No Data

**Symptom:**
```bash
sudo timeout 5 cat /dev/ttyS0
# Output: ÿÿÿÿÿ???...  (garbage)
# or: (no output at all)
```

**Cause:** The Raspberry Pi serial console (`getty`) is using the same UART as GPS.

**Fix via raspi-config:**
```bash
sudo raspi-config
# Interface Options → Serial Port
# "Login shell accessible over serial?" → No
# "Serial port hardware enabled?" → Yes
sudo reboot
```

**Fix via cmdline.txt:**
```bash
sudo nano /boot/cmdline.txt
# Remove: console=serial0,115200
# Keep everything else on the same line
sudo reboot
```

**Verify:**
```bash
sudo stty -F /dev/ttyS0 9600
sudo timeout 10 cat /dev/ttyS0
# Expected: $GPGGA,...  $GPRMC,...  lines
```

---

### 12.5 Service Crashes Immediately

**Symptom:** `systemctl status lorawan-gateway` shows `failed` or `activating` in a loop.

**Diagnosis:**
```bash
sudo journalctl -u lorawan-gateway -n 50
```

**Common causes:**

1. **HAT not properly seated:**
   - Power off completely, remove HAT, reseat firmly, power on
   - Check for bent GPIO pins

2. **No LoRa antenna connected:**
   - The concentrator may fail SPI init without proper RF termination
   - Connect an 868 MHz SMA antenna before starting

3. **SPI not enabled (no reboot after config.txt edit):**
   - Check `ls /dev/spidev0.*` — if missing, reboot

4. **Wrong SPI path in global_conf.json:**
   ```bash
   grep com_path /etc/lorawan-gateway/global_conf.json
   # Expected: "com_path": "/dev/spidev0.0"
   ```

---

### 12.6 No Packets in TTN Console

**Symptom:** Gateway shows as connected in TTN Console but no uplinks appear.

**Checklist:**
```bash
# 1. Verify EUI matches TTN Console registration
sudo cat /etc/lorawan-gateway/local_conf.json | grep gateway_ID
# Compare to: TTN Console → your gateway → General settings → Gateway EUI

# 2. Verify service is running and sending PUSH_ACK
sudo journalctl -u lorawan-gateway -f
# Look for: PUSH_ACK received in X ms

# 3. Check frequency plan
# In TTN Console: your gateway → General settings → Frequency plan
# Must be: Europe 863-870 MHz (SF9 for RX2 — recommended)

# 4. Verify antenna is connected (visual check)

# 5. Check end device configuration
# End device must be configured for EU868 (OTAA or ABP)
# Try moving device closer — start within 1–5 meters
```

---

### 12.7 Build Fails (sx1302_hal)

**Symptom:**
```
make: *** [all] Error 1
```

**Fix 1 — Install missing dependencies:**
```bash
sudo apt-get install -y gcc make libusb-1.0-0-dev pkg-config git
```

**Fix 2 — Clean and retry:**
```bash
cd /tmp/lr1302_build
make clean
make -j$(nproc)
```

**Fix 3 — Full rebuild:**
```bash
sudo rm -rf /tmp/lr1302_build
git clone --depth 1 https://github.com/Elecrow-RD/LR1302_loraWAN.git /tmp/lr1302_build
cd /tmp/lr1302_build
make -j$(nproc)
```

**Find the binary after build:**
```bash
find /tmp/lr1302_build -name "lora_pkt_fwd" -type f
```

---

### 12.8 Service Restart Loop (StartLimitBurst Hit)

**Symptom:**
```bash
sudo systemctl status lorawan-gateway
# ● lorawan-gateway.service - ...
#    Loaded: loaded (/etc/systemd/system/lorawan-gateway.service; enabled)
#    Active: failed (Result: start-limit-hit) since ...
```

The service failed and restarted 5 times within 120 seconds (`StartLimitBurst=5`,
`StartLimitInterval=120`). Systemd stopped retrying to prevent hardware damage.

**Fix:**
```bash
# Reset the failure counter
sudo systemctl reset-failed lorawan-gateway

# Investigate the root cause first
sudo journalctl -u lorawan-gateway -n 100

# Then start again
sudo systemctl start lorawan-gateway
```

Do not just reset and restart blindly — read the logs to find the underlying cause
(SPI error, missing binary, hardware fault) before attempting to restart.

---

## 13. Reference

### 13.1 Installed File Reference

| Source File | Installed Path | Purpose |
|-------------|---------------|---------|
| (built from Elecrow repo) | `/opt/lorawan-gateway/lora_pkt_fwd` | UDP packet forwarder binary |
| `scripts/reset_lgw.sh` | `/opt/lorawan-gateway/reset_lgw.sh` | GPIO power/reset script |
| `config/local_conf.json.template` | `/opt/lorawan-gateway/local_conf.json.template` | EUI/server template |
| `config/global_conf.json` | `/etc/lorawan-gateway/global_conf.json` | EU868 radio config (8 channels) |
| (generated by configure_gateway.sh) | `/etc/lorawan-gateway/local_conf.json` | Gateway EUI + TTN server |
| `systemd/lorawan-gateway.service` | `/etc/systemd/system/lorawan-gateway.service` | Systemd unit |
| `scripts/setup.sh` | (run from repo, not installed) | One-shot installer |
| `scripts/configure_gateway.sh` | (run from repo, not installed) | Interactive EUI/TTN config |
| `hardware/elecrow-lr1302-pinout.md` | (documentation only) | GPIO map and hardware notes |

### 13.2 Key Configuration Files

**`/etc/lorawan-gateway/global_conf.json`** — EU868 radio configuration:
- `SX130x_conf.com_path`: `/dev/spidev0.0` — SPI device path
- `SX130x_conf.radio_0.freq`: `867500000` — Radio 0 center frequency (867.5 MHz)
- `SX130x_conf.radio_1.freq`: `868500000` — Radio 1 center frequency (868.5 MHz)
- `chan_multiSF_0` through `chan_multiSF_7` — 8 multi-SF channels (SF7–SF12)
- `chan_Lora_std` — LoRa standard channel (250 kHz, SF7)
- `chan_FSK` — FSK channel (125 kHz, 50 kbps)
- `gateway_conf.gps_tty_path`: `/dev/ttyS0` — GPS UART path
- `gateway_conf.stat_interval`: `30` — Statistics report interval in seconds

**`/etc/lorawan-gateway/local_conf.json`** — Per-deployment overrides:
- `gateway_conf.gateway_ID` — 16-char hex EUI (auto-generated from MAC)
- `gateway_conf.server_address` — TTN cluster server hostname
- `gateway_conf.serv_port_up` / `serv_port_down` — UDP port 1700

### 13.3 External Links

| Resource | URL |
|----------|-----|
| Elecrow LR1302 Product Page | https://www.elecrow.com/lr1302-lorawan-gateway-module-spi-868m.html |
| Elecrow LR1302 Wiki | https://www.elecrow.com/wiki/index.php?title=LR1302_LoRaWAN_Gateway_Module |
| Elecrow sx1302_hal GitHub | https://github.com/Elecrow-RD/LR1302_loraWAN |
| Semtech sx1302_hal upstream | https://github.com/Lora-net/sx1302_hal |
| TTN Console | https://console.cloud.thethings.network/ |
| TTN Gateway Registration Docs | https://www.thethingsindustries.com/docs/gateways/adding-gateways/ |
| EU868 Frequency Plan | https://www.thethingsnetwork.org/docs/lorawan/frequency-plans/ |
| Raspberry Pi GPIO Pinout | https://pinout.xyz/ |
| Raspberry Pi Imager | https://www.raspberrypi.com/software/ |

---

*Generated from source files: `CLAUDE.md`, `hardware/elecrow-lr1302-pinout.md`,
`scripts/setup.sh`, `scripts/configure_gateway.sh`, `scripts/reset_lgw.sh`,
`config/global_conf.json`, `config/local_conf.json.template`,
`systemd/lorawan-gateway.service`*
