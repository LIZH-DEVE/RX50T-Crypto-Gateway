# Day 03

## Goal

Start the PC-side GUI layer without touching the validated pure-`PL` datapath.

The board remains the hardware engine:

`UART -> Parser -> 4-rule ACL -> AES/SM4 (16B/32B) -> UART + Stats Query`

The new goal for Day 03 is to add the first usable software instrument panel on top of that engine.

## Completed Work

### 1. Shared Python Protocol Layer

New file:
- `contest_project/tools/crypto_gateway_protocol.py`

Completed:
- extracted the UART frame format into reusable helpers
- centralized known vectors and expected ciphertext values
- added reusable `ProbeCase`, `ProbeResult`, and `StatsCounters`
- added shared helpers for:
  - frame building
  - stats parsing
  - exact serial reads
  - 16B/32B transport chunking

This removes protocol duplication between CLI scripts and the future GUI.

### 2. Background Serial Worker

New file:
- `contest_project/tools/crypto_gateway_worker.py`

Completed:
- added a dedicated worker thread for serial I/O
- separated GUI responsiveness from blocking UART transactions
- added queue-based commands for:
  - connect / disconnect
  - run one probe case
  - encrypt a file in 16B/32B chunks
- added event emission for:
  - transaction result
  - stats update
  - file progress
  - file completion
  - runtime errors

### 3. GUI MVP

New file:
- `contest_project/tools/rx50t_crypto_gui.py`

Completed:
- built a Tkinter GUI MVP
- added serial connect / disconnect controls
- added quick buttons for:
  - stats query
  - `SM4 16B`
  - `AES 16B`
  - `SM4 32B`
  - `AES 32B`
  - invalid selector
  - ACL block probe
- added live metrics area for:
  - throughput
  - last latency
  - `total / acl / aes / sm4 / err`
- added a rolling throughput chart
- added scrolling event log
- added file encryption entry point using the host chunking layer

### 4. CLI Refactor

Updated file:
- `contest_project/tools/send_rx50t_crypto_probe.py`

Completed:
- rewired the existing CLI test tool to use the shared protocol layer
- preserved the existing command-line behavior
- removed duplicated protocol constants and frame logic

### 5. Python Unit Tests

New file:
- `contest_project/tools/test_crypto_gateway_protocol.py`

Coverage added:
- frame wrapping
- empty payload rejection
- stats parsing
- stats case generation
- `32B + 16B` chunk split behavior
- AES selector framing

## Verification

### Python Unit Tests

Passed:

```powershell
py -3 -m unittest test_crypto_gateway_protocol.py
```

### Python Syntax Check

Passed:

```powershell
py -3 -m py_compile crypto_gateway_protocol.py crypto_gateway_worker.py rx50t_crypto_gui.py send_rx50t_crypto_probe.py
```

### GUI Import Smoke Test

Passed:

```powershell
py -3 -c "import rx50t_crypto_gui; print('gui-import-ok')"
```

### First Real-Board GUI Walkthrough

Passed on the real board.

Board-side baseline:
- `COM12`
- `115200 8N1`
- current `P1 Phase 2` bitstream loaded

Walkthrough sequence:
1. connect `COM12`
2. query initial stats
3. run `SM4 16B`
4. run `AES 16B`
5. run ACL block test with `XYZ`
6. run `SM4 32B`
7. run `AES 32B`
8. query final stats

Observed results:
- initial stats:
  - `53 00 00 00 00 00 0A`
- `SM4 16B`: `PASS`
- `AES 16B`: `PASS`
- ACL block:
  - `44 0A`
- `SM4 32B`: `PASS`
- `AES 32B`: `PASS`
- final stats:
  - `53 05 01 02 02 00 0A`

Meaning of final stats:
- `total = 5`
- `acl = 1`
- `aes = 2`
- `sm4 = 2`
- `err = 0`

### Demo-Polish Real-Board Check

The polished GUI layer was also rechecked on the live board after adding:
- top banner status prompts
- colored `PASS / FAIL` log lines
- red ACL warning banner
- emphasized stats boxes for `ACL / AES / SM4 / ERR`

Observed behavior:
- connect state remains stable on `COM12`
- ACL block immediately turns the banner red with a hardware-firewall style message
- successful crypto operations switch the banner back to green
- stats boxes visibly highlight active counters
- the waveform, throughput, and latency readouts continue updating correctly

## Current Boundaries

Still not completed on Day 03:
- file encryption real-board validation from the GUI path
- throughput chart calibration with long streaming runs
- richer host-side visualization beyond the current banner/log/stats polish

## Conclusion

By the end of Day 03, the project gained its first usable software instrument panel without changing the pure-`PL` hardware datapath boundary.

The GUI is no longer just a local shell.
It has already completed a first real-board walkthrough against the live `RX50T` datapath.
It has also completed a first demo-polish validation pass on the live board.

The board remains the hardware engine.
The new GUI is the first real operator console.

## Next Step

Next priority should be:
1. real-board file-encryption walkthrough from the GUI path
2. polish the GUI for demo use
3. optionally extend the hardware side with BRAM-backed ACL rules or larger streaming support
