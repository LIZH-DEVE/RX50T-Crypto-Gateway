# RX50T 当前已实现基线

## 1. 项目定位

当前 `RX50T` 版本不是原 `AX7020/Zynq` 完整异构系统的直接移植，而是针对比赛约束重新抽取出来的一条纯 `PL` 最小闭环。其核心目标是：

- 不使用 `ARM/PS`
- 不依赖 `DMA/DDR/PBM`
- 保留最能体现 FPGA 价值的硬件数据通路
- 在 `RX50T` 上完成可仿真、可综合、可上板的纯硬件演示

当前已经打通的主线为：

`UART -> parser -> ACL -> AES/SM4 -> UART`

当前 `P1` 版本在这条主线上额外加入了：

- `4` 条固定 ACL 规则
- `5` 个 8-bit 状态计数器
- 串口状态查询命令

这条主线已经具备：

- 仿真验证
- 实现收敛
- 板级串口回环验证
- 板级加密与 ACL 功能验证

## 2. 当前已确认的板级基线

- 开发板：`RX50T`
- 有效串口：`COM12`
- 串口参数：`115200 8N1`
- 时钟引脚：`Y18`
- 时钟频率：`50MHz`
- UART RX 引脚：`K1`
- UART TX 引脚：`J1`
- 复位按键：`J20`

## 3. 当前已实现模块

### 3.1 UART 接收模块

文件：

- `contest_uart_rx.sv`

功能：

- 从 PC 串口接收字节流
- 完成异步串口采样与字节恢复
- 输出 `valid + data` 形式的内部字节流

实现思路：

- 固定 `115200 8N1`
- 使用 `50MHz` 时钟分频采样
- 作为整条纯 PL 数据通路的输入边界

### 3.2 UART 发送模块

文件：

- `contest_uart_tx.sv`

功能：

- 将内部字节流重新编码为串口输出
- 向 PC 回传处理结果

实现思路：

- 固定 `115200 8N1`
- 采用 `ready/valid` 风格与上游桥接层配合
- 作为整条纯 PL 数据通路的输出边界

### 3.3 Parser 模块

文件：

- `contest_parser_core.sv`

功能：

- 完成最小帧格式解析
- 做长度合法性检查
- 提取 payload
- 给后级 ACL 与加密路径提供帧级输入

当前帧格式：

- `SOF = 0x55`
- 第二字节为 `LEN`
- 后续为 `PAYLOAD[LEN]`

实现思路：

- 使用小状态机依次完成：
  - 等待帧头
  - 读取长度
  - 逐字节输出 payload
- `LEN=0` 或超过上限时直接报错

### 3.4 ACL 模块

文件：

- `contest_acl_core.sv`

功能：

- 对解析出来的 payload 做最小规则匹配
- 命中规则时阻断
- 未命中时透传数据

当前规则：

- 固定 `4` 条阻断规则
- 当首字节匹配以下关键字时阻断并返回 `D\\n`：
  - `0x58 ('X')`
  - `0x59 ('Y')`
  - `0x5A ('Z')`
  - `0x57 ('W')`

实现思路：

- 命中规则时，停止透传原 payload
- 由内部小状态机强制发出：
  - `0x44 ('D')`
  - `0x0A ('\\n')`
- 未命中时，逐字节透传到后级

### 3.5 Crypto Bridge 模块

文件：

- `contest_crypto_bridge.sv`

功能：

- 将上游 8-bit 数据拼成 128-bit block
- 驱动 `AES/SM4` 加密核
- 将 128-bit 密文拆成 8-bit 串口输出

当前边界：

- 固定内部测试密钥
- 只支持单个 `16B` 明文块
- 不做动态密钥下发
- 不做硬件 padding
- `D\\n / E\\n` 这类短控制帧绕过加密

内部状态机：

- `S_RX_GATHER`：收集 16 个字节
- `S_ENCRYPT`：等待加密完成
- `S_TX_SCATTER`：逐字节发送密文

### 3.6 AES/SM4 算法核心

来源：

- `reference/rtl/core/crypto/`

当前已接入：

- `SM4-128`
- `AES-128`

当前使用方式：

- 均为 `128-bit` 分组
- 均为固定测试密钥
- 当前工作模式为块加密处理
- 不包含 `CBC`

### 3.7 顶层封装

