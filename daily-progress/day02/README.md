# Day 02

## Goal

Extend the stable `P1 Phase 1` baseline into a real `P1 Phase 2` version that supports two-block continuous encryption on the board.

## Completed Work

### 1. Multi-Block Mainline Added

The mainline was extended to:

`UART -> Parser -> 4-rule ACL -> AES/SM4(16B/32B) -> UART + Stats Query`

Compatibility was preserved for:
- `16B` default `SM4`
- `17B` explicit `AES/SM4`
- ACL block reply `D\n`
- protocol error reply `E\n`
- stats query `55 01 3F`

### 2. Crypto Bridge Extended

Core file:
- `contest_crypto_bridge.sv`

Main changes:
- gather depth expanded to `32B`
- result path expanded to two blocks
- scatter path expanded to `32` ciphertext bytes
- fixed AES two-block result reuse issue
- added `SM4 done-clear` handling to stabilize block-to-block handoff on real hardware

### 3. Top-Level Protocol Extended

Files:
- `contest_uart_crypto_probe.sv`
- `tb_uart_crypto_probe.sv`
- `send_rx50t_crypto_probe.py`

New supported modes:
- `LEN = 32` default two-block `SM4`
- `LEN = 33 + 'A'` explicit two-block `AES`
- `LEN = 33 + 'S'` explicit two-block `SM4`

## Verification

### Simulation

Passed:
- `tb_contest_crypto_bridge`
- `tb_uart_crypto_probe`

Coverage includes:
- ACL block
- single-block `SM4`
- single-block `AES`
- two-block `SM4`
- two-block `AES`
- invalid selector
- stats query

### Implementation

Bitstream:
- `contest_project/build/rx50t_uart_crypto_probe/rx50t_uart_crypto_probe_board_top_mapB_p1_multiblock.bit`

Implementation results:
- `WNS = 4.796ns`
- `WHS = 0.074ns`
- `DRC violations = 0`
- `Slice LUTs = 4317`
- `Slice Registers = 4926`

### Real Board

Board baseline unchanged:
- `COM12`
- `115200 8N1`
- `Y18 / 50MHz`
- `K1 (RX) / J1 (TX)`

Verified:

1. `SM4` two-block vector
   - input:
     `55 20 01 23 45 67 89 ab cd ef fe dc ba 98 76 54 32 10 00 11 22 33 44 55 66 77 88 99 aa bb cc dd ee ff`
   - output:
     `68 1e df 34 d2 06 96 5e 86 b3 e9 4f 53 6e 42 46 09 32 5c 48 53 83 2d cb 93 37 a5 98 4f 67 1b 9a`

2. `AES` two-block vector
   - input:
     `55 21 41 00 11 22 33 44 55 66 77 88 99 aa bb cc dd ee ff ff ee dd cc bb aa 99 88 77 66 55 44 33 22 11 00`
   - output:
     `69 c4 e0 d8 6a 7b 04 30 d8 cd b7 80 70 b4 c5 5a 1b 87 23 78 79 5f 4f fd 77 28 55 fc 87 ca 96 4d`

3. stats query after isolated `32B SM4` retest
   - input:
     `55 01 3F`
   - output:
     `53 01 00 00 01 00 0A`
   - meaning:
     the `sm4` path increments cleanly on the updated multiblock bit

## Current Boundaries

Still not implemented:
- dynamic key download
- `CBC`
- payloads longer than `32B`
- `DMA / DDR / PBM`
- `ARM/PS`
- full network protocol stack

## Conclusion

By the end of Day 02, the design had moved from a single-block crypto demo to a pure-`PL` datapath that can process two consecutive `128-bit` blocks on real hardware.

## Next Step

Next priority should be one of:
1. stronger system presentation through host GUI, throughput display, and logs
2. lock down `P1 Phase 2` as the stable contest demo release
