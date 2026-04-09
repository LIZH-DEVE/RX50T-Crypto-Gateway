# Day 01

## Goal

Build the first stable pure-`PL` baseline on `RX50T` and push it far enough to support both board demonstration and technical documentation.

## Completed Work

### 1. Mainline Closed Loop

The first complete mainline was established:

`UART -> Parser -> 4-rule ACL -> AES/SM4 -> UART + Stats Query`

### 2. Board Baseline Confirmed

- board: `RX50T`
- serial port: `COM12`
- UART: `115200 8N1`
- clock: `Y18 / 50MHz`
- UART pins: `K1 (RX) / J1 (TX)`
- reset key: `J20`

### 3. Core Modules Completed

- `contest_uart_rx.sv`
- `contest_uart_tx.sv`
- `contest_parser_core.sv`
- `contest_acl_core.sv`
- `contest_crypto_bridge.sv`
- `contest_uart_crypto_probe.sv`
- `rx50t_uart_crypto_probe_top.sv`
- `rx50t_uart_crypto_probe_board_top.sv`

### 4. P1 Phase 1 Features Completed

- `4` fixed ACL rules: `X / Y / Z / W`
- `AES-128 / SM4-128`
- invalid selector fallback `E\n`
- ACL block fallback `D\n`
- stats query command `55 01 3F`
- counters:
  - `total`
  - `acl`
  - `aes`
  - `sm4`
  - `err`

## Verification

### Simulation

Passed:
- `tb_contest_acl_core`
- `tb_contest_crypto_bridge`
- `tb_uart_crypto_probe`

### Implementation

Vivado build passed with:
- `WNS = 5.552ns`
- `WHS = 0.055ns`
- `DRC violations = 0`
- `Slice LUTs = 3345`
- `Slice Registers = 4266`

### Real Board

Verified on `COM12`:

1. initial stats query
   - input: `55 01 3F`
   - output: `53 00 00 00 00 00 0A`

2. ACL block
   - input: `55 03 58 59 5A`
   - output: `44 0A`

3. `SM4` known vector
   - input: `55 10 01 23 45 67 89 AB CD EF FE DC BA 98 76 54 32 10`
   - output: `68 1E DF 34 D2 06 96 5E 86 B3 E9 4F 53 6E 42 46`

4. `AES` known vector
   - input: `55 11 41 00 11 22 33 44 55 66 77 88 99 AA BB CC DD EE FF`
   - output: `69 C4 E0 D8 6A 7B 04 30 D8 CD B7 80 70 B4 C5 5A`

5. invalid selector
   - input: `55 11 51 00 11 22 33 44 55 66 77 88 99 AA BB CC DD EE FF`
   - output: `45 0A`

6. final stats query
   - input: `55 01 3F`
   - output: `53 03 01 01 01 01 0A`

## Current Boundaries

Not included in the baseline:
- dynamic key download
- `CBC`
- multi-block continuous encryption
- `DMA / DDR / PBM`
- `ARM/PS`
- full network protocol stack

## Conclusion

The `RX50T` version was no longer a set of isolated module experiments by the end of Day 01.
It had become a real pure-`PL` closed loop with simulation, implementation, and board evidence.

## Next Step

Priority for the next stage:
1. multi-block continuous encryption
2. stronger host-side protocol and demo tooling
3. tighter architecture and demo documentation
