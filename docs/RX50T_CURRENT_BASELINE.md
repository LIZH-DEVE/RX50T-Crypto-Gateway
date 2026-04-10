# RX50T Current Baseline

## 1. Project Positioning

The current `RX50T` version is not a direct port of the original `AX7020/Zynq` heterogeneous system.
It is a deliberately trimmed pure-`PL` branch built for a resource-constrained FPGA contest workflow.

Design goals:
- no `ARM/PS`
- no `DMA/DDR/PBM`
- keep only the highest-value hardware datapath
- maintain a clean real-board demonstration path

The current validated mainline is:

`UART -> Parser -> 8-rule BRAM-backed ACL -> BRAM-backed block-stream AES/SM4 (16B/32B/64B/128B) -> UART + Stats Query + Rule-Stats Query`

`P1` extends that path with:
- a BRAM-backed ACL rule table
- current default ACL entries: `8`
- `5` `8-bit` status counters
- `8` `8-bit` per-rule ACL hardware counters
- stats query over UART
- rule-stats query over UART
- `16B / 32B / 64B / 128B` BRAM-backed block-stream encryption

This mainline now has:
- simulation evidence
- implementation evidence
- real-board evidence

The current system boundary is:
- board-side pure `PL` datapath
- PC-side Python tools for testing, observability, and GUI demo

The GUI MVP has already completed a first real-board walkthrough over the live UART link.

## 2. Board Baseline

- board: `RX50T`
- serial port: `COM12`
- UART: `115200 8N1`
- clock pin: `Y18`
- clock frequency: `50MHz`
- UART RX pin: `K1`
- UART TX pin: `J1`
- reset key: `J20`

## 3. Current Implemented Modules

### 3.1 UART RX

File:
- `contest_uart_rx.sv`

Purpose:
- receive bytes from the PC UART
- convert asynchronous serial input into an internal byte stream

### 3.2 UART TX

File:
- `contest_uart_tx.sv`

Purpose:
- send processed bytes back to the PC
- provide a simple UART egress for every stage of the pipeline

### 3.3 Parser

File:
- `contest_parser_core.sv`

Purpose:
- detect frame header
- read payload length
- output payload byte stream
- generate `frame_done` and `error`

Current frame format:
- `SOF = 0x55`
- second byte = `LEN`
- followed by `PAYLOAD[LEN]`

### 3.4 ACL

File:
- `contest_acl_core.sv`

Purpose:
- apply minimal rule matching on parsed payload bytes
- block illegal frames
- pass legal frames downstream

Current implementation:
- rules are stored in a BRAM-backed lookup table
- the current match key is the first payload byte of each frame
- the shipped default initialized entries block:
  - `0x58 ('X')`
  - `0x59 ('Y')`
  - `0x5A ('Z')`
  - `0x57 ('W')`
  - `0x50 ('P')`
  - `0x52 ('R')`
  - `0x54 ('T')`
  - `0x55 ('U')`

Block response:
- `D\n`

### 3.5 Crypto Bridge

File:
- `contest_crypto_bridge.sv`

Purpose:
- gather `8-bit` bytes into `128-bit` blocks
- drive the AES/SM4 core
- scatter ciphertext back into `8-bit` UART bytes

Current boundary:
- fixed internal test keys
- supports `16B`, `32B`, `64B`, and `128B` payload paths
- no dynamic key download
- no hardware padding
- short control frames like `D\n` and `E\n` bypass encryption

Internal phases:
- pack incoming bytes into one `128-bit` block at a time
- push plaintext blocks into a BRAM-backed ingress FIFO
- drive a single-block `AES/SM4` worker
- push ciphertext blocks into a BRAM-backed egress FIFO
- emit ciphertext one byte at a time from the egress FIFO under UART backpressure

### 3.6 AES/SM4 Cores

Source:
- `reference/rtl/core/crypto/`

Currently integrated:
- `AES-128`
- `SM4-128`

Current mode:
- `128-bit` block processing
- fixed internal test key
- no `CBC`

### 3.7 Top-Level Integration

Files:
- `contest_uart_crypto_probe.sv`
- `rx50t_uart_crypto_probe_top.sv`
- `rx50t_uart_crypto_probe_board_top.sv`

Purpose:
- integrate `UART / parser / ACL / AES/SM4 / UART`
- produce a real synthesizable and downloadable board top
- host counters and UART stats reply logic

### 3.8 Stats and Query Logic

Location:
- `contest_uart_crypto_probe.sv`

Counters:
- `total`
- `acl`
- `aes`
- `sm4`
- `err`

Purpose:
- count valid processed frames
- count ACL hits
- count AES invocations
- count SM4 invocations
- count protocol errors

## 4. Current Protocol Rules

### Default SM4 Mode

- `LEN = 16`
- payload is one `SM4` plaintext block

- `LEN = 32`
- payload is two consecutive `SM4` plaintext blocks

- `LEN = 64`
- payload is four consecutive `SM4` plaintext blocks

- `LEN = 128`
- payload is eight consecutive `SM4` plaintext blocks

