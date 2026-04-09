# RX50T UART Crypto Probe Board Test

## Bitstream

- `D:\FPGAhanjia\jichuangsai\contest_project\build\rx50t_uart_crypto_probe\rx50t_uart_crypto_probe.runs\impl_1\rx50t_uart_crypto_probe_board_top.bit`

## Board bring-up

- UART port: `COM12`
- UART settings: `115200 8N1`
- Clock pin: `Y18`
- UART RX pin: `K1`
- UART TX pin: `J1`

## Python dependency

```powershell
py -3 -m pip install pyserial
```

## SM4 known vector

```powershell
py -3 D:\FPGAhanjia\jichuangsai\contest_project\tools\send_rx50t_crypto_probe.py --port COM12 --sm4-known-vector
```

Expected RX:

```text
68 1e df 34 d2 06 96 5e 86 b3 e9 4f 53 6e 42 46
```

## AES known vector

```powershell
py -3 D:\FPGAhanjia\jichuangsai\contest_project\tools\send_rx50t_crypto_probe.py --port COM12 --aes-known-vector
```

Expected RX:

```text
69 c4 e0 d8 6a 7b 04 30 d8 cd b7 80 70 b4 c5 5a
```

## ACL block path

```powershell
py -3 D:\FPGAhanjia\jichuangsai\contest_project\tools\send_rx50t_crypto_probe.py --port COM12 --block-ascii XYZ
```

Expected RX:

```text
44 0a
```
