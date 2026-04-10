# RX50T Crypto Gateway

`RX50T Crypto Gateway` is a pure-`PL` security datapath prototype for the `RX50T` board.

The current validated mainline is:

`UART -> Parser -> 8-rule BRAM-backed ACL -> BRAM-backed block-stream AES/SM4 (16B/32B/64B/128B) -> UART + Stats Query + Rule-Stats Query`

This repository intentionally does not depend on:
- `ARM/PS`
- `DMA/DDR/PBM`
- a full `Ethernet/IP/UDP` stack

The goal is to keep the board focused on the hard real-time work:
- frame parsing
- hardware ACL blocking
- AES/SM4 block encryption
- lightweight observability through stats counters

The current system direction is:
- board-side pure `PL` datapath
- PC-side GUI as the instrument panel for demo, monitoring, and batch testing
- the GUI exposes the compiled ACL rule table carried by the current bitstream
- the GUI can query board-side per-rule ACL counters and highlight the current hot rule

The GUI MVP has already completed its first real-board walkthrough against the live `RX50T` board.

## Current Status

The current multiblock baseline is complete and has fresh real-board evidence.

Implemented:
- BRAM-backed ACL rule table
- current default ACL entries: `X / Y / Z / W / P / R / T / U`
- `AES-128` and `SM4-128`
- block-stream bridge with BRAM ingress/egress FIFOs
- single-block (`16B`), two-block (`32B`), four-block (`64B`), and eight-block (`128B`) encryption
- protocol error fallback `E\n`
- ACL block fallback `D\n`
- stats query command `55 01 3F`
- per-rule ACL counter query command `55 01 48`
- five `8-bit` counters:
  - `total`
  - `acl`
  - `aes`
  - `sm4`
  - `err`
- eight `8-bit` board-side ACL rule counters:
  - `X`
  - `Y`
  - `Z`
  - `W`
  - `P`
  - `R`
  - `T`
  - `U`

Board baseline:
- board: `RX50T`
- serial port: `COM12`
- UART: `115200 8N1`
- clock: `Y18 / 50MHz`
- UART pins: `K1 (RX) / J1 (TX)`
- reset key: `J20`

## Repository Layout

- `contest_project/rtl/contest/`
  - current pure-`PL` RTL
- `contest_project/tb/contest/`
  - simulation testbenches
- `contest_project/tools/`
  - host-side UART test tools
  - shared host protocol layer
  - Tkinter GUI MVP
- `contest_project/scripts/`
  - Vivado build scripts
- `contest_project/constraints/`
  - board constraints
- `reference/`
  - extracted reference crypto code from the original large project
- `docs/`
  - architecture notes, current baseline, board test docs, demo runbook
- `daily-progress/`
  - day-by-day progress logs

## Documentation Entry Points

- [Current baseline](./docs/RX50T_CURRENT_BASELINE.md)
- [Architecture overview](./docs/RX50T_ARCHITECTURE_OVERVIEW.md)
- [P1 demo runbook](./docs/RX50T_P1_DEMO_RUNBOOK.md)
- [Daily progress index](./daily-progress/README.md)
- GUI entry:
  - `py -3 .\contest_project\tools\rx50t_crypto_gui.py`

## Implemented Capability

- `UART Echo`
- `UART -> Parser -> UART`
- `UART -> Parser -> ACL -> UART`
- `UART -> Parser -> ACL -> SM4 -> UART`
- `UART -> Parser -> ACL -> AES/SM4 -> UART`
- `UART -> Parser -> 4-rule ACL -> AES/SM4 -> UART + Stats Query`
- `UART -> Parser -> 8-rule BRAM-backed ACL -> BRAM-backed block-stream AES/SM4 (16B/32B/64B/128B) -> UART + Stats Query + Rule-Stats Query`

## Explicitly Out of Scope

- dynamic key download
- `CBC`
- payloads longer than `128B`
- `DMA / DDR / PBM`
- `ARM/PS`
- full `Ethernet/IP/UDP` protocol processing

## Quick Demo

Program the current block-stream bitstream, then run:

