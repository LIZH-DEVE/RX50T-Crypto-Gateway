# RX50T Crypto Gateway

`RX50T Crypto Gateway` is a pure-`PL` security datapath prototype for the `RX50T` board.

The currently validated line is:

`UART @ 2,000,000 baud -> parser -> 8-slot BRAM-backed runtime ACL -> BRAM-backed AES/SM4 block-stream engine -> UART`

The project deliberately avoids:
- `ARM/PS`
- `DMA/DDR/PBM`
- full `Ethernet/IP/UDP`

The board is used for the hard real-time path only:
- frame parsing
- ACL blocking
- runtime ACL rule rewrite
- AES/SM4 encryption
- hardware-side observability through counters and PMU snapshots

## Current Status

Fresh validated baseline:
- board-side `2,000,000 baud` UART datapath
- `AES-128` and `SM4-128`
- `16B / 32B / 64B / 128B` block encryption
- `128B` streaming file path on the board and in the GUI worker
- `8` runtime ACL slots backed by BRAM
- ACL hot update without reboot through control frames
- ACL key-map readback
- per-slot ACL hit counters
- PMU v1.1 hardware snapshot and clear path

Current host-side capabilities:
- CLI probe tool for vectors, stats, ACL, and PMU
- Tkinter GUI for:
  - live connect / disconnect
  - AES/SM4 demo vectors
  - runtime file encryption
  - live ACL key-map readback
  - `Deploy Threat Signature`
  - PMU panel with `HW Util / UART Stall / Credit Block / ACL Events`

Current default ACL bytes:
- slot `0`: `X`
- slot `1`: `Y`
- slot `2`: `Z`
- slot `3`: `W`
- slot `4`: `P`
- slot `5`: `R`
- slot `6`: `T`
- slot `7`: `U`

Runtime ACL constraints:
- rule width is `1 byte`
- updates are `volatile only`
- duplicate rule bytes are rejected
- rewriting a slot resets that slot's hit counter

## Board Baseline

- board: `RX50T`
- serial port: `COM12`
- UART: `2,000,000 8N1`
- clock: `Y18 / 50MHz`
- UART pins: `K1 (RX) / J1 (TX)`
- reset key: `J20`
- FTDI latency timer used during the latest board run: `1 ms`

## Control and Data Plane

Data plane:
- `UART -> parser -> ACL -> AES/SM4 -> UART`

Control plane:
- stats query
- ACL rule-hit query
- ACL key-map query
- ACL slot rewrite
- PMU snapshot query
- PMU clear

The current PMU v1.1 counters are:
- `global_cycles`
- `crypto_active_cycles`
- `uart_tx_stall_cycles`
- `stream_credit_block_cycles`
- `acl_block_events`

## Protocol Quick Reference

All commands keep the existing frame wrapper:

`55 LEN PAYLOAD`

Current commands:
- stats query:
  - `55 01 3F`
  - response: `53 total acl aes sm4 err 0A`
- rule-hit query:
  - `55 01 48`
  - response: `48 c0 c1 c2 c3 c4 c5 c6 c7 0A`
- ACL key-map query:
  - `55 01 4B`
  - response: `4B key0 key1 key2 key3 key4 key5 key6 key7 0A`
- ACL write:
  - `55 03 03 idx key`
  - response: `43 idx key 0A`
  - reject: `45 0A`
- PMU query:
  - `55 01 50`
  - response:
    - `55 2E 50 01 clk_hz_be32 global_be64 crypto_active_be64 uart_tx_stall_be64 credit_block_be64 acl_block_events_be64`
- PMU clear:
  - `55 01 4A`
  - response: `55 02 4A 00`

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
py -3 .\contest_project\tools\send_rx50t_crypto_probe.py --port COM12 --baud 2000000 --sm4-known-vector
py -3 .\contest_project\tools\send_rx50t_crypto_probe.py --port COM12 --baud 2000000 --aes-known-vector
```

Launch GUI:

```powershell
py -3 .\contest_project\tools\rx50t_crypto_gui.py
```

## Latest Verified Results

Latest build and board-tested tag:
- `pmu-v1.1-stream-2mbaud-20260413`

Fresh build result:
- bitstream:
  - `contest_project/build/rx50t_uart_crypto_probe/rx50t_uart_crypto_probe.runs/impl_1/rx50t_uart_crypto_probe_board_top.bit`
- `impl WNS = 5.888ns`
- `impl WHS = 0.035ns`
- `Slice LUTs = 3969 (12.17%)`
- `Slice Registers = 5628 (8.63%)`
- `Block RAM Tile = 4.5 (6.00%)`
- `DSP = 0`

Fresh CLI smoke on the programmed board:
- `--query-stats`: pass
- `--clear-pmu`: pass
- `--query-pmu`: pass
  - `clk_hz = 50000000`
  - all counters cleared to `0`
- `SM4 16B` known vector: pass
- `AES 16B` known vector: pass

Fresh GUI worker run on the real board with `512KB` file traffic:
- `SM4`
  - PMU snapshot:
    - `global=266580316`
    - `crypto_active=655360`
    - `uart_tx_stall=134287671`
    - `credit_block=0`
    - `acl_events=0`
  - derived ratios:
    - `HW Util = 0.25%`
    - `UART Stall = 50.36%`
    - `Credit Block = 0.00%`
- `AES`
  - PMU snapshot:
    - `global=266598814`
    - `crypto_active=1835008`
    - `uart_tx_stall=134284215`
    - `credit_block=0`
    - `acl_events=0`
  - derived ratios:
    - `HW Util = 0.69%`
    - `UART Stall = 50.37%`
    - `Credit Block = 0.00%`

Interpretation of the latest PMU evidence:
- the current bottleneck is still the UART transmit side and host link behavior
- the crypto engine is not saturated
- the streaming window did not become the dominant limiter in the verified `512KB` board run

Fresh ACL runtime path verification:
- GUI `Deploy Threat Signature`: verified
- live key-map readback on connect: verified
- ACL block flash in threat array: verified
- PMU snapshot after ACL event:
  - `global=16096984`
  - `crypto_active=0`
  - `uart_tx_stall=2242`
  - `credit_block=0`
  - `acl_events=1`

## Documentation Entry Points

- [Daily progress index](./daily-progress/README.md)
- [Current baseline](./docs/RX50T_CURRENT_BASELINE.md)
- [Architecture overview](./docs/RX50T_ARCHITECTURE_OVERVIEW.md)
- [P1 demo runbook](./docs/RX50T_P1_DEMO_RUNBOOK.md)

## Current Boundaries

- ACL v1 hot update is `1-byte` rule provisioning, not a `16B` signature matcher
- updates are not persistent across reset or power cycle
- the board-side transport unit is still `128B`
- PMU v1.1 provides hardware-side ratios and raw counters, not a standalone hardware Mbps counter
- GUI rendering can still lag behind sustained traffic; PMU is the authoritative source for bottleneck attribution

## Explicitly Out of Scope

- `ARM/PS`
- `DMA / DDR / PBM`
- full `Ethernet/IP/UDP`
- persistent ACL storage in flash
- decryption and unpadding path
- `16B` sliding-window signature ACL
