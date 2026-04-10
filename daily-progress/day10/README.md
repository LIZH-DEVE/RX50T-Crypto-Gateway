# Day 10

## Goal

Finish the refactor from a bounded wide-register multiblock bridge into a BRAM-backed block-stream crypto bridge, then close the loop with fresh `128B` real-board evidence.

## Completed

- added a dedicated block FIFO:
  - `contest_block_fifo.sv`
- refactored `contest_crypto_bridge.sv` into a block-stream structure:
  - `16B` packer
  - BRAM-backed ingress FIFO
  - single-block `AES/SM4` worker
  - BRAM-backed egress FIFO
  - UART byte scatter
- converted the bridge-side FIFO control to synchronous-reset style so BRAM control ports no longer inherit the old async-reset DRC issues
- kept the current user-visible protocol compatible while extending the verified path to:
  - `16B`
  - `32B`
  - `64B`
  - `128B`

## Verification

### Simulation

- `tb_contest_block_fifo.sv`: pass
- `tb_contest_crypto_bridge.sv`: pass
- `tb_uart_crypto_probe.sv`: pass, including:
  - ACL block
  - `SM4 16B / 32B / 64B / 128B`
  - `AES 16B / 32B / 64B / 128B`
  - dynamic rule-counter query
  - aggregate stats query

### Python / host-side

- protocol unit tests: `14` passed
- `py_compile`: passed

### Fresh build

- `DRC = 0`
- `WNS = 6.199ns`
- `WHS = 0.031ns`
- `Slice LUTs = 3432`
- `Slice Registers = 4702`
- `Slice = 1580`
- `RAMB36E1 = 4`
- `RAMB18E1 = 1`
- `DSP = 0`

### Fresh real-board smoke (`COM12`)

- initial stats query:
  - `53 00 00 00 00 00 0A`
- `SM4 128B`: pass
- `AES 128B`: pass
- final stats query:
  - `53 02 00 01 01 00 0A`

## Notes

- this milestone matters because the datapath is no longer being scaled by blindly widening whole-frame staging registers
- the large FF-heavy multiblock staging path has been replaced by BRAM-backed block FIFOs plus a single-block worker
- the post-refactor implementation numbers confirm the change:
  - the bridge is now BRAM-heavy instead of register-heavy

## Current Boundary

- the current path is now fairly described as a `BRAM-backed block-stream bridge`
- it is still UART-framed and fixed-key
- runtime key updates are still out of scope
- payloads longer than `128B` are not yet enabled

## Next Step

- if we continue on the hardware side, the next meaningful step is to extend the same block-stream structure beyond `128B` without changing the datapath width
- if we continue on the demo side, the next meaningful step is to surface `128B` actions through the GUI and verify them on the live board
