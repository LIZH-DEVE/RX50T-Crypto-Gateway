# Day 06

## Goal

Expand the shipped BRAM-backed ACL defaults from `4` to `8` entries and make the current rule table visible in the Python GUI without changing the board-side UART protocol.

## Completed

- expanded the compiled ACL default entries to:
  - `X`
  - `Y`
  - `Z`
  - `W`
  - `P`
  - `R`
  - `T`
  - `U`
- kept the BRAM-backed lookup structure and external board protocol unchanged
- updated the ACL unit test to cover the new default blocked keys
- extended the top-level crypto testbench with one additional default blocked-frame case
- added a GUI panel that displays the compiled ACL rule table carried by the current bitstream

## Verification

### Python / GUI

- `py_compile`: pass
- `test_crypto_gateway_protocol.py`: pass
- GUI import: pass

### RTL / Build

- `contest_acl_core` unit simulation: pass
- full `rx50t_uart_crypto_probe` build: pass
- latest implementation snapshot:
  - `WNS = 5.856ns`
  - `WHS = 0.014ns`
  - `DRC = 0`
  - `Slice LUTs = 4342`
  - `Slice Registers = 4970`
  - `BRAM = 0.5`

### Real Board Smoke

Board baseline:
- `COM12`
- `115200 8N1`

Observed:
- before `XYZ`:
  - `53 00 00 00 00 00 0A`
- `XYZ -> 44 0A`
- after `XYZ`:
  - `53 01 01 00 00 00 0A`
- before `PQR`:
  - `53 01 01 00 00 00 0A`
- `PQR -> 44 0A`
- after `PQR`:
  - `53 02 02 00 00 00 0A`

## Boundary

- the GUI now shows the compiled rule set, but it still does not edit rules at runtime
- the board image still ships a fixed ACL table baked into the bitstream
- runtime ACL rule update remains a separate future feature

## Next Step

- expose a runtime rule-update path for the BRAM rule table
- or extend the GUI to visualize ACL hit counters and per-rule activity more explicitly
