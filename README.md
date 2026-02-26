# LoRaWAN Gateway con Raspberry Pi 3 + Elecrow HAT + LR1302

Gateway LoRaWAN de producción basado en **Raspberry Pi 3B/B+** y el **HAT Elecrow LR1302** (SX1302 + SX1250), conectado a **The Things Network (TTN)** mediante el protocolo UDP Packet Forwarder de Semtech.

---

## Descripción / Resumen del proyecto

Este proyecto proporciona un instalador completo y listo para producción de un gateway LoRaWAN. Permite conectar dispositivos LoRaWAN al backend de red **The Things Network (TTN)** usando el protocolo estándar **Semtech UDP Packet Forwarder** sobre UDP/1700.

### Características principales

- **Configuración automática de EUI** — generado desde la MAC de `eth0` mediante inserción FFFE (EUI-64)
- **Soporte EU868** por defecto, con soporte configurable para US915, AU915, AS923 e IN865
- **Instalador one-shot** (`setup.sh`) con comprobaciones de preflight, manejo de errores y salida en color
- **Servicio systemd** — arranque automático en boot, reinicio en fallo, límite de reintentos
- **Reset del concentrador vía GPIO** — secuencia de power-on/reset controlada (GPIO18, GPIO22, GPIO23)
- **Configuración predefinida EU868** — 8 canales multi-SF + canal LoRa estándar + canal FSK
- **Template de configuración local** — separación entre config de radio (`global_conf.json`) y credenciales (`local_conf.json`)

---

## Arquitectura

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
  │             │ UDP/1700                         │ RF          │
  │             ▼                                  ▼            │
  │      Internet / LAN                      Antena SMA         │
  └─────────────────────────────────────────────────────────────┘
                    │
                    ▼ UDP puerto 1700
  ┌─────────────────────────────────────────┐
  │     The Things Network (TTN)            │
  │     eu1.cloud.thethings.network         │
  │     EU868 — 8 canales, SF7-SF12         │
  └─────────────────────────────────────────┘
```

---

## Requisitos de hardware

| Componente | Especificación |
|------------|---------------|
| SBC | Raspberry Pi 3 Model B o B+ (recomendado) |
| HAT LoRaWAN | Elecrow LR1302 (SX1302 + SX1250, variante EU868) |
| Antena LoRa | SMA hembra, 868 MHz, 2–3 dBi — **OBLIGATORIA** |
| Fuente de alimentación | 5V / ≥ 2.5A (se recomienda ≥ 3A) |
| Tarjeta microSD | ≥ 16 GB, Clase 10 o superior |
| Red | Cable Ethernet (recomendado) o WiFi |
| Antena GPS | SMA activa, 3.3V (opcional) |

> **⚠️ ADVERTENCIA:** Nunca enciendas el HAT LR1302 sin una antena LoRa conectada al puerto `ANT`.
> Hacerlo puede dañar permanentemente el front-end RF SX1250.

---

## Requisitos de software

- **Raspberry Pi OS** — versión reciente (Bullseye o Bookworm), 64-bit preferible; versión Lite recomendada para uso headless
- **Acceso a internet** durante la instalación inicial (para clonar el repositorio y compilar `sx1302_hal`)
- **Cuenta en The Things Network (TTN)** si se utiliza TTN como backend de red: [console.cloud.thethings.network](https://console.cloud.thethings.network/)

---

## Instalación rápida (Quick Start)

```bash
# Clonar el repositorio
git clone https://github.com/fsvsgjmrsf-prog/Raspi_LORAWAN.git
cd Raspi_LORAWAN

