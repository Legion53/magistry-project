# Day 7 experimental data

`Invoke-RecoveryExperiment.ps1` writes each execution to a new `run-*`
subdirectory, so existing raw observations are never overwritten.

- `raw/` — request-level observations;
- `metrics/` — latency/error-rate aggregates and MTTR;
- `events/` — timestamped timeline and Actuator/Toxiproxy snapshots;
- `charts/` — generated SVG timeline;
- `jfr/` — optional Java Flight Recorder captures.

The experimental protocol and exact commands are in
[`docs/experiments/day-07/toxiproxy-controlled-fault-injection.md`](../../docs/experiments/day-07/toxiproxy-controlled-fault-injection.md).
