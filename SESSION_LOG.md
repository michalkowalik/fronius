# Fronius Stack — Session Log & Documentation

## Overview

This document records all analysis, findings, decisions, and changes made during the engineering session of 2026-05-10/11. It covers energy monitoring, InfluxDB task provisioning, Telegraf configuration corrections, and Grafana operational issues.

---

## Stack Architecture

```
Fronius Inverter / Smart Meter
        │
        │ HTTP polling (10s)
        ▼
    Telegraf 1.31
        │
        │ Line Protocol
        ▼
  InfluxDB 2.7  ──── Tasks (downsampling + aggregation)
        │
        │ Flux queries
        ▼
   Grafana 11.1.4
```

### Buckets

| Bucket | Retention | Contents |
|---|---|---|
| `fronius_raw` | 60–90 days | Raw 10s samples from Telegraf |
| `fronius_1m` | 2 years | 1-minute means (downsampled) |
| `fronius_1h` | long-term | 1-hour means (downsampled) |
| `fronius_daily` | unlimited | Daily energy totals (aggregated) |

**All buckets must be created manually in the InfluxDB UI.** InfluxDB does not auto-create buckets referenced in task `to()` calls.

### Measurements written by Telegraf

| Measurement | Key Fields | Source Endpoint |
|---|---|---|
| `fronius_powerflow` | `pv_w`, `grid_w`, `load_w`, `autonomy_pct`, `self_consumption_pct` | `GetPowerFlowRealtimeData.fcgi` |
| `fronius_meter` | `p_sum_w`, `q_sum_var`, `s_sum_va`, `pf_sum`, `e_consumed_wh`, `e_produced_wh` | `GetMeterRealtimeData.cgi?Scope=System` |
| `fronius_battery` | `soc`, `temp_cell`, `v_dc`, `current_dc` | `GetStorageRealtimeData.cgi` |

### Field semantics

- `pv_w` — solar generation in watts, always non-negative
- `grid_w` — grid exchange in watts; positive = importing, negative = exporting
- `load_w` — site consumption in watts, positive
- `e_consumed_wh` — cumulative monotonic counter (Wh), total energy imported from grid since meter reset
- `e_produced_wh` — cumulative monotonic counter (Wh), total energy exported to grid since meter reset

---

## InfluxDB Tasks

InfluxDB does **not** scan the filesystem for `.flux` files. Every task in `influx/tasks/` must be manually registered in the InfluxDB instance via one of:

- **UI:** Tasks → Create Task → paste file contents
- **CLI:** `influx task create --file <path>.flux`
- **API:** `POST /api/v2/tasks`

Tasks must be created in dependency order:

1. `downsample_10s_to_1m.flux` — reads `fronius_raw`, writes `fronius_1m`
2. `downsample_1m_to_1h.flux` — reads `fronius_1m`, writes `fronius_1h`
3. `aggregate_daily_energy.flux` — reads `fronius_1m`, writes `fronius_daily`

### Task: `downsample_10s_to_1m`

Runs every 1 minute. Aggregates 10s raw samples into 1-minute means.

```flux
option task = {name: "downsample_10s_to_1m", every: 1m}

from(bucket: "fronius_raw")
  |> range(start: -task.every)
  |> filter(fn: (r) => r._measurement == "fronius_powerflow" or r._measurement == "fronius_meter")
  |> aggregateWindow(every: 1m, fn: mean, createEmpty: false)
  |> to(bucket: "fronius_1m", org: "home")
```

### Task: `downsample_1m_to_1h`

Runs every 1 hour. Aggregates 1-minute means into 1-hour means.

```flux
option task = {name: "downsample_1m_to_1h", every: 1h}

from(bucket: "fronius_1m")
  |> range(start: -task.every)
  |> filter(fn: (r) => r._measurement == "fronius_powerflow" or r._measurement == "fronius_meter")
  |> aggregateWindow(every: 1h, fn: mean, createEmpty: false)
  |> to(bucket: "fronius_1h", org: "home")
```

### Task: `aggregate_daily_energy`

Runs once per day at local midnight + 5 minutes (Europe/Berlin timezone). Computes three daily energy totals and writes them to `fronius_daily` as measurement `energy_daily`.

**Fields written:**

| Field | Description | Method |
|---|---|---|
| `pv_produced_wh` | Solar energy generated | `integral()` of `pv_w` over 1m samples ÷ 3600 |
| `grid_consumed_wh` | Energy imported from grid | Counter delta (`difference() + sum()`) on `e_consumed_wh` |
| `grid_exported_wh` | Energy exported to grid | Counter delta on `e_produced_wh` |

