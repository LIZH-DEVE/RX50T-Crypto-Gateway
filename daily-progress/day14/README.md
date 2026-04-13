# Day 14

## Goal

Freeze the `AXIS v1.1` mainline as the documented repository baseline:
- align the written architecture with the shipped `crypto probe`
- remove legacy RTL noise from the main Vivado project script
- record the board-validated `AXIS` baseline and PMU recovery fix

## Completed

- recorded the current mainline as:
  - `parser -> protocol dispatcher -> contest_crypto_axis_core -> UART`
- kept `ACL Probe / SM4 Probe` explicitly marked as legacy validation paths
- updated the repository-level documentation to reflect the `AXIS v1.1` baseline:
  - main README
  - code analysis report
  - daily progress index
- corrected the code-analysis description of `contest_axis_block_packer`:
  - `tuser[0]` is the algorithm-select bit
  - it is not a frame-start marker
- removed legacy-only source files from the main `crypto probe` Vivado project script:
  - `contest_acl_core.sv`
  - `contest_crypto_bridge.sv`
- kept those legacy RTL files in the repository for:
  - `ACL Probe`
  - `SM4 Probe`
  - their dedicated unit tests and project scripts
- recorded the board-validated `AXIS v1.1` Git baseline:
  - `axis-v1.1-board-baseline-20260413`
- recorded the worker-side PMU recovery fix after ACL block residual frames

## Verification

### RTL

Fresh simulation and build targets for the mainline passed:
- `tb_contest_crypto_axis_core`
- `tb_uart_crypto_probe`
- `tb_uart_crypto_probe_stream_v3`
- `build_rx50t_uart_crypto_probe.ps1`

### Mainline build result

- `synth WNS = 8.603ns`
- `synth WHS = 0.058ns`
- `impl WNS = 6.392ns`
- `impl WHS = 0.035ns`
- `Slice LUTs = 3794 (11.64%)`
- `Slice Registers = 5449 (8.36%)`
- `Block RAM Tile = 4.5 (6.00%)`
- `DSP = 0`

### Board evidence recorded for this baseline

CLI smoke remained green on the programmed board:
- `--query-stats`
- `--clear-pmu`
- `--query-pmu`
- `--sm4-known-vector`
- `--aes-known-vector`

Real-board file traffic already recorded against this baseline:
- `32KB SM4`: `0.336s`, `0.780 Mbps`
- `32KB AES`: `0.336s`, `0.780 Mbps`
- `512KB SM4`: `5.331s`, `0.787 Mbps`
- `512KB AES`: `5.331s`, `0.787 Mbps`

ACL block recovery evidence:
- blocked stream still raises the session error
- worker now retries PMU query after residual stream-error contamination
- PMU snapshot is recovered after the ACL-blocked session

## Notes

- this day did not change the crypto datapath behavior
- the purpose was to make the repository state match the already-verified `AXIS v1.1` mainline
- the main `crypto probe` project script is now cleaner:
  - mainline sources only for the mainline build
  - legacy sources only in their own legacy projects

## Current Boundary

- legacy probe RTL still exists and is intentionally preserved
- GUI automated coverage is still event/layout level, not full serial E2E
- PMU is still a bottleneck-attribution layer, not a standalone hardware throughput meter

## Next Step

- if the next goal is performance storytelling, add an on-chip AXIS benchmark harness
- if the next goal is repository hygiene, add one short regression check that enforces the mainline TCL source list
