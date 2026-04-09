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
- event log reported:
  - queued file encryption
  - `FILE SM4: 32/32 bytes (chunk 32)`
  - `FILE DONE SM4: 32 bytes -> ...demo_sm4_32b.bin.sm4.bin`

### Output File Verification

Compared:
- generated:
  - `contest_project/demo_assets/demo_sm4_32b.bin.sm4.bin`
- expected:
  - `contest_project/demo_assets/expected_sm4_32b.bin`

Result:
- the generated ciphertext matched the expected reference exactly

## Current Boundaries

Completed on Day 04:
- `SM4` GUI file-encryption real-board walkthrough
- stable demo asset set for `32B AES/SM4`

Still pending:
- explicit `AES` GUI file-encryption walkthrough to leave a generated `.aes.bin` artifact in the workspace
- longer file streaming demos beyond the current `32B` sample scale

## Conclusion

By the end of Day 04, the project no longer relied on quick-action buttons alone for GUI proof.
The file-encryption path itself has now been exercised on the real board and validated against a known-good expected ciphertext file.

The GUI is therefore no longer only an operator console.
It is now a verified demo surface for both interactive probe actions and file-based encryption demonstrations.

## Next Step

Next priority should be:
1. run and retain the `AES` GUI file-encryption walkthrough
2. optionally automate a post-encryption file check in the GUI
3. continue improving the demo flow and host-side presentation