**Derived metric (computed in Grafana):**
```
site_consumed_wh = pv_produced_wh + grid_consumed_wh - grid_exported_wh
```

---

## Energy Dashboard

File: `grafana-dashboard-energy.json`
Dashboard UID: `fronius-energy-01`
Timezone: `Europe/Berlin`

### Panels

| Row | Panel | Type | Query window |
|---|---|---|---|
| Last Completed Day | PV Produced | Stat | last record in `fronius_daily` |
| Last Completed Day | Grid Consumed | Stat | last record in `fronius_daily` |
| Last Completed Day | Total Site Consumed | Stat | derived via `pivot + map`, last record |
| Daily Breakdown | Energy per Day | Bar chart | last 30 days, 3 series |
| Weekly Totals | PV / Grid / Site | Stat (×3) | `sum()` over last 7 days |
| Monthly Totals | PV / Grid / Site | Stat (×3) | `sum()` over last 30 days |

**Import:** Dashboards → Import → upload `grafana-dashboard-energy.json` → select InfluxDB datasource when prompted.

**Note:** "Last Completed Day" panels show the most recently aggregated day. Since the task runs at midnight + 5 min, today's data will appear the following day.

---

## Changes Made This Session

### 1. `telegraf/telegraf.conf` — removed broken duplicate input block

A `[[inputs.http]]` block was present (lines 129–143) labeled as an inverter input but incorrectly pointing at `${FRONIUS_METER_URL}` and attempting to extract `Body.Data.0.Controller.Current_DC` — a path that does not exist in the meter response. The block produced no data and wrote garbage to the `fronius_meter` measurement. It was removed.

### 2. `influx/tasks/downsample_10s_to_1m.flux` — fixed measurement name filter

The task was filtering for `r._measurement == "powerflow"` and `r._measurement == "meter"`. Telegraf writes measurements as `fronius_powerflow` and `fronius_meter` (due to `name_override` in telegraf.conf). Nothing was matching. Corrected to the actual measurement names.

### 3. `influx/tasks/downsample_1m_to_1h.flux` — same fix

Identical measurement name mismatch corrected.

### 4. `influx/tasks/aggregate_daily_energy.flux` — new file

New InfluxDB Task created. See task description above. Also contained the same measurement name bug on creation; corrected before finalisation.

### 5. `grafana-dashboard-energy.json` — new file

New Grafana dashboard for energy production and consumption reporting. See dashboard section above.

### 6. `.gitignore` — added `data/` exclusion

The entire `data/` directory (containing `grafana.db`, `influxd.bolt`, `influxd.sqlite`, and all other runtime-generated state) was added to `.gitignore` and removed from git tracking via `git rm --cached`.

**Root cause:** `data/grafana/grafana.db` was committed to the repository. When the repository was pulled on the Pi, the live production database was overwritten with the committed (stale/empty) version, causing Grafana to lose all configuration and fail to start correctly with "no such table" errors across all core tables.

**Files removed from tracking:**
- `data/grafana/grafana.db`
- `data/influxdb2/influxd.bolt`
- `data/influxdb2/influxd.sqlite`

---

## Grafana Recovery Procedure

If `grafana.db` is lost or corrupted:

1. Delete the damaged file on the host:
   ```bash
   rm data/grafana/grafana.db
   ```
2. Restart Grafana:
   ```bash
   docker compose restart grafana
   ```
3. Grafana will recreate `grafana.db` and run all migrations on first start.
4. Log in with `admin` / `admin`. Change password immediately via Profile → Change password, or set permanently via environment variable (see below).
5. Re-add the InfluxDB datasource: Connections → Data sources → Add new → InfluxDB → Flux query language → URL `http://influxdb:8086` → Token from `.env`.
6. Re-import dashboards: Dashboards → Import → upload `grafana-dashboard.json` and `grafana-dashboard-energy.json`.

### Recommended: set admin password via environment variable

Add to `docker-compose.yml` under the `grafana` service to survive future DB resets:

```yaml
grafana:
  environment:
    - GF_SECURITY_ADMIN_PASSWORD=your-password
```

---

## Known Issues / Open Items

| Item | Status |
|---|---|
| InfluxDB tasks must be registered manually — no automated provisioning | Open — Option B (init container) proposed but not implemented |
| `fronius_daily` bucket must be created manually before `aggregate_daily_energy` task will run | Open |
| `data/grafana/grafana.db` present in git history prior to this session | Not purged from history — `git filter-repo` would be required if removal from history is desired |
| Grafana datasource and dashboards lost on DB reset — no provisioning-as-code | Open |