# Dar permisos de ejecución
chmod +x scripts/*.sh

# Ejecutar el instalador principal (como root)
sudo bash scripts/setup.sh

# Reiniciar para activar SPI/I2C/UART
sudo reboot
```

Tras el reinicio el servicio `lorawan-gateway` arranca automáticamente.
Verifica que todo funciona:

```bash
# Estado del servicio
sudo systemctl status lorawan-gateway

# Logs en tiempo real
sudo journalctl -u lorawan-gateway -f
```

Salida esperada cuando el gateway está operativo:

```
[INFO] concentrator started, packet can now be received
[INFO] PUSH_ACK received in 12 ms
```

---

## Estructura del repositorio

```
Raspi_LORAWAN/
├── CLAUDE.md                          ← Arquitectura del proyecto e instrucciones
├── INSTALLATION_GUIDE.md              ← Guía de instalación completa (~1400 líneas)
├── .gitignore
│
├── scripts/
│   ├── setup.sh                       ← Instalador one-shot (ejecutar como root)
│   ├── configure_gateway.sh           ← Configuración interactiva EUI + TTN
│   └── reset_lgw.sh                   ← Secuenciador GPIO de power/reset
│
├── config/
│   ├── global_conf.json               ← Configuración de radio EU868 (8 canales)
│   └── local_conf.json.template       ← Template de EUI y servidor TTN
│
├── systemd/
│   └── lorawan-gateway.service        ← Unidad systemd
│
└── hardware/
    └── elecrow-lr1302-pinout.md       ← Mapa GPIO, tabla de señales, jumpers
```

---

## Rutas de instalación (tras ejecutar setup.sh)

| Archivo fuente | Destino instalado |
|----------------|-------------------|
| (compilado de Elecrow fork) | `/opt/lorawan-gateway/lora_pkt_fwd` |
| `scripts/reset_lgw.sh` | `/opt/lorawan-gateway/reset_lgw.sh` |
| `config/global_conf.json` | `/etc/lorawan-gateway/global_conf.json` |
| (generado por configure_gateway.sh) | `/etc/lorawan-gateway/local_conf.json` |
| `systemd/lorawan-gateway.service` | `/etc/systemd/system/lorawan-gateway.service` |

---

## Gestión del servicio

```bash
sudo systemctl start lorawan-gateway      # Iniciar
sudo systemctl stop lorawan-gateway       # Detener
sudo systemctl restart lorawan-gateway    # Reiniciar (tras cambio de config)
sudo systemctl status lorawan-gateway     # Estado actual
sudo journalctl -u lorawan-gateway -f     # Logs en tiempo real
sudo journalctl -u lorawan-gateway -b     # Logs desde el último arranque
```

---

## Registro en TTN Console

1. Accede a [console.cloud.thethings.network](https://console.cloud.thethings.network/)
2. Selecciona el cluster **eu1** (Europa)
3. Ve a **Gateways** → **Register gateway**
4. Introduce el **Gateway EUI** (obtenido al ejecutar `configure_gateway.sh`)
5. Selecciona el plan de frecuencias: `Europe 863-870 MHz (SF9 for RX2 — recommended)`
6. Haz clic en **Register gateway**

Para obtener el EUI del gateway instalado:

```bash
sudo cat /etc/lorawan-gateway/local_conf.json | grep gateway_ID
```

---

## Reconfiguración

Para cambiar el EUI o el servidor TTN:

```bash
sudo bash scripts/configure_gateway.sh
sudo systemctl restart lorawan-gateway
```

---

## Solución de problemas rápida

| Síntoma | Causa probable | Solución rápida |
|---------|---------------|-----------------|
| `failed to open SPI device /dev/spidev0.0` | SPI no activado o sin reboot | Añadir `dtparam=spi=on` a `config.txt` y reiniciar |
| `Permission denied on /dev/spidev0.0` | Servicio no ejecuta como root | Verificar `User=root` en el archivo de servicio |
| `GPIO export: Device or resource busy` | GPIOs no liberados tras crash | `echo 23 > /sys/class/gpio/unexport` (y 18, 22) |
| GPS UART con datos basura | Conflicto con consola serie | Deshabilitar vía `raspi-config` → Serial Port |
| Servicio termina inmediatamente | HAT mal colocado / sin antena / SPI inactivo | Revisar hardware y verificar SPI |
| Sin paquetes en TTN Console | EUI incorrecto o plan de frecuencias erróneo | Verificar EUI en `local_conf.json` vs TTN |

Para diagnóstico detallado, consulta [INSTALLATION_GUIDE.md](./INSTALLATION_GUIDE.md).

---

## Referencias

| Recurso | Enlace |
|---------|--------|
| Elecrow LR1302 Página del producto | https://www.elecrow.com/lr1302-lorawan-gateway-module-spi-868m.html |
| Elecrow LR1302 Wiki | https://www.elecrow.com/wiki/index.php?title=LR1302_LoRaWAN_Gateway_Module |
| Elecrow sx1302_hal GitHub | https://github.com/Elecrow-RD/LR1302_loraWAN |
| Semtech sx1302_hal upstream | https://github.com/Lora-net/sx1302_hal |
| TTN Console | https://console.cloud.thethings.network/ |
| Documentación TTN Gateways | https://www.thethingsindustries.com/docs/gateways/adding-gateways/ |
| Plan de frecuencias EU868 | https://www.thethingsnetwork.org/docs/lorawan/frequency-plans/ |
| Pinout Raspberry Pi | https://pinout.xyz/ |

---

## Licencia

Este proyecto se distribuye bajo los términos de la licencia MIT.
Consulta el archivo `LICENSE` para más información.