### Explicit AES Mode

- `LEN = 17`
- first payload byte = `0x41 ('A')`
- remaining `16B` = one AES plaintext block

- `LEN = 33`
- first payload byte = `0x41 ('A')`
- remaining `32B` = two consecutive AES plaintext blocks

- `LEN = 65`
- first payload byte = `0x41 ('A')`
- remaining `64B` = four consecutive AES plaintext blocks

- `LEN = 129`
- first payload byte = `0x41 ('A')`
- remaining `128B` = eight consecutive AES plaintext blocks

### Explicit SM4 Mode

- `LEN = 17`
- first payload byte = `0x53 ('S')`
- remaining `16B` = one SM4 plaintext block

- `LEN = 33`
- first payload byte = `0x53 ('S')`
- remaining `32B` = two consecutive SM4 plaintext blocks

- `LEN = 65`
- first payload byte = `0x53 ('S')`
- remaining `64B` = four consecutive SM4 plaintext blocks

- `LEN = 129`
- first payload byte = `0x53 ('S')`
- remaining `128B` = eight consecutive SM4 plaintext blocks

### Error and Block Replies

- ACL block response: `D\n`
- protocol error response: `E\n`

### Stats Query Command

- query frame: `55 01 3F`
- response format: `53 total acl aes sm4 err 0A`

### Rule-Stats Query Command

- query frame: `55 01 48`
- response format: `48 x y z w p r t u 0A`

Returned rule order:
- `X`
- `Y`
- `Z`
- `W`
- `P`
- `R`
- `T`
- `U`

## 5. Verification Status

### Simulation

Verified:
- `UART Echo`
- `parser probe`
- `ACL probe`
- `BRAM-backed ACL core`
- `SM4 probe`
- `crypto probe (AES/SM4)`
- `two-block AES/SM4`
- `four-block AES/SM4`
- `eight-block AES/SM4`

### Real Board

Verified on `COM12`:
- `UART Echo`
- `parser`
- `ACL`
- `SM4`
- `AES`
- `32B SM4`
- `32B AES`
- `64B SM4`
- `64B AES`
- `128B SM4`
- `128B AES`
- latest BRAM-backed ACL smoke test

Representative real-board results:

- `SM4` known vector
  - input: `55 10 01 23 45 67 89 ab cd ef fe dc ba 98 76 54 32 10`
  - output: `68 1e df 34 d2 06 96 5e 86 b3 e9 4f 53 6e 42 46`

- `AES` known vector
  - input: `55 11 41 00 11 22 33 44 55 66 77 88 99 aa bb cc dd ee ff`
  - output: `69 c4 e0 d8 6a 7b 04 30 d8 cd b7 80 70 b4 c5 5a`

- `SM4` two-block vector
  - input: `55 20 01 23 45 67 89 ab cd ef fe dc ba 98 76 54 32 10 00 11 22 33 44 55 66 77 88 99 aa bb cc dd ee ff`
  - output: `68 1e df 34 d2 06 96 5e 86 b3 e9 4f 53 6e 42 46 09 32 5c 48 53 83 2d cb 93 37 a5 98 4f 67 1b 9a`

- `AES` two-block vector
  - input: `55 21 41 00 11 22 33 44 55 66 77 88 99 aa bb cc dd ee ff ff ee dd cc bb aa 99 88 77 66 55 44 33 22 11 00`
  - output: `69 c4 e0 d8 6a 7b 04 30 d8 cd b7 80 70 b4 c5 5a 1b 87 23 78 79 5f 4f fd 77 28 55 fc 87 ca 96 4d`

- `SM4` four-block vector
  - input: `55 40 01 23 45 67 89 ab cd ef fe dc ba 98 76 54 32 10 00 11 22 33 44 55 66 77 88 99 aa bb cc dd ee ff 01 23 45 67 89 ab cd ef fe dc ba 98 76 54 32 10 00 11 22 33 44 55 66 77 88 99 aa bb cc dd ee ff`
  - output: `68 1e df 34 d2 06 96 5e 86 b3 e9 4f 53 6e 42 46 09 32 5c 48 53 83 2d cb 93 37 a5 98 4f 67 1b 9a 68 1e df 34 d2 06 96 5e 86 b3 e9 4f 53 6e 42 46 09 32 5c 48 53 83 2d cb 93 37 a5 98 4f 67 1b 9a`

- `AES` four-block vector
  - input: `55 41 41 00 11 22 33 44 55 66 77 88 99 aa bb cc dd ee ff ff ee dd cc bb aa 99 88 77 66 55 44 33 22 11 00 00 11 22 33 44 55 66 77 88 99 aa bb cc dd ee ff ff ee dd cc bb aa 99 88 77 66 55 44 33 22 11 00`
  - output: `69 c4 e0 d8 6a 7b 04 30 d8 cd b7 80 70 b4 c5 5a 1b 87 23 78 79 5f 4f fd 77 28 55 fc 87 ca 96 4d 69 c4 e0 d8 6a 7b 04 30 d8 cd b7 80 70 b4 c5 5a 1b 87 23 78 79 5f 4f fd 77 28 55 fc 87 ca 96 4d`

