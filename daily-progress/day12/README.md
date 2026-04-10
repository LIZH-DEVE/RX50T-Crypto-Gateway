# Day 12

## Goal

Upgrade the GUI file-encryption path from fixed demo sizes into a real ping-pong scheduler that can handle files larger than the board-side `128B` MTU.

## Completed

- added a file-specific transport planner:
  - oversize files are sliced into `128B` chunks
  - the final short chunk is padded with `PKCS#7` up to `128B`
- kept the worker in strict ping-pong mode:
  - send one chunk
  - wait for ciphertext
  - append ciphertext
  - send the next chunk
- changed GUI throughput updates to use cumulative transport progress over elapsed time instead of per-chunk instantaneous values
- updated the GUI copy so the file panel now explains:
  - any non-empty file is accepted
  - files larger than `128B` use `128B` ping-pong chunks
  - the tail is padded automatically

## Verification

### Python / local

- `py -3 -m unittest test_crypto_gateway_protocol.py`
  - `19` tests passed
- `py -3 -m py_compile ...`
  - passed

### Fresh real-board worker check (`COM12`)

Verified by running the same `GatewayWorker` path used by the GUI:

- `SM4`
  - original size: `160B`
  - transport size: `256B`
  - `pad_bytes = 96`
  - `chunk_count = 2`
  - progress:
    - `128 / 256`
    - `256 / 256`
- `AES`
  - original size: `160B`
  - transport size: `256B`
  - `pad_bytes = 96`
  - `chunk_count = 2`
  - progress:
    - `128 / 256`
    - `256 / 256`

## Notes

- this is the first point where the GUI file path is no longer constrained to hand-prepared `16B / 32B / 128B` samples
- the current scheduling strategy still respects the board-side MTU and avoids flooding the UART link
- throughput displayed in the GUI now reflects cumulative progress through the full ping-pong loop

## Current Boundary

- the transport is still half-duplex UART, so throughput is bounded by the link itself
- the worker currently pads oversize tails to `128B` for transport simplicity
- decryption and unpadding are still out of scope

## Next Step

- if we continue on the GUI side, the next useful step is to surface chunk count / padding metadata directly in a dedicated file-demo status panel
- if we continue on the hardware side, the next useful step is extending the same block-stream structure beyond `128B`
