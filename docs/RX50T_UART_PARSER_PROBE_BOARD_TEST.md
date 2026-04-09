# RX50T UART Parser Probe Board Test

## 当前板级基础

- 有效串口：`COM12`
- 波特率：`115200 8N1`
- 时钟：`Y18 / 50MHz`
- UART 引脚：`K1(rx) / J1(tx)`

## 已生成 bit

- `D:\FPGAhanjia\jichuangsai\contest_project\build\rx50t_uart_parser_probe\rx50t_uart_parser_probe.runs\impl_1\rx50t_uart_parser_probe_board_top.bit`

## 输出规则

- 合法帧：回传 payload，并追加换行 `0x0A`
- 非法帧：回传 `E\n`

## 帧格式

- `0x55`
- `LEN`
- `PAYLOAD[LEN]`

## 推荐测试方法

先安装依赖：

```powershell
py -3 -m pip install pyserial
```

### 合法帧测试

```powershell
py -3 D:\FPGAhanjia\jichuangsai\contest_project\tools\send_rx50t_parser_probe.py --port COM12 --ascii ABC
```

期望：

- 发送：`55 03 41 42 43`
- 返回：`41 42 43 0A`

### 非法帧测试

```powershell
py -3 D:\FPGAhanjia\jichuangsai\contest_project\tools\send_rx50t_parser_probe.py --port COM12 --invalid-zero-len
```

期望：

- 发送：`55 00`
- 返回：`45 0A`

