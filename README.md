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

| Bucket | Retention | Purpose |
|---|---|---|
| `fronius_raw` | 90 days | 10 s raw samples from Telegraf |
| `fronius_1m` | 18 months | 1-minute downsampled data |
| `fronius_1h` | infinite | 1-hour downsampled data |

### Applying retention via CLI

Run once against the live InfluxDB instance (replace `$INFLUX_TOKEN` and
`$INFLUX_ORG` as appropriate, or source your `.env` first):

```bash
# fronius_raw — 90 days (2160 h)
influx bucket update \
  --name fronius_raw \
  --retention 2160h \
  --org "$INFLUX_ORG" \
  --token "$INFLUX_TOKEN" \
  --host http://localhost:8086

# fronius_1m — 18 months (13140 h)
influx bucket update \
  --name fronius_1m \
  --retention 13140h \
  --org "$INFLUX_ORG" \
  --token "$INFLUX_TOKEN" \
  --host http://localhost:8086

# fronius_1h — infinite (no expiry)
influx bucket update \
  --name fronius_1h \
  --retention 0 \
  --org "$INFLUX_ORG" \
  --token "$INFLUX_TOKEN" \
  --host http://localhost:8086
```

The same settings can be applied through the InfluxDB UI under
**Load Data → Buckets → (bucket) → Settings**. The commands are idempotent
and safe to re-run.

## Tasks
Create tasks in Influx using files under `influx/tasks`.

## Notes
- Verify sign convention of `grid_w` in your installation.
- Start with 10s polling; adjust later if needed.
