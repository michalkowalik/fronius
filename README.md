# Fronius Local Stack (InfluxDB 2.7)

Local-first setup for collecting Fronius inverter/smart meter data, storing in InfluxDB, and visualizing with Grafana.

## Stack
- InfluxDB 2.7
- Telegraf
- Grafana (optional)

## Files
- `docker-compose.yml`
- `.env.example`
- `telegraf/telegraf.conf`
- `influx/tasks/downsample_10s_to_1m.flux`
- `influx/tasks/downsample_1m_to_1h.flux`
- `scripts/ev_best_window.flux`

## Quick start
1. Copy env template:
   ```bash
   cp .env.example .env
   ```
2. Edit `.env` and set your Fronius IP/token/password values.
3. Start services:
   ```bash
   docker compose up -d
   ```
4. Check Telegraf logs:
   ```bash
   docker compose logs -f telegraf
   ```
5. Open Influx UI: `http://<server-ip>:8086`

## Suggested buckets
Create these buckets in Influx UI:
- `fronius_raw` (retention: 60-90 days)
- `fronius_1m` (retention: 2 years)
- `fronius_1h` (retention: long-term)

## Tasks
Create tasks in Influx using files under `influx/tasks`.

## Notes
- Verify sign convention of `grid_w` in your installation.
- Start with 10s polling; adjust later if needed.
