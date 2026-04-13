# Day 13

## Goal

Close `PMU v1.1` end-to-end:
- finish the hardware PMU evidence path
- validate it with fresh simulation and build data
- flash the new bitstream to the board
- prove the GUI, CLI, and ACL paths on the real `RX50T`
- freeze the verified result in Git

## Completed

- finalized the PMU v1.1 hardware path:
  - `global_cycles`
  - `crypto_active_cycles`
  - `uart_tx_stall_cycles`
  - `stream_credit_block_cycles`
  - `acl_block_events`
- added PMU control commands on the host side:
  - query: `55 01 50`
  - clear: `55 01 4A`
- extended the CLI probe tool to print:
  - raw PMU counters
  - `HW Util`
  - `UART Stall`
  - `Credit Block`
  - hardware-derived elapsed time
- extended the GUI:
  - PMU panel with `Clear PMU` and `Read PMU`
  - PMU metric strip
  - PMU snapshot summary in the live log
  - automatic PMU capture around file-encryption sessions
- verified the runtime ACL path still works with the PMU-enabled image:
  - live key-map readback
  - `Deploy Threat Signature`
  - threat-tile flash
  - ACL event count in PMU
- built, flashed, and board-validated the new image
- tagged the verified result:
  - `pmu-v1.1-stream-2mbaud-20260413`

## Verification

### Python

- `python -m pytest ...test_crypto_gateway_protocol.py -q`
  - `38 passed`
- `python -m pytest ...test_crypto_gateway_worker.py -q`
  - `11 passed`
- `python -m pytest ...test_rx50t_crypto_gui_layout.py -q`
  - `5 passed`

### RTL

Fresh simulation passed for:
- `tb_contest_crypto_bridge`
- `tb_uart_crypto_probe`
- `tb_uart_crypto_probe_stream_v3`

Verified points:
- `o_pmu_crypto_active` is phase-aligned with `worker_busy_q`
- `credit_block` is not counted while `crypto_active` is asserted at a full window
- PMU query and clear frames return the expected formats

### Fresh build

Fresh bitstream build completed successfully.

Key implementation numbers:
- `impl WNS = 5.888ns`
- `impl WHS = 0.035ns`
- `Slice LUTs = 3969 (12.17%)`
- `Slice Registers = 5628 (8.63%)`
- `Block RAM Tile = 4.5 (6.00%)`
- `DSP = 0`

### Board smoke

Programmed board:
- `RX50T`
- `COM12`
- `2,000,000 baud`

CLI smoke after programming:
- `--query-stats`: pass
- `--clear-pmu`: pass
- `--query-pmu`: pass
  - `clk_hz = 50000000`
  - all PMU counters were `0` immediately after clear
- `--sm4-known-vector`: pass
- `--aes-known-vector`: pass

### Real-board GUI and worker path

Used a safe `512KB` file and ran both algorithms through the live GUI worker path.

`SM4` PMU snapshot:
- `global=266580316`
- `crypto_active=655360`
- `uart_tx_stall=134287671`
- `credit_block=0`
- `acl_events=0`
- `HW Util = 0.25%`
- `UART Stall = 50.36%`
- `Credit Block = 0.00%`

`AES` PMU snapshot:
- `global=266598814`
- `crypto_active=1835008`
- `uart_tx_stall=134284215`
- `credit_block=0`
- `acl_events=0`
- `HW Util = 0.69%`
- `UART Stall = 50.37%`
- `Credit Block = 0.00%`

### ACL event check

After forcing an ACL block:
- slot `0` hit counter increased to `1`
- the corresponding threat tile flashed red
- PMU event count increased

Observed PMU snapshot:
- `global=16096984`
- `crypto_active=0`
- `uart_tx_stall=2242`
- `credit_block=0`
- `acl_events=1`

## Notes

- this was the first full run where the board, CLI, GUI, and PMU evidence chain were all closed at `2,000,000 baud`
- the PMU data makes the current bottleneck explicit:
  - the UART transmit side dominates
  - the crypto engine is lightly utilized
  - the verified run did not hit a sustained `credit_block` wall

## Current Boundary

- PMU v1.1 is an evidence layer, not a hardware throughput meter
- ACL runtime update is still `1-byte` and volatile
- the GUI can still lag visually under heavy traffic even when the board is correct
- the current bottleneck is still outside the crypto core

## Next Step

- if we continue on performance, the next useful step is reducing host-link overhead rather than changing the crypto core
- if we continue on observability, the next PMU extension would be an explicit hardware throughput counter or stream chunk counter
