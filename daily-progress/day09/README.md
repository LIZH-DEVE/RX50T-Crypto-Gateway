# Day 09

## Goal

Extend the pure-`PL` crypto path from `16B/32B` into a real `64B / 4-block` continuous-encryption milestone without breaking the existing UART, ACL, and stats flow.

## Completed

- widened `contest_crypto_bridge.sv` from `32B / 2 blocks` to `64B / 4 blocks`
- upgraded the internal gather / encrypt / scatter datapath from `256-bit` staging to `512-bit`
- kept the existing protocol backward-compatible:
  - default `LEN = 16 / 32 / 64` still means `SM4`
  - explicit `AES` selector now supports:
    - `LEN = 17 / 33 / 65`
  - explicit `SM4` selector now supports:
    - `LEN = 17 / 33 / 65`
- extended the Python protocol layer with:
  - `64B` known vectors for `AES` and `SM4`
  - `64B` frame generation
  - `64B` transport chunk splitting
- extended the CLI with:
  - `--sm4-four-block-vector`
  - `--aes-four-block-vector`
- extended the GUI quick actions with:
  - `SM4 64B`
  - `AES 64B`
- fixed a latent stats bug discovered during the first `64B` board smoke:
  - aggregate `acl` stats were previously inferred by watching for byte `0x44`
  - this broke as soon as legal ciphertext happened to contain `0x44`
  - the top-level path now uses the explicit `acl_blocked` pulse exported by `contest_acl_core.sv`

## Verification

### Python / host-side

- `py -3 -m unittest D:\FPGAhanjia\jichuangsai\contest_project\tools\test_crypto_gateway_protocol.py`
  - passed (`12` tests)
- `py -3 -m py_compile ...`
  - passed

### RTL / implementation

- fresh Vivado build in an isolated output directory:
  - passed
- latest implementation results:
  - `WNS = 5.691ns`
  - `WHS = 0.048ns`
  - `DRC = 0`
  - `Slice LUTs = 6327`
  - `Slice Registers = 6238`
  - `Slice = 2411`
  - `RAMB18 = 1`

### Real-board smoke

Verified on the live `RX50T` board over `COM12`:

- `SM4 64B`: pass
- `AES 64B`: pass
- stats after the two 64B vectors:
  - `53 02 00 01 01 00 0A`
  - decoded as:
    - `total = 2`
    - `acl = 0`
    - `aes = 1`
    - `sm4 = 1`
    - `err = 0`

## Notes

- this milestone proves that the current pure-`PL` datapath is no longer limited to single-block or two-block demos
- the board now supports `16B / 32B / 64B` end-to-end encryption over the same UART protocol
- the first 64B smoke test was valuable because it exposed the old "watch for byte `0x44`" shortcut in the aggregate ACL counter path
- switching to the explicit `acl_blocked` signal made the stats path correct again without changing the user-visible UART protocol

## Current Boundary

- the current ceiling is still `64B` per frame
- this is not yet the fully streamed `1KB` continuous mode
- runtime rule updates are still out of scope
- dynamic key download remains out of scope

## Next Step

- if we stay on the hardware datapath track, the next meaningful extension is a true longer streaming mode beyond `64B`
- if we stay on the presentation track, the next meaningful extension is to surface the new `64B` quick actions through a fresh GUI real-board walkthrough
