// Task: aggregate_daily_energy
// Runs once per day, 5 minutes after local midnight (Europe/Berlin).
// Reads fronius_1m, computes three daily energy totals, writes to fronius_daily.
//
// Fields written to measurement "energy_daily":
//   pv_produced_wh   — solar energy generated (integral of pv_w)
//   grid_consumed_wh — energy imported from grid (meter counter delta)
//   grid_exported_wh — energy exported to grid (meter counter delta)
//
// site_consumed_wh = pv_produced_wh + grid_consumed_wh - grid_exported_wh
// is derived in Grafana via Flux query or panel transformation.
//
// Prerequisites:
//   - Bucket "fronius_daily" must exist in InfluxDB (create manually in UI or CLI).
//   - Bucket "fronius_1m" must contain measurements "fronius_powerflow" (field: pv_w)
//     and "fronius_meter" (fields: e_consumed_wh, e_produced_wh).

import "date"
import "timezone"

option task = {name: "aggregate_daily_energy", every: 1d, offset: 5m}
option location = timezone.location(name: "Europe/Berlin")

// Start of the calendar day being aggregated (local midnight, Europe/Berlin).
dayStart = date.truncate(t: date.sub(d: 1d, from: now()), unit: 1d)

// ── PV produced ──────────────────────────────────────────────────────────────
// integral(unit: 1s) integrates W over seconds → W·s. Divide by 3600 → Wh.
// pv_w is always non-negative (inverter output), so no filtering needed.
pv_produced =
    from(bucket: "fronius_1m")
        |> range(start: -1d)
        |> filter(fn: (r) => r._measurement == "fronius_powerflow" and r._field == "pv_w")
        |> integral(unit: 1s)
        |> map(
            fn: (r) => ({r with
                _time: dayStart,
                _value: r._value / 3600.0,
                _field: "pv_produced_wh",
                _measurement: "energy_daily",
            }),
        )

// ── Grid consumed ─────────────────────────────────────────────────────────────
// e_consumed_wh is a cumulative monotonic counter (Wh).
// difference(nonNegative: true) computes per-sample deltas, dropping resets.
// sum() collapses the day's deltas into a single total.
grid_consumed =
    from(bucket: "fronius_1m")
        |> range(start: -1d)
        |> filter(fn: (r) => r._measurement == "fronius_meter" and r._field == "e_consumed_wh")
        |> difference(nonNegative: true)
        |> sum()
        |> map(
            fn: (r) => ({r with
                _time: dayStart,
                _field: "grid_consumed_wh",
                _measurement: "energy_daily",
            }),
        )

// ── Grid exported ─────────────────────────────────────────────────────────────
// e_produced_wh is a cumulative monotonic counter (Wh) for energy sent to grid.
grid_exported =
    from(bucket: "fronius_1m")
        |> range(start: -1d)
        |> filter(fn: (r) => r._measurement == "fronius_meter" and r._field == "e_produced_wh")
        |> difference(nonNegative: true)
        |> sum()
        |> map(
            fn: (r) => ({r with
                _time: dayStart,
                _field: "grid_exported_wh",
                _measurement: "energy_daily",
            }),
        )

// ── Write ─────────────────────────────────────────────────────────────────────
union(tables: [pv_produced, grid_consumed, grid_exported])
    |> to(bucket: "fronius_daily", org: "home")
