// Prototype query: find hours with highest expected PV surplus.
// Assumes forecast and load estimates are written to bucket "fronius_1h"
// with measurements:
//   - forecast: field "pv_w_pred"
//   - forecast: field "load_w_pred"

pv =
  from(bucket: "fronius_1h")
    |> range(start: now(), stop: now() + 24h)
    |> filter(fn: (r) => r._measurement == "forecast" and r._field == "pv_w_pred")
    |> keep(columns: ["_time", "_value"])
    |> rename(columns: {_value: "pv_w_pred"})

load =
  from(bucket: "fronius_1h")
    |> range(start: now(), stop: now() + 24h)
    |> filter(fn: (r) => r._measurement == "forecast" and r._field == "load_w_pred")
    |> keep(columns: ["_time", "_value"])
    |> rename(columns: {_value: "load_w_pred"})

join(tables: {pv: pv, load: load}, on: ["_time"])
  |> map(fn: (r) => ({r with surplus_w: r.pv_w_pred - r.load_w_pred}))
  |> sort(columns: ["surplus_w"], desc: true)
  |> limit(n: 8)