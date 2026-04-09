# RX50T UART SM4 Probe Board Test

## Current Board Baseline

- Valid serial port: `COM12`
- UART: `115200 8N1`
- Clock: `Y18 / 50MHz`
- UART pins: `K1(rx) / J1(tx)`
- Probe stage: `UART -> parser -> ACL -> SM4 -> UART`

## Current Scope

- This stage uses a fixed internal SM4 test key.
- This stage accepts exactly one `16-byte` plaintext block.
- No dynamic key download is implemented here.
- No hardware padding is implemented here.
- Short ACL/error control frames such as `D\n` and `E\n` bypass SM4.

## Generated Bitstream

- `D:\FPGAhanjia\jichuangsai\contest_project\build\rx50t_uart_sm4_probe\rx50t_uart_sm4_probe.runs\impl_1\rx50t_uart_sm4_probe_board_top.bit`

## Frame Format

- `0x55`
- `LEN`
- `PAYLOAD[LEN]`

For the current SM4 path:

- `LEN` must be `0x10`
- `PAYLOAD` must be exactly `16` bytes

## Recommended Host Setup

Install dependency:

```powershell
py -3 -m pip install pyserial
```

## SM4 Known-Vector Test

```powershell
py -3 D:\FPGAhanjia\jichuangsai\contest_project\tools\send_rx50t_sm4_probe.py --port COM12 --sm4-known-vector
```

Expected:

- TX payload: `01 23 45 67 89 ab cd ef fe dc ba 98 76 54 32 10`
- RX ciphertext: `68 1e df 34 d2 06 96 5e 86 b3 e9 4f 53 6e 42 46`

## ACL Block-Bypass Test

```powershell
py -3 D:\FPGAhanjia\jichuangsai\contest_project\tools\send_rx50t_sm4_probe.py --port COM12 --block-ascii XYZ
```

Expected:

- TX: `55 03 58 59 5A`
- RX: `44 0A`

## Notes

- The current SM4 bridge is intentionally fixed-key and single-block.
- If the first payload byte hits the ACL block rule (`0x58`), the probe returns `D\n` instead of entering SM4.
- Parser or UART framing errors return `E\n`.
