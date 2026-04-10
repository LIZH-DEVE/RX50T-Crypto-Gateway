# Day 11

## Goal

Extend the GUI/demo layer so the new `128B` block-stream capability is represented by real demo assets and verified through the same worker path that the GUI uses for file encryption.

## Completed

- added `128B` demo plaintext and expected ciphertext assets:
  - `contest_project/demo_assets/demo_sm4_128b.bin`
  - `contest_project/demo_assets/expected_sm4_128b.bin`
  - `contest_project/demo_assets/demo_aes_128b.bin`
  - `contest_project/demo_assets/expected_aes_128b.bin`
- confirmed the GUI quick-action layer already exposes:
  - `SM4 128B`
  - `AES 128B`
- added a protocol-layer regression test to make sure a `128B` payload is transported as a single `128B` transaction instead of being split into smaller chunks

## Verification

### Python / local

- `py -3 -m unittest test_crypto_gateway_protocol.py`
  - `15` tests passed
- `py -3 -m py_compile ...`
  - passed

### Real-board file-demo backend (`COM12`)

Verified by running the same `GatewayWorker` backend path used by the Tkinter GUI file-encryption action:

- `SM4 128B`
  - output file:
    - `demo_sm4_128b.bin.sm4.bin`
  - output `SHA256`:
    - `e42bc759150c3c028d572a6278122971748300b5f56f6a200cd077efda07439a`
  - matched `expected_sm4_128b.bin`
- `AES 128B`
  - output file:
    - `demo_aes_128b.bin.aes.bin`
  - output `SHA256`:
    - `3336e368f90f2215aefe723476d6f1a7a234ff4fd5b96f47cafa5d96653d773e`
  - matched `expected_aes_128b.bin`

## Notes

- this step does not claim that a human manually clicked every new `128B` GUI button on screen
- it does prove that the GUI-facing quick actions exist and that the shared GUI file-encryption backend path is correct for `128B` payloads on the live board

## Current Boundary

- the GUI quick actions for `128B` are available, but a fresh screenshot/video walkthrough for the `128B` buttons is still optional presentation work
- runtime key updates remain out of scope

## Next Step

- if we keep pushing the demo layer, the next clean step is a fresh recorded GUI walkthrough covering `SM4 128B / AES 128B`
- if we go back to hardware, the next clean step is extending the same block-stream structure beyond `128B`
