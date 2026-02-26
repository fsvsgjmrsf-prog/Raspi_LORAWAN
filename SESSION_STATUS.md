# Estado actual del proyecto (para retomar la conversación)

Fecha aproximada: última sesión febrero 2026

## Archivos principales presentes

| Archivo | Descripción |
|---------|-------------|
| `CLAUDE.md` | README completo con diagrama de arquitectura y troubleshooting |
| `README.md` | Resumen del proyecto + guía rápida de instalación (Quick Start) |
| `INSTALLATION_GUIDE.md` | Guía detallada paso a paso (~1400 líneas) |
| `.gitignore` | Ignores estándar (local_conf.json excluido) |
| `scripts/setup.sh` | Instalador one-shot (ejecutar como root) |
| `scripts/configure_gateway.sh` | Configuración interactiva EUI + TTN |
| `scripts/reset_lgw.sh` | Secuenciador GPIO de power/reset |
| `config/global_conf.json` | Configuración de radio EU868 (8 canales) |
| `config/local_conf.json.template` | Template de EUI y servidor TTN |
| `systemd/lorawan-gateway.service` | Unidad systemd con restart y límite de fallos |
| `hardware/elecrow-lr1302-pinout.md` | Mapa GPIO, tabla de señales, jumpers |

## Estado del repositorio

- **Remoto:** https://github.com/fsvsgjmrsf-prog/Raspi_LORAWAN.git
- **Branch principal:** `main`
- **Visibilidad:** Privado
- **Último commit:** `d21813b` — docs: add README.md with project overview, quick start, and reference tables

## Historial de commits

```
d21813b docs: add README.md with project overview, quick start, and reference tables
bc8c1a7 Update installation guide with correct GitHub repository URL
b11de00 Initial commit: LoRaWAN gateway setup for Raspberry Pi 3 + Elecrow HAT + LR1302
```

## Notas para la próxima sesión

- El proyecto está listo para pruebas en hardware real (Raspberry Pi 3B + HAT Elecrow LR1302).
- Todos los archivos de configuración EU868 están presentes y validados.
- Todo el código ha pasado chequeos básicos de sintaxis y formato JSON.

### Pendientes posibles

- [ ] Pruebas en hardware real y validación de uplinks en TTN Console
- [ ] Soporte para otras regiones (US915, AU915, AS923, IN865) con configs adicionales
- [ ] Dashboard básico de monitorización (uplinks/hora, RSSI, SNR)
- [ ] Integración con MQTT broker (Mosquitto) para forward local de datos
- [ ] Monitorización remota (Grafana + InfluxDB, o similar)
- [ ] Soporte GPS con procesado de tramas NMEA
- [ ] Script de actualización automática del binario `lora_pkt_fwd`
- [ ] Tests de integración básicos para verificar SPI y GPIO en arranque

## Cómo retomar

```bash
# Clonar el repo si es necesario
git clone https://github.com/fsvsgjmrsf-prog/Raspi_LORAWAN.git
cd Raspi_LORAWAN

# Ver el estado actual
git log --oneline
git status

# Consultar la guía completa
cat INSTALLATION_GUIDE.md
```
