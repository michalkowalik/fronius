option task = {name: "downsample_1m_to_1h", every: 1h}

from(bucket: "fronius_1m")
  |> range(start: -task.every)
  |> filter(fn: (r) => r._measurement == "powerflow" or r._measurement == "meter")
  |> aggregateWindow(every: 1h, fn: mean, createEmpty: false)
  |> to(bucket: "fronius_1h", org: "home")