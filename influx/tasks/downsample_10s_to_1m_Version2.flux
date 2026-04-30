option task = {name: "downsample_10s_to_1m", every: 1m}

from(bucket: "fronius_raw")
  |> range(start: -task.every)
  |> filter(fn: (r) => r._measurement == "powerflow" or r._measurement == "meter")
  |> aggregateWindow(every: 1m, fn: mean, createEmpty: false)
  |> to(bucket: "fronius_1m", org: "home")
