# Day 01

## 当日目标

建立 `RX50T` 纯 `PL` 版最小可验证主线，并将其推进到可用于演示和文档编写的 `P1` 基线。

## 当日完成内容

### 1. 板级纯 PL 主线打通

当前主线已经形成：

`UART -> Parser -> 4-rule ACL -> AES/SM4 -> UART + Stats Query`

### 2. 串口与板级基线确认

- 开发板：`RX50T`
- 串口：`COM12`
- 串口参数：`115200 8N1`
- 时钟：`Y18 / 50MHz`
- UART：`K1 (RX) / J1 (TX)`
- 复位键：`J20`

### 3. 核心模块完成

- `contest_uart_rx.sv`
- `contest_uart_tx.sv`
- `contest_parser_core.sv`
- `contest_acl_core.sv`
- `contest_crypto_bridge.sv`
- `contest_uart_crypto_probe.sv`
- `rx50t_uart_crypto_probe_top.sv`
- `rx50t_uart_crypto_probe_board_top.sv`

### 4. P1 功能完成

- `4` 条固定 ACL 规则：`X / Y / Z / W`
- `AES-128 / SM4-128` 双模式
- 非法模式错误返回 `E\n`
- 阻断返回 `D\n`
- 状态查询命令 `55 01 3F`
- 计数器：
  - `total`
  - `acl`
  - `aes`
  - `sm4`
  - `err`

## 验证方式

### 仿真验证

已通过：

- `tb_contest_acl_core`
- `tb_contest_crypto_bridge`
- `tb_uart_crypto_probe`

### 实现验证

Vivado 构建通过，结果：

- `WNS = 5.552ns`
- `WHS = 0.055ns`
- `DRC violations = 0`
- `Slice LUTs = 3345`
- `Slice Registers = 4266`

### 实板验证

已在 `COM12` 上完成：

1. 初始状态查询：
   - 输入：`55 01 3F`
   - 输出：`53 00 00 00 00 00 0A`

2. ACL 阻断：
   - 输入：`55 03 58 59 5A`
   - 输出：`44 0A`

3. `SM4` 已知向量：
   - 输入：`55 10 01 23 45 67 89 AB CD EF FE DC BA 98 76 54 32 10`
   - 输出：`68 1E DF 34 D2 06 96 5E 86 B3 E9 4F 53 6E 42 46`

4. `AES` 已知向量：
   - 输入：`55 11 41 00 11 22 33 44 55 66 77 88 99 AA BB CC DD EE FF`
   - 输出：`69 C4 E0 D8 6A 7B 04 30 D8 CD B7 80 70 B4 C5 5A`

5. 非法模式：
   - 输入：`55 11 51 00 11 22 33 44 55 66 77 88 99 AA BB CC DD EE FF`
   - 输出：`45 0A`

6. 最终状态查询：
   - 输入：`55 01 3F`
   - 输出：`53 03 01 01 01 01 0A`

## 当前边界

当前版本仍然明确不包含：

- 动态密钥下发
- `CBC`
- 多块连续加密
- `DMA / DDR / PBM`
- `ARM/PS`
- 完整网络协议栈

## 当日结论

`RX50T` 当前版本已经不再是单模块实验，而是一条完成仿真、实现和实板闭环验证的纯 `PL` 安全数据通路基线。

它已经具备：

- 纯硬件串口输入/输出
- 轻量帧解析
- 多规则 ACL 阻断
- `AES/SM4` 双模式硬件块加密
- 状态计数与上位机查询

## 下一步

下一阶段优先在这条稳定主线上继续扩展：

1. 多块连续加密
2. 更规范的上位机协议与界面
3. 文档、架构图和演示材料进一步收口
