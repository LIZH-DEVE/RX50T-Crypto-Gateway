# RX50T Crypto Gateway

`RX50T Crypto Gateway` is a pure-`PL` security datapath prototype for the `RX50T` board.

The currently validated hardware line is:

`UART @ 2,000,000 baud -> parser -> protocol dispatcher -> contest_crypto_axis_core (ACL AXIS + packer + crypto block engine + unpacker) -> UART`

The project deliberately avoids:
- `ARM/PS`
- `DMA/DDR/PBM`
- full `Ethernet/IP/UDP`

The board is used for the hard real-time path only:
- framed UART command/data ingress
- ACL v2 blocking
- AES/SM4 encryption
- watchdog-based fault recovery
- PMU and trace-buffer observability

## Current Status

Current merged baseline under `main`, plus this `P2` branch work:
- `ACL v2`: `8` runtime slots, `16B` signatures, `32-bit` hit counters, sliding-window block path
- `PMU v3`: stream counters + clock-gating counters + clock status flags
- `P1` clock gating: `BUFGCE`-gated `contest_crypto_axis_core` island with GUI `Clock: ACTIVE / GATED`
- `P2` trace buffer: `256 x 64-bit`, BRAM-backed, independent `1 ms` timestamp base, paged UART readback
- `AES-128` and `SM4-128`
- `16B / 32B / 64B / 128B` block encryption
- `128B` streaming file path on the board and in the GUI worker
- on-chip `1 MiB` benchmark flow
- watchdog fatal frames: `55 02 EE code`

Current host-side capabilities:
- CLI probe tool for vectors, stats, ACL v2, PMU, bench, and trace readback
- Tkinter GUI for:
  - live connect / disconnect
  - AES/SM4 demo vectors
  - runtime file encryption
  - Evidence Dashboard with frozen file-session snapshot
  - live ACL v2 key-map / hit-counter readback
  - `Deploy Threat Signature`
  - PMU panel with `HW Util / UART Stall / Credit Block / Clock Status`
  - manual `Read Trace`

ACL runtime constraints that still apply:
- rule width is fixed at `16 bytes`
- slot count is fixed at `8`
- updates are `volatile only`
- rewriting a slot resets that slot's hit counter

## Board Baseline

- board: `RX50T`
- serial port used in the latest merged board baseline: `COM12`
- UART: `2,000,000 8N1`
- clock: `Y18 / 50MHz`
- UART pins: `K1 (RX) / J1 (TX)`
- reset key: `J20`
- FTDI latency timer used in the latest merged board run: `1 ms`

## Control and Data Plane

Data plane:
- `UART -> parser -> ACL v2 -> AES/SM4 -> UART`

Control plane:
- stats query
- ACL v2 hit-counter query
- ACL v2 key-map query
- ACL v2 slot rewrite
- PMU snapshot query
- PMU clear
- trace metadata query
- trace page query
- on-chip bench run / result query

The current PMU v3 counters are:
- `global_cycles`
- `crypto_active_cycles`
- `uart_tx_stall_cycles`
- `stream_credit_block_cycles`
- `acl_block_events`
- `stream_bytes_in`
- `stream_bytes_out`
- `stream_chunk_count`
- `crypto_clock_gated_cycles`
- `crypto_clock_status_flags`

## Protocol Quick Reference

All commands keep the existing frame wrapper:

`55 LEN PAYLOAD`

Current commands:
- stats query:
  - `55 01 3F`
  - response: `53 total acl aes sm4 err 0A`
- ACL v2 hit-counter query:
  - `55 01 48`
  - response: `55 21 48 <8 * be32 counters>`
- ACL v2 key-map query:
  - `55 01 4B`
  - response: `55 81 4B <8 * 16B signatures>`
- ACL v2 write:
  - request: `55 12 43 <slot> <16B signature>`
  - ACK: `55 12 43 <slot> <16B signature>`
- PMU query:
  - `55 01 50`
  - current response schema: `v0x03`
  - payload fields: `0x50 0x03 clk_hz_be32 + 10 * be64 counters`
- PMU clear:
  - `55 01 4A`
  - response: `55 02 4A 00`
- fatal frame:
  - `55 02 EE code`
  - `code = 0x01` stream watchdog timeout
  - `code = 0x02` crypto watchdog timeout
- trace metadata query:
  - `55 01 54`
  - response: `55 06 54 01 valid_be16 write_ptr flags`
- trace page query:
  - `55 02 54 <page_idx>`
  - response: `55 85 54 02 page_idx entry_count flags <16 * be64 entries>`

Trace entry format:
- `[63:32] timestamp_ms`
- `[31:24] event_code`
- `[23:16] arg0`
- `[15:0] arg1`

## Repository Layout

- `contest_project/rtl/contest/`
  - pure-`PL` RTL
- `contest_project/tb/contest/`
  - simulation testbenches
- `contest_project/tools/`
  - host UART probe CLI
  - shared host protocol layer
  - worker
  - Tkinter GUI