```powershell
py -3 .\contest_project\tools\send_rx50t_crypto_probe.py --port COM12 --query-stats --expect-stats 0,0,0,0,0
py -3 .\contest_project\tools\send_rx50t_crypto_probe.py --port COM12 --query-rule-stats --expect-rule-stats 0,0,0,0,0,0,0,0
py -3 .\contest_project\tools\send_rx50t_crypto_probe.py --port COM12 --block-ascii XYZ
py -3 .\contest_project\tools\send_rx50t_crypto_probe.py --port COM12 --sm4-known-vector
py -3 .\contest_project\tools\send_rx50t_crypto_probe.py --port COM12 --aes-known-vector
py -3 .\contest_project\tools\send_rx50t_crypto_probe.py --port COM12 --sm4-two-block-vector
py -3 .\contest_project\tools\send_rx50t_crypto_probe.py --port COM12 --aes-two-block-vector
py -3 .\contest_project\tools\send_rx50t_crypto_probe.py --port COM12 --sm4-four-block-vector
py -3 .\contest_project\tools\send_rx50t_crypto_probe.py --port COM12 --aes-four-block-vector
py -3 .\contest_project\tools\send_rx50t_crypto_probe.py --port COM12 --sm4-eight-block-vector
py -3 .\contest_project\tools\send_rx50t_crypto_probe.py --port COM12 --aes-eight-block-vector
py -3 .\contest_project\tools\send_rx50t_crypto_probe.py --port COM12 --invalid-selector
py -3 .\contest_project\tools\send_rx50t_crypto_probe.py --port COM12 --query-stats --expect-stats 9,1,4,4,1
```

## Latest Verified Results

Latest BRAM-backed block-stream build:
- `DRC = 0`
- `WNS = 6.199ns`
- `WHS = 0.031ns`
- `Slice LUTs = 3432`
- `Slice Registers = 4702`
- `Slice = 1580`
- `RAMB36E1 = 4`
- `RAMB18E1 = 1`
- `DSP = 0`

Fresh BRAM-backed ACL smoke test:
- initial stats query: `53 00 00 00 00 00 0A`
- `SM4 16B`: pass
- `AES 16B`: pass
- ACL block: `XYZ -> 44 0A`
- final stats query: `53 02 01 00 01 00 0A`

Board-side rule-counter query:
- persistent-session real-board check with a short host-side settle between blocked frames:
  - before:
    - `X=1, P=0`
  - `XYZ -> 44 0A`
  - `PQR -> 44 0A`
  - after:
    - `X=2, P=1`
  - observed delta:
    - `X:+1`
    - `P:+1`
- the GUI now applies a short delayed auto-refresh after ACL block events so the board-side rule counters are read back after this settle window

Expanded rule-table smoke test:
- before `XYZ`: `53 00 00 00 00 00 0A`
- `XYZ -> 44 0A`
- after `XYZ`: `53 01 01 00 00 00 0A`
- before `PQR`: `53 01 01 00 00 00 0A`
- `PQR -> 44 0A`
- after `PQR`: `53 02 02 00 00 00 0A`

Real-board verified:
- initial stats query: `53 00 00 00 00 00 0A`
- ACL block: `XYZ -> 44 0A`
- `SM4` known vector: pass
- `AES` known vector: pass
- `SM4` two-block vector: pass
- `AES` two-block vector: pass
- `SM4` four-block vector: pass
- `AES` four-block vector: pass
- invalid selector: `45 0A`
- final stats query: `53 07 01 03 03 01 0A`

Fresh 64B multiblock smoke:
- `SM4 64B`: pass
- `AES 64B`: pass
- stats after the two 64B vectors:
  - `53 02 00 01 01 00 0A`

Fresh 128B block-stream smoke:
- initial stats query:
  - `53 00 00 00 00 00 0A`
- `SM4 128B`: pass
- `AES 128B`: pass
- final stats query:
  - `53 02 00 01 01 00 0A`

GUI real-board walkthrough verified:
- connect `COM12`
- `Query Stats`: pass
- `Query Rule Hits`: pass
- `SM4 16B`: pass
- `AES 16B`: pass
- `ACL Block (XYZ)`: pass
- `SM4 32B`: pass
- `AES 32B`: pass
- final GUI stats: `53 05 01 02 02 00 0A`
- GUI rule-hit panel now refreshes from board-side ACL counters

GUI file-encryption walkthrough verified:
- `SM4` file demo through the Tkinter GUI: pass
  - input sample:
    - `contest_project/demo_assets/demo_sm4_32b.bin`
  - generated output:
    - `contest_project/demo_assets/demo_sm4_32b.bin.sm4.bin`
  - expected reference:
    - `contest_project/demo_assets/expected_sm4_32b.bin`
- `AES` file demo through the Tkinter GUI: pass
  - input sample:
    - `contest_project/demo_assets/demo_aes_32b.bin`
  - generated output:
    - `contest_project/demo_assets/demo_aes_32b.bin.aes.bin`
  - expected reference:
    - `contest_project/demo_assets/expected_aes_32b.bin`
- result:
  - both generated files matched their expected ciphertext references exactly

## Relation to the Original Project

This repository is the trimmed `RX50T` pure-`PL` contest branch extracted from a much larger original project.
It no longer tries to carry the original `Zynq + ARM + DMA + DDR` heterogeneous system.