- initial stats query
  - input: `55 01 3F`
  - output: `53 00 00 00 00 00 0A`

- final `P1 Phase 2` stats query
  - after: `ACL block + SM4 + AES + 32B SM4 + 32B AES + invalid selector`
  - input: `55 01 3F`
  - output: `53 05 01 02 02 01 0A`

- fresh `64B` multiblock stats query
  - after: `64B SM4 + 64B AES`
  - input: `55 01 3F`
  - output: `53 02 00 01 01 00 0A`

- fresh BRAM-backed ACL smoke test
  - initial stats:
    - `53 00 00 00 00 00 0A`
  - `SM4 16B`: pass
  - `AES 16B`: pass
  - ACL block:
    - `XYZ -> 44 0A`
  - final stats:
    - `53 02 01 00 01 00 0A`

### GUI File-Encryption Walkthrough

Verified on the real board through the Tkinter GUI path:
- `SM4`
  - input file:
    - `contest_project/demo_assets/demo_sm4_32b.bin`
  - output file:
    - `contest_project/demo_assets/demo_sm4_32b.bin.sm4.bin`
  - expected reference:
    - `contest_project/demo_assets/expected_sm4_32b.bin`
- `AES`
  - input file:
    - `contest_project/demo_assets/demo_aes_32b.bin`
  - output file:
    - `contest_project/demo_assets/demo_aes_32b.bin.aes.bin`
  - expected reference:
    - `contest_project/demo_assets/expected_aes_32b.bin`

Observed result:
- the GUI completed both file-encryption runs
- both output files remained `32B`
- both generated ciphertext files matched their expected references exactly

### GUI ACL Rule-Table Display

The Tkinter GUI now shows the compiled ACL rule table directly in the control panel.

Current displayed blocked keys:
- `X`
- `Y`
- `Z`
- `W`
- `P`
- `R`
- `T`
- `U`

This is a display-only reflection of the current shipped bitstream defaults.
It is not yet a runtime rule-update interface.

### Board-Side ACL Rule Counters and GUI Hot Rule

The board now keeps per-rule ACL hit counters in hardware for the shipped default rule table.
The GUI can query those counters and highlight the current hot rule.

Current behavior:
- the query command `55 01 48` returns `H x y z w p r t u \n`
- the GUI `Query Rule Hits` action refreshes the on-board counters
- blocked keys with non-zero hardware hits are highlighted
- the GUI surfaces a `Hot Rule` summary for the most frequently blocked hardware rule
- after an ACL block event, the GUI schedules a short delayed rule-counter refresh so the board-side values catch up cleanly before repainting

This remains a read-only presentation and observability feature.
It does not expose runtime ACL table writes.

## 6. Current Implementation Numbers

`rx50t_uart_crypto_probe_board_top` implementation results:
- `WNS = 6.199ns`
- `WHS = 0.031ns`
- `DRC violations = 0`
- `Slice LUTs = 3432`
- `Slice Registers = 4702`
- `Slice = 1580`
- `Bonded IOB = 4`
- `RAMB36 = 4`
- `RAMB18 = 1`
- `DSPs = 0`

## 7. Fresh Expanded ACL Smoke Test

The latest real-board check also verified one of the newly added default ACL entries.

Observed on `COM12` with short host-side spacing between frames:
- before `XYZ`:
  - `53 00 00 00 00 00 0A`
- `XYZ` block:
  - `44 0A`
- after `XYZ`:
  - `53 01 01 00 00 00 0A`
- before `PQR`:
  - `53 01 01 00 00 00 0A`
- `PQR` block:
  - `44 0A`
- after `PQR`:
  - `53 02 02 00 00 00 0A`

## 8. Fresh Board-Side Rule-Counter Smoke Test

In a persistent UART session on the live board, rule counters were verified by observing the delta before and after two blocked frames.

Observed with a short host-side settle between blocked frames:

- before:
  - `X=1, P=0`
- `XYZ -> 44 0A`
- `PQR -> 44 0A`
- after:
  - `X=2, P=1`
- observed delta:
  - `X:+1`
  - `P:+1`

This is why the GUI now schedules a short delayed rule-counter refresh after ACL block events instead of querying the hardware counters immediately.

## 9. Current Explicit Non-Goals

Not part of the current baseline:
- dynamic key download
- `CBC`
- payloads longer than `128B`
- `DMA / DDR / PBM`
- `Host/PS`
- full `Ethernet/IP/UDP` stack
- zero-copy fast path

## 10. One-Line Summary

The current `RX50T` version is now a real pure-`PL` security datapath with verified evidence for:

`UART input -> frame parsing -> ACL filtering -> AES/SM4 block encryption -> UART output`

and it already supports:
- multi-rule ACL
- AES/SM4 mode switching
- `16B / 32B / 64B / 128B` BRAM-backed block-stream encryption
- protocol error fallback
- aggregate stats query and counter readback
- board-side per-rule ACL counter readback
