# Day 05

## Goal

Upgrade the `ACL` stage from hardcoded combinational rules to a BRAM-backed rule table without breaking the validated `UART -> parser -> ACL -> AES/SM4 -> UART + stats` mainline.

## Completed

- rewrote `contest_acl_core.sv` to use a BRAM-backed lookup table
- kept the shipped default blocked entries as:
  - `X`
  - `Y`
  - `Z`
  - `W`
- updated the top-level stats path so ACL accounting follows the actual ACL output behavior instead of a duplicated hardcoded key list
- added shadow feed registers ahead of the ACL stage to keep the BRAM path clean in implementation
- changed the ACL control path to synchronous reset and removed the remaining BRAM-related DRC issue

## Verification

### Unit / RTL

- `contest_acl_core` unit simulation: pass
- full `rx50t_uart_crypto_probe` build: pass

### Implementation

- `DRC = 0`
- `WNS = 5.856ns`
- `WHS = 0.014ns`
- `Slice LUTs = 4342 / 32600 = 13.32%`
- `Slice Registers = 4970 / 65200 = 7.62%`
- `Slice = 1676 / 8150 = 20.56%`
- `BRAM = 0.5 / 75 = 0.67%`
- `DSP = 0 / 120 = 0%`

### Real Board Smoke Test

Board baseline:
- `COM12`
- `115200 8N1`

Fresh smoke results:
- initial stats query:
  - `53 00 00 00 00 00 0A`
- `SM4 16B`: pass
- `AES 16B`: pass
- ACL block:
  - `XYZ -> 44 0A`
- final stats query:
  - `53 02 01 00 01 00 0A`

## Boundary

- the board image proves the BRAM-backed ACL implementation does not regress the validated mainline
- current shipped rules are still fixed at synthesis time
- there is still no UART-side runtime rule update path
- top-level manual standalone `xsim` remains awkward because of an unrelated legacy reference RTL compile quirk, but the Vivado project build and real-board smoke test both passed

## Next Step

- either expose a runtime ACL rule update path
- or expand the shipped BRAM rule table and document its layout more formally
