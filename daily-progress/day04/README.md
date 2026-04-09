# Day 04

## Goal

Close the loop on the GUI demo path by proving that file encryption from the Tkinter interface works against the live `RX50T` board, not just through CLI probe scripts.

## Completed Work

### 1. GUI File-Encryption Real-Board Walkthrough

Validated the GUI file-encryption path against the live board on:
- `COM12`
- `115200 8N1`

Completed path:
- open the GUI
- connect to `COM12`
- choose `SM4`
- select `contest_project/demo_assets/demo_sm4_32b.bin`
- let the GUI chunk and send the file over UART
- receive ciphertext back from the board
- write the encrypted file to disk

Repeated for:
- `AES`
- input file:
  - `contest_project/demo_assets/demo_aes_32b.bin`

### 2. Demo Assets Formalized

Prepared reusable demo files under:
- `contest_project/demo_assets/demo_sm4_32b.bin`
- `contest_project/demo_assets/demo_aes_32b.bin`
- `contest_project/demo_assets/expected_sm4_32b.bin`
- `contest_project/demo_assets/expected_aes_32b.bin`

These files now serve as the stable sample inputs and expected outputs for future GUI and CLI demonstrations.

## Verification

### GUI Runtime Evidence

Observed in the GUI:
- top banner reported:
  - `File encryption finished: demo_sm4_32b.bin.sm4.bin`
  - `File encryption finished: demo_aes_32b.bin.aes.bin`
- event log reported:
  - queued file encryption
  - `FILE SM4: 32/32 bytes (chunk 32)`
  - `FILE DONE SM4: 32 bytes -> ...demo_sm4_32b.bin.sm4.bin`
  - `FILE AES: 32/32 bytes (chunk 32)`
  - `FILE DONE AES: 32 bytes -> ...demo_aes_32b.bin.aes.bin`

### Output File Verification

Compared:
- generated:
  - `contest_project/demo_assets/demo_sm4_32b.bin.sm4.bin`
  - `contest_project/demo_assets/demo_aes_32b.bin.aes.bin`
- expected:
  - `contest_project/demo_assets/expected_sm4_32b.bin`
  - `contest_project/demo_assets/expected_aes_32b.bin`

Result:
- both generated ciphertext files matched their expected references exactly

## Current Boundaries

Completed on Day 04:
- `SM4` GUI file-encryption real-board walkthrough
- `AES` GUI file-encryption real-board walkthrough
- stable demo asset set for `32B AES/SM4`

Still pending:
- longer file streaming demos beyond the current `32B` sample scale
- optional automatic post-encryption binary comparison inside the GUI

## Conclusion

By the end of Day 04, the project no longer relied on quick-action buttons alone for GUI proof.
The file-encryption path itself has now been exercised on the real board for both `SM4` and `AES`, and both outputs were validated against known-good expected ciphertext files.

The GUI is therefore no longer only an operator console.
It is now a verified demo surface for both interactive probe actions and file-based encryption demonstrations.

## Next Step

Next priority should be:
1. optionally automate a post-encryption file check in the GUI
2. continue improving the demo flow and host-side presentation
3. extend the same GUI path to larger streaming runs
