# RX50T P1 演示脚本

## 1. 演示目标

本次 `P1` 演示要证明的不是“板子能亮起来”，而是当前 `RX50T` 版本已经具备一条可观测的纯 `PL` 安全数据通路：

`UART -> parser -> 4-rule ACL -> AES/SM4 -> UART + stats query`

## 2. 板级配置

- 开发板：`RX50T`
- 串口：`COM12`
- 参数：`115200 8N1`
- 时钟：`Y18 / 50MHz`
- UART：`K1(rx) / J1(tx)`

本轮演示使用 bit：

- `contest_project/build/rx50t_uart_crypto_probe/rx50t_uart_crypto_probe_board_top_mapB_p1_stats_acl.bit`

## 3. 演示顺序

### 第一步：查询初始状态

命令：

```powershell
py -3 D:\FPGAhanjia\jichuangsai\contest_project\tools\send_rx50t_crypto_probe.py --port COM12 --query-stats --expect-stats 0,0,0,0,0
```

预期：

- 返回 `53 00 00 00 00 00 0A`

说明：

- 当前总帧、ACL、AES、SM4、错误计数均为 `0`

### 第二步：演示 ACL 阻断

命令：

```powershell
py -3 D:\FPGAhanjia\jichuangsai\contest_project\tools\send_rx50t_crypto_probe.py --port COM12 --block-ascii XYZ
```

预期：

- 返回 `44 0A`

说明：

- 当前 `X/Y/Z/W` 会命中固定规则并被硬件阻断

### 第三步：演示 SM4 加密

命令：

```powershell
py -3 D:\FPGAhanjia\jichuangsai\contest_project\tools\send_rx50t_crypto_probe.py --port COM12 --sm4-known-vector
```

预期：

- 返回 `68 1e df 34 d2 06 96 5e 86 b3 e9 4f 53 6e 42 46`

说明：

- 证明 `SM4-128` 硬件块加密路径正常

### 第四步：演示 AES 加密

命令：

```powershell
py -3 D:\FPGAhanjia\jichuangsai\contest_project\tools\send_rx50t_crypto_probe.py --port COM12 --aes-known-vector
```

预期：

- 返回 `69 c4 e0 d8 6a 7b 04 30 d8 cd b7 80 70 b4 c5 5a`

说明：

- 证明 `AES-128` 显式模式切换与硬件块加密路径正常

### 第五步：演示协议错误处理

命令：

```powershell
py -3 D:\FPGAhanjia\jichuangsai\contest_project\tools\send_rx50t_crypto_probe.py --port COM12 --invalid-selector
```

预期：

- 返回 `45 0A`

说明：

- 非法模式选择会触发协议错误回退

### 第六步：查询最终状态

命令：

```powershell
py -3 D:\FPGAhanjia\jichuangsai\contest_project\tools\send_rx50t_crypto_probe.py --port COM12 --query-stats --expect-stats 3,1,1,1,1
```

预期：

- 返回 `53 03 01 01 01 01 0A`

含义：

- `total = 3`
- `acl = 1`
- `aes = 1`
- `sm4 = 1`
- `err = 1`

## 4. 讲解口径

演示时建议按下面的话术讲：

- 第一步先说明板子是纯 `PL` 通路，不依赖 `ARM/PS`
- 第二步展示硬件 ACL 在底层直接熔断非法流
- 第三步和第四步展示 `SM4/AES` 双算法切换
- 第五步展示协议错误不会把系统打挂，而是进入明确回退
- 第六步展示板子内部计数器不是“黑盒”，而是可被上位机读取和监控

## 5. 当前边界

本次 `P1` 演示不宣称以下能力：

- 动态密钥下发
- CBC
- 多块连续加密
- 完整网络协议栈
- DMA / DDR / PBM

当前演示只证明：

- 纯 `PL` 主线可用
- 多规则 ACL 可用
- AES/SM4 双模式可用
- 状态计数与查询可用