文件：

- `contest_uart_crypto_probe.sv`
- `rx50t_uart_crypto_probe_top.sv`
- `rx50t_uart_crypto_probe_board_top.sv`

功能：

- 将 `UART / parser / ACL / AES/SM4 / UART` 串成完整板级主线
- 提供实际可综合、可下载、可验证的顶层
- 管理状态计数器与串口状态查询响应

### 3.8 状态计数与查询逻辑

位置：

- `contest_uart_crypto_probe.sv`

功能：

- 统计有效处理帧数
- 统计 ACL 阻断次数
- 统计 AES 加密次数
- 统计 SM4 加密次数
- 统计协议错误次数

当前计数器：

- `total`
- `acl`
- `aes`
- `sm4`
- `err`

## 4. 当前协议规则

### 默认 SM4 模式

- `LEN = 16`
- 直接将 16 字节 payload 作为 `SM4` 明文块

### 显式 AES 模式

- `LEN = 17`
- 第一个 payload 字节为模式选择符：
  - `0x41 ('A')` 表示 `AES`
- 后 16 字节作为明文块

### 显式 SM4 模式

- `LEN = 17`
- 第一个 payload 字节为：
  - `0x53 ('S')`
- 后 16 字节作为 `SM4` 明文块

### 错误与阻断返回

- 协议错误：返回 `E\\n`
- ACL 阻断：返回 `D\\n`

### 状态查询命令

- 查询帧：`55 01 3F`
- 返回格式：`53 total acl aes sm4 err 0A`
- 其中：
  - `0x53 ('S')` 表示 stats 响应头
  - `total / acl / aes / sm4 / err` 为 8-bit 计数值
  - `0x0A` 为换行结束符

## 5. 当前已完成验证

### 仿真验证通过

- `UART Echo`
- `parser probe`
- `ACL probe`
- `SM4 probe`
- `crypto probe (AES/SM4)`

### 实板验证通过

已在 `COM12` 上通过：

- `UART Echo`
- `parser`
- `ACL`
- `SM4`
- `AES`

当前实板有效结果包括：

- `SM4` 已知向量：
  - 输入：`55 10 01 23 45 67 89 ab cd ef fe dc ba 98 76 54 32 10`
  - 输出：`68 1e df 34 d2 06 96 5e 86 b3 e9 4f 53 6e 42 46`

- `AES` 已知向量：
  - 输入：`55 11 41 00 11 22 33 44 55 66 77 88 99 aa bb cc dd ee ff`
  - 输出：`69 c4 e0 d8 6a 7b 04 30 d8 cd b7 80 70 b4 c5 5a`

- `ACL` 阻断：
  - 输入：`55 03 58 59 5a`
  - 输出：`44 0a`

- `状态查询（初始）`：
  - 输入：`55 01 3f`
  - 输出：`53 00 00 00 00 00 0a`

- `状态查询（P1 功能验证后）`：
  - 在依次执行 `ACL阻断 + SM4 + AES + 非法模式` 后
  - 输入：`55 01 3f`
  - 输出：`53 03 01 01 01 01 0a`

## 6. 当前资源与实现状态

`rx50t_uart_crypto_probe_board_top` 当前实现结果：

- `WNS = 5.552ns`
- `WHS = 0.055ns`
- `DRC violations = 0`
- `Slice LUTs = 3345`
- `Slice Registers = 4266`
- `Bonded IOB = 4`
- `RAMB18 = 0`
- `DSPs = 0`

这说明当前纯 PL 主线已经在 `RX50T` 上稳定收敛。

## 7. 当前没有实现的内容

以下内容当前不属于 `RX50T` 基线：

- 动态密钥下发
- CBC
- 多块连续链式加密
- DMA / DDR / PBM
- Host/PS 控制面
- 完整 Ethernet/IP/UDP 协议栈
- 零拷贝 FastPath

## 8. 当前版本一句话总结

当前 `RX50T` 版本已经完成一条纯 `PL` 的最小闭环安全数据通路：

`UART输入 -> 帧解析 -> ACL过滤 -> AES/SM4块加密 -> UART输出`

并且该闭环已经具备仿真、实现和实板验证证据，同时支持：

- 多规则 ACL 阻断
- AES/SM4 双模式切换
- 协议错误回退
- 状态计数查询
