# RX50T Crypto Gateway

`RX50T Crypto Gateway` 是一个面向资源受限 FPGA 的纯 `PL` 安全数据通路原型。  
当前版本已经在 `RX50T` 开发板上打通并实板验证了以下主线：

`UART -> Parser -> 4-rule ACL -> AES/SM4 -> UART + Stats Query`

这条主线不依赖 `ARM/PS`、`DMA/DDR/PBM` 或完整网络协议栈，目标是用最小闭环证明：

- 串口输入可用
- 帧解析可用
- 硬件 ACL 阻断可用
- `AES-128 / SM4-128` 块加密可用
- 状态计数器与上位机查询可用

## 当前状态

当前 `P1` 基线已经完成：

- `4` 条固定 ACL 规则：`X / Y / Z / W`
- `AES/SM4` 双模式切换
- 协议错误回退 `E\n`
- 状态查询命令 `55 01 3F`
- `total / acl / aes / sm4 / err` 五个计数器

当前板级有效配置：

- 开发板：`RX50T`
- 串口：`COM12`
- 串口参数：`115200 8N1`
- 时钟：`Y18 / 50MHz`
- UART：`K1 (RX) / J1 (TX)`
- 复位按键：`J20`

## 仓库结构

- `contest_project/rtl/contest/`
  - 当前纯 `PL` 主线 RTL
- `contest_project/tb/contest/`
  - 对应 testbench
- `contest_project/tools/`
  - 板测/串口验证脚本
- `contest_project/scripts/`
  - Vivado 构建脚本
- `contest_project/constraints/`
  - 板级约束
- `reference/`
  - 从原始工程提炼出的算法核和参考资产
- `docs/`
  - 架构说明、当前基线、板测说明、演示脚本
- `daily-progress/`
  - 每日开发进度记录

## 文档入口

- [当前基线说明](./docs/RX50T_CURRENT_BASELINE.md)
- [架构总览](./docs/RX50T_ARCHITECTURE_OVERVIEW.md)
- [P1 演示脚本](./docs/RX50T_P1_DEMO_RUNBOOK.md)
- [每日进度索引](./daily-progress/README.md)

## 当前能力

### 已实现

- `UART Echo`
- `UART -> Parser -> UART`
- `UART -> Parser -> ACL -> UART`
- `UART -> Parser -> ACL -> SM4 -> UART`
- `UART -> Parser -> ACL -> AES/SM4 -> UART`
- `UART -> Parser -> 4-rule ACL -> AES/SM4 -> UART + Stats Query`

### 当前不做

- 动态密钥下发
- `CBC`
- 多块连续加密
- `DMA / DDR / PBM`
- `ARM/PS` 控制面
- 完整 `Ethernet/IP/UDP` 协议栈

## 快速演示

下载当前 `P1` bit 后，在 `COM12` 上运行：

```powershell
py -3 .\contest_project\tools\send_rx50t_crypto_probe.py --port COM12 --query-stats --expect-stats 0,0,0,0,0
py -3 .\contest_project\tools\send_rx50t_crypto_probe.py --port COM12 --block-ascii XYZ
py -3 .\contest_project\tools\send_rx50t_crypto_probe.py --port COM12 --sm4-known-vector
py -3 .\contest_project\tools\send_rx50t_crypto_probe.py --port COM12 --aes-known-vector
py -3 .\contest_project\tools\send_rx50t_crypto_probe.py --port COM12 --invalid-selector
py -3 .\contest_project\tools\send_rx50t_crypto_probe.py --port COM12 --query-stats --expect-stats 3,1,1,1,1
```

## 当前 P1 板测结果

已实板验证通过：

- 初始状态查询：`53 00 00 00 00 00 0A`
- ACL 阻断：`XYZ -> 44 0A`
- `SM4` 已知向量：通过
- `AES` 已知向量：通过
- 非法模式：`45 0A`
- 最终状态查询：`53 03 01 01 01 01 0A`

## 联系关系

本仓库来自更大的原始工程裁剪，但当前 GitHub 仓库只聚焦 `RX50T` 纯 `PL` 竞赛版，不再承载原始 `Zynq + ARM + DMA + DDR` 的完整异构系统。