- `contest_project/scripts/`
  - Vivado build scripts
- `contest_project/constraints/`
  - board constraints
- `docs/`
  - architecture notes, baseline notes, runbooks
- `daily-progress/`
  - day-by-day progress logs

## Quick Start

Build bitstream:

```powershell
powershell -ExecutionPolicy Bypass -File .\contest_project\scripts\build_rx50t_uart_crypto_probe.ps1
```

Program the board, then run CLI smoke:

```powershell
py -3 .\contest_project\tools\send_rx50t_crypto_probe.py --port COM12 --baud 2000000 --query-stats
py -3 .\contest_project\tools\send_rx50t_crypto_probe.py --port COM12 --baud 2000000 --clear-pmu
py -3 .\contest_project\tools\send_rx50t_crypto_probe.py --port COM12 --baud 2000000 --query-pmu
py -3 .\contest_project\tools\send_rx50t_crypto_probe.py --port COM12 --baud 2000000 --query-trace
py -3 .\contest_project\tools\send_rx50t_crypto_probe.py --port COM12 --baud 2000000 --sm4-known-vector
py -3 .\contest_project\tools\send_rx50t_crypto_probe.py --port COM12 --baud 2000000 --aes-known-vector
```

Launch GUI:

```powershell
py -3 .\contest_project\tools\rx50t_crypto_gui.py
```

## Latest Verified Results

Fresh Python verification on `feature/p2-trace-buffer`:
- `107 passed`

Fresh RTL / TB verification on `feature/p2-trace-buffer`:
- `build_tb_contest_trace_buffer.ps1`: pass
- `build_tb_uart_crypto_probe_trace.ps1`: pass
- `build_tb_uart_crypto_probe_acl_v2.ps1`: pass
- `build_tb_uart_crypto_probe_onchip_bench.ps1`: pass
- `build_tb_uart_crypto_probe_watchdog.ps1`: pass

Fresh build result on `feature/p2-trace-buffer`:
- bitstream:
  - `contest_project/build/rx50t_uart_crypto_probe/rx50t_uart_crypto_probe.runs/impl_1/rx50t_uart_crypto_probe_board_top.bit`
- routed timing summary:
  - `WNS = 5.979ns`
  - `WHS = 0.011ns`
- per-clock routed timing:
  - `i_clk WNS = 7.185ns`
  - `clk_crypto_gated WNS = 5.979ns`
  - `clk_crypto_gated WHS = 0.034ns`
- implementation utilization:
  - `Slice LUTs = 7444 (22.83%)`
  - `Slice Registers = 14877 (22.82%)`
  - `Block RAM Tile = 5 (6.67%)`
  - `DSPs = 0`
- routed DRC:
  - `Violations found = 0`

Physical sanity checks from the same fresh build:
- trace storage remained BRAM-backed: `Block RAM Tile = 5`, not a LUT-heavy fallback
- LUT memory footprint stayed minimal: `LUT as Memory = 6`
- high-frequency trace event sources were checked for pulse semantics:
  - `STREAM_START` uses edge detection
  - `ACL_BLOCK` uses `axis_acl_block_pulse_w`
  - fatal trace uses watchdog timeout equality with `!fatal_pending_q`

Most recent carried board validation from the merged `main` / `P1` baseline:
- PMU v3 query: pass
- idle gated counter growth: pass
- ACL write wake / ACK: pass
- benign pass-through: pass
- exact block: pass
- `SM4` on-chip bench: pass

Branch-level trace board smoke on `feature/p2-trace-buffer` (`COM12 @ 2,000,000`) completed and passed:
- trace metadata/page query: pass
- `ACL_CFG_ACK` and `ACL_BLOCK` readback: pass
- `BENCH_START` and `BENCH_DONE` readback: pass
- `FATAL_0x01` persisted after soft-abort and remained readable: pass
- GUI `Read Trace` rendered `FATAL_0x01`: pass

## Documentation Entry Points

- [Daily progress index](./daily-progress/README.md)
- [Code analysis report](./docs/CODE_ANALYSIS_REPORT.md)
- [Current baseline](./docs/RX50T_CURRENT_BASELINE.md)
- [Architecture overview](./docs/RX50T_ARCHITECTURE_OVERVIEW.md)
- [P1 demo runbook](./docs/RX50T_P1_DEMO_RUNBOOK.md)

## Current Boundaries

- ACL v2 hot update is `16B` runtime signature provisioning, not persistent storage
- updates are not persistent across reset or power cycle
- the board-side transport unit is still `128B`
- trace readout is explicit and paged; there is no trace clear command and no background polling path
- PMU / trace / GUI numbers are observability evidence, not absolute board power measurement
- trace-specific board smoke has been rerun on this branch; metadata/page readback and GUI `Read Trace` both passed

## Explicitly Out of Scope

- `ARM/PS`
- `DMA / DDR / PBM`
- full `Ethernet/IP/UDP`
- persistent ACL storage in flash
- decryption and unpadding path
- `CDC / GALS`
- `PUF / hardware key derivation`
