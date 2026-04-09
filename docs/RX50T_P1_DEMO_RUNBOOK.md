# RX50T P1 Demo Runbook

## 1. Demo Goal

This `P1` demo is meant to show a visible pure-`PL` security datapath:

`UART -> parser -> 4-rule ACL -> AES/SM4(16B/32B) -> UART + stats query`

The point is not "the board powers up". The point is that the board now behaves like a small hardware crypto/filter engine with observable results.

## 2. Board Setup

- board: `RX50T`
- serial port: `COM12`
- UART: `115200 8N1`
- clock: `Y18 / 50MHz`
- UART pins: `K1(rx) / J1(tx)`

Bitstream used for this demo:
- `contest_project/build/rx50t_uart_crypto_probe/rx50t_uart_crypto_probe_board_top_mapB_p1_multiblock.bit`

## 3. Demo Sequence

### Step 1: Query Initial Stats

```powershell
py -3 D:\FPGAhanjia\jichuangsai\contest_project\tools\send_rx50t_crypto_probe.py --port COM12 --query-stats --expect-stats 0,0,0,0,0
```

Expected:
- `53 00 00 00 00 00 0A`

Meaning:
- all counters start at zero

### Step 2: Show ACL Block

```powershell
py -3 D:\FPGAhanjia\jichuangsai\contest_project\tools\send_rx50t_crypto_probe.py --port COM12 --block-ascii XYZ
```

Expected:
- `44 0A`

Meaning:
- `X/Y/Z/W` hit the fixed ACL rules and are blocked in hardware

### Step 3: Show Single-Block SM4

```powershell
py -3 D:\FPGAhanjia\jichuangsai\contest_project\tools\send_rx50t_crypto_probe.py --port COM12 --sm4-known-vector
```

Expected:
- `68 1e df 34 d2 06 96 5e 86 b3 e9 4f 53 6e 42 46`

### Step 4: Show Single-Block AES

```powershell
py -3 D:\FPGAhanjia\jichuangsai\contest_project\tools\send_rx50t_crypto_probe.py --port COM12 --aes-known-vector
```

Expected:
- `69 c4 e0 d8 6a 7b 04 30 d8 cd b7 80 70 b4 c5 5a`

### Step 5: Show Two-Block SM4

```powershell
py -3 D:\FPGAhanjia\jichuangsai\contest_project\tools\send_rx50t_crypto_probe.py --port COM12 --sm4-two-block-vector
```

Expected:
- `68 1e df 34 d2 06 96 5e 86 b3 e9 4f 53 6e 42 46 09 32 5c 48 53 83 2d cb 93 37 a5 98 4f 67 1b 9a`

Meaning:
- `SM4` now handles two consecutive `128-bit` blocks, not just a single demo block

### Step 6: Show Two-Block AES

```powershell
py -3 D:\FPGAhanjia\jichuangsai\contest_project\tools\send_rx50t_crypto_probe.py --port COM12 --aes-two-block-vector
```

Expected:
- `69 c4 e0 d8 6a 7b 04 30 d8 cd b7 80 70 b4 c5 5a 1b 87 23 78 79 5f 4f fd 77 28 55 fc 87 ca 96 4d`

Meaning:
- `AES` also supports two consecutive `128-bit` blocks

### Step 7: Show Protocol Error Handling

```powershell
py -3 D:\FPGAhanjia\jichuangsai\contest_project\tools\send_rx50t_crypto_probe.py --port COM12 --invalid-selector
```

Expected:
- `45 0A`

Meaning:
- invalid selector does not hang the system; it falls back cleanly to an error reply

### Step 8: Query Final Stats

```powershell
py -3 D:\FPGAhanjia\jichuangsai\contest_project\tools\send_rx50t_crypto_probe.py --port COM12 --query-stats --expect-stats 5,1,2,2,1
```

Expected:
- `53 05 01 02 02 01 0A`

Meaning:
- `total = 5`
- `acl = 1`
- `aes = 2`
- `sm4 = 2`
- `err = 1`

## 4. Suggested Talking Points

- Start by saying the board is a pure-`PL` datapath and does not depend on `ARM/PS`
- Use the ACL step to show physical hardware blocking
- Use the AES/SM4 steps to show algorithm switching
- Use the two-block steps to show the bridge is beyond a single-block demo
- Use the error step to show the protocol is not fragile
- Use the final stats step to show the board is observable rather than a black box

## 5. Current Explicit Boundaries

This `P1` demo does **not** claim:
- dynamic key download
- `CBC`
- payloads longer than `32B`
- a full network protocol stack
- `DMA / DDR / PBM`

This demo does prove:
- pure-`PL` mainline works
- multi-rule ACL works
- AES/SM4 dual-mode works
- single-block and two-block encryption work
- stats query works
