# RX50T UART ACL Probe Board Test

## Current Board Baseline

- Valid serial port: `COM12`
- UART: `115200 8N1`
- Clock: `Y18 / 50MHz`
- UART pins: `K1(rx) / J1(tx)`
- ACL block key: `0x58` (`'X'`)

## Generated Bitstream

- `D:\FPGAhanjia\jichuangsai\contest_project\build\rx50t_uart_acl_probe\rx50t_uart_acl_probe.runs\impl_1\rx50t_uart_acl_probe_board_top.bit`

## Probe Behavior

Frame format:

- `0x55`
- `LEN`
- `PAYLOAD[LEN]`

ACL behavior:

- If first payload byte is not `0x58`, payload passes through unchanged
- If first payload byte is `0x58`, payload is blocked and probe returns `D\n`
- Parser or UART framing errors return `E\n`

## Recommended Host Setup

Install dependency:

```powershell
py -3 -m pip install pyserial
```

## Pass-Through Test

```powershell
py -3 D:\FPGAhanjia\jichuangsai\contest_project\tools\send_rx50t_acl_probe.py --port COM12 --pass-ascii ABC
```

Expected:

- TX: `55 03 41 42 43`
- RX: `41 42 43`

## Block Test

```powershell
py -3 D:\FPGAhanjia\jichuangsai\contest_project\tools\send_rx50t_acl_probe.py --port COM12 --block-ascii XYZ
```

Expected:

- TX: `55 03 58 59 5A`
- RX: `44 0A`

## Notes

- `0x58` is the current fixed block rule for the first payload byte.
- This is the first ACL stage only. Rule count and match logic can expand later without changing the UART probe structure.
