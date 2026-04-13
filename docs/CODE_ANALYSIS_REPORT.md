# RX50T FPGA 仓库已实现功能分析报告

> 修订日期：2026-04-13
> 分析范围：所有源代码文件（已排除 README 和 TB 文件）
> 本报告基于代码实际实现状态，已对照 TCL 构建脚本和主线数据通路验证

---

## 一、系统总体架构

本仓库是一个基于 Xilinx Artix-7 (xc7a50tfgg484-1) FPGA 的 **UART 加密网关系统**，采用分层模块化设计，通过 UART 串口接收数据帧，执行协议解析、访问控制列表（ACL）过滤和加密运算，最后将结果通过 UART 返回。系统存在 **5 个独立的顶层配置（Probe）**，对应不同功能阶段。

### 当前主线架构（Crypto Probe）

```
Board Top → Probe Top → Probe Core → [Parser → Protocol Dispatcher → ACL AXIS Core → Packer → Crypto Block Engine → Unpacker → TX Mux → UART TX]
```

> **关键区别**：当前主线 Crypto Probe 的密码数据通路走的是 `contest_crypto_axis_core`（内含 `contest_acl_axis_core` + `contest_axis_block_packer` + `contest_crypto_block_engine` + `contest_axis_block_unpacker`），而非旧的 `contest_acl_core` + `contest_crypto_bridge` 直连路径。旧模块仍保留在仓库中，供 Legacy Probe 与对应单元测试使用，但不再属于主线 `crypto probe` 工程的默认源文件集合。

### Legacy Probe 架构（ACL / SM4 Probe）

```
Board Top → Probe Top → Probe Core → [Parser → ACL Core → Crypto Bridge(SM4 only) → UART TX]
```

> ACL Probe 和 SM4 Probe 仍使用 `contest_acl_core` + `contest_crypto_bridge` 的旧路径。这些是独立的功能验证探针，不是主线。

---

## 二、已确认的核心模块与功能

### 1. UART 通信层

#### contest_uart_rx.sv
- **功能**：UART 接收器
- **实现细节**：
  - 可参数化时钟频率（`CLK_HZ`）和波特率（`BAUD`），默认 50MHz/115200
  - 4 状态 FSM：`ST_IDLE → ST_START → ST_DATA → ST_STOP`
  - 双级同步器（`rx_meta_q → rx_sync_q`）消除亚稳态
  - 半位周期起始位验证
  - 8 位数据 LSB 优先接收
  - 帧错误检测（停止位不为1时置位 `o_frame_error`）

#### contest_uart_tx.sv
- **功能**：UART 发送器
- **实现细节**：
  - 可参数化时钟频率和波特率
  - 4 状态 FSM：`ST_IDLE → ST_START → ST_DATA → ST_STOP`
  - 8 位数据 LSB 优先发送
  - 握手协议：`i_valid/i_data → o_ready`
  - 空闲时 TX 线保持高电平

#### contest_uart_fifo.sv
- **功能**：8 位宽同步 FIFO
- **实现细节**：
  - 可参数化深度（默认16）
  - 读写指针 + 计数器管理
  - 满空标志（`o_full/o_empty`）
  - 溢出/下溢检测（`o_overflow/o_underflow`）
  - 同时读写支持（case 2'b11 同时推进读写指针）

#### contest_uart_io.sv
- **功能**：UART 回环 I/O 聚合模块
- **实现细节**：
  - 集成 `contest_uart_rx` + `contest_uart_fifo` + `contest_uart_tx`
  - 接收字节自动入 FIFO，TX 空闲时自动从 FIFO 读取发送
  - 调试输出：`o_last_rx_byte`, `o_last_tx_byte`, `o_rx_pulse`, `o_tx_pulse`, `o_frame_error`, `o_overrun`

---

### 2. 协议解析层

#### contest_parser_core.sv
- **功能**：自定义帧协议解析器
- **实现细节**：
  - 帧格式：`[SOF(0x55)] [LEN] [PAYLOAD_0..PAYLOAD_N-1]`
  - 可参数化 SOF 字节（默认 0x55）、最大负载长度（默认32字节）
  - 3 状态 FSM：`ST_IDLE → ST_WAIT_LEN → ST_WAIT_DATA`
  - **帧间超时机制**（`INTERBYTE_TIMEOUT_CLKS` 参数）：当启用时，若帧内字节间隔超过阈值，自动中止当前帧并报错
  - 错误检测：零长度负载、超长负载、超时
  - 输出：`o_in_frame`, `o_frame_start`, `o_payload_valid`, `o_payload_byte`, `o_frame_done`, `o_error`, `o_payload_len`, `o_payload_count`

---

### 3. 访问控制列表（ACL）层

本系统包含两套 ACL 实现：主线 AXIS 版和旧版直连版。

#### 3.1 主线 AXIS 版 ACL（contest_acl_axis_core.sv）

- **功能**：AXI-Stream 接口的 ACL 匹配与过滤引擎，是当前 Crypto Probe 的实际使用模块
- **实现细节**：
  - 与 `contest_acl_core` 相同的 8 槽位 + 256 项 membership RAM 机制
  - **AXI-Stream 字节级接口**：`s_axis_tvalid/tready/tdata/tlast/tuser`，`tuser[0]` 携带算法选择
  - 4 状态数据路径 FSM：`ST_IDLE → ST_LOOKUP → ST_PASS → ST_DROP_DRAIN`
  - 7 状态配置 FSM：与 `contest_acl_core` 相同
  - **背压感知**：`s_axis_tready` 综合考虑配置状态和数据处理状态
  - **ACL 阻止脉冲**：`o_acl_block_pulse` + `o_acl_block_slot_valid` + `o_acl_block_slot`，用于上层统计和 PMU
  - 运行时配置接口：`i_cfg_valid/i_cfg_index/i_cfg_key`，含重复检测
  - 诊断输出：`o_rule_keys_flat`（64位）、`o_rule_counts_flat`（64位）

#### 3.2 旧版直连 ACL（contest_acl_core.sv）

- **功能**：基于字节级直连接口的 ACL 引擎，用于 ACL Probe 和 SM4 Probe
- **实现细节**：
  - 与 AXIS 版相同的 8 槽位 + 256 项 membership RAM
  - **非 AXIS 接口**：`parser_valid/parser_match_key/parser_payload/parser_last` 输入，`acl_valid/acl_data/acl_last` 输出
  - 6 状态数据路径 FSM：`ST_IDLE → ST_LOOKUP → ST_PASS/ST_DROP_D → ST_DROP_NL → ST_DROP_DRAIN`
  - 阻止时自行生成 `D + NL` 输出（AXIS 版不生成，交由上层处理）
  - 运行时配置接口和诊断输出同 AXIS 版

#### 3.3 参考版 ACL（acl_match_engine.sv / acl_packet_filter.sv）

- **功能**：2 路组相联哈希查找引擎和 5 元组包过滤器（参考实现，未被 Contest 代码直接使用）
- **实现细节**：
  - `acl_match_engine`：12 位地址、104 位标签、2 路组相联，使用 XPM BRAM，代际清除机制
  - `acl_packet_filter`：AXI-Stream 接口，7 状态 FSM，头部缓冲防泄露

---

### 4. AXI-Stream 块级数据通路（主线密码核心）

#### contest_axis_block_packer.sv
- **功能**：字节→128-bit 块打包器
- **实现细节**：
  - AXI-Stream 8-bit 输入 → 128-bit 输出
  - `tuser[0]`：算法选择位（从 ACL 的 `tuser[0]` 透传，0=SM4，1=AES）
  - `tuser[1]`：短帧标记（`gather_count != 15` 时置位，表示不足 16 字节）
  - `tuser[5:2]`：有效字节数 - 1（用于 unpacker 还原）
  - 满 16 字节或遇到 `tlast` 时输出一个 128-bit 块

#### contest_crypto_block_engine.sv
- **功能**：128-bit 块级密码引擎，主线密码运算核心
- **实现细节**：
  - **AXI-Stream 128-bit 块级接口**：`s_axis_tvalid/tready/tdata/tlast/tuser[5:0]`
  - **双算法支持**：`tuser[0]` = 0 选 SM4，= 1 选 AES
  - **Bypass 模式**：`tuser[1]` = 1 时短帧不加密直接透传
  - **硬编码测试密钥**：
    - SM4: `0123456789ABCDEFFEDCBA9876543210`
    - AES: `000102030405060708090A0B0C0D0E0F`
  - **双 FIFO 架构**：
    - Ingress FIFO：135 位宽（128 数据 + 1 last + 6 user），深度 64
    - Egress FIFO：135 位宽（128 数据 + 1 last + 6 user），深度 64
  - **AES 引擎控制**：7 状态 FSM（`AES_BOOT_INIT → AES_BOOT_WAIT_BUSY → AES_BOOT_WAIT_RDY → AES_IDLE → AES_RUN_PULSE → AES_RUN_WAIT_BUSY → AES_RUN_WAIT_DONE`），启动时自动初始化密钥
  - **SM4 引擎控制**：首次上电自动发送密钥，4 周期 valid burst 触发加密
  - **PMU 输出**：`o_pmu_crypto_active`（密码引擎活跃指示，供 PMU 计数使用）

#### contest_axis_block_unpacker.sv
- **功能**：128-bit 块→字节拆包器
- **实现细节**：
  - AXI-Stream 128-bit 输入 → 8-bit 输出
  - 从 `s_axis_tuser[5:2]` 读取有效字节数，逐字节输出
  - 仅在最后一个有效字节时拉高 `m_axis_tlast`

#### contest_crypto_axis_core.sv
- **功能**：完整 AXIS 密码核心，串联 ACL + Packer + Block Engine + Unpacker
- **实现细节**：
  - **数据通路**：`s_axis(8-bit) → contest_acl_axis_core → contest_axis_block_packer → contest_crypto_block_engine → contest_axis_block_unpacker → m_axis(8-bit)`
  - 暴露 ACL 配置接口：`i_acl_cfg_valid/i_acl_cfg_index/i_acl_cfg_key`
  - 暴露 ACL 诊断：`o_rule_keys_flat/o_rule_counts_flat`
  - 暴露 ACL 阻止脉冲：`o_acl_block_pulse/o_acl_block_slot_valid/o_acl_block_slot`
  - 暴露 PMU 信号：`o_pmu_crypto_active`

---

### 5. 旧版加密桥接层（Legacy）

#### contest_crypto_bridge.sv
- **功能**：ACL 输出到加密引擎的桥接模块（旧版，用于 SM4 Probe）
- **实现细节**：
  - 字节级输入（`acl_valid/acl_data/acl_last`），非 AXIS 接口
  - 内部自行完成字节→128-bit 块攒集和 128-bit→字节拆分
  - 短块透传（不足 16 字节不加密）
  - 双 FIFO（130 位 ingress / 129 位 egress）
  - AES/SM4 控制逻辑与 `contest_crypto_block_engine` 相同
  - **当前状态**：仍保留在仓库中，供 Legacy ACL/SM4 Probe 的独立工程脚本和对应单元测试使用；主线 Crypto Probe 已不再例化，也不再加入主线 `sources_1`

---

### 6. 块 FIFO

#### contest_block_fifo.sv
- **功能**：宽位宽 BRAM FIFO
- **实现细节**：
  - 可参数化宽度（默认130位）、深度（默认64）、地址宽度（默认6位）
  - `(* ram_style = "block" *)` 属性确保推断为 BRAM
  - 输出 `level` 信号指示当前填充深度
  - 同步复位，读数据单周期延迟（`rd_valid`）

---

### 7. 五个系统级 Probe 配置

#### 7.1 UART Echo Probe
- **文件**：rx50t_uart_echo_top.sv, rx50t_uart_echo_board_top.sv
- **功能**：最基础配置 — UART 回环
- **数据流**：`UART RX → FIFO → UART TX`
- **调试输出**：最后收/发字节、脉冲指示、帧错误、溢出标志

#### 7.2 Parser Probe
- **文件**：contest_uart_parser_probe.sv
- **功能**：协议解析验证
- **数据流**：`UART RX → Parser → Payload 透传到 TX FIFO → UART TX`
- **行为**：
  - 有效帧：回传 payload 字节 + 换行符
  - 解析错误/帧错误：回传 `E(0x45)` + 换行符
  - FIFO 满时设置 `o_dbg_tx_overrun`

#### 7.3 ACL Probe（Legacy）
- **文件**：contest_uart_acl_probe.sv
- **功能**：ACL 过滤验证
- **数据流**：`UART RX → Parser → ACL Core → TX FIFO → UART TX`
- **行为**：
  - 帧首字节作为 ACL 匹配键
  - 命中阻止键：回传 `D + NL`
  - 未命中：原样透传 payload
  - 错误：回传 `E + NL`
- **已确认限制**：此版本 ACL Core 未连接配置接口和诊断输出（`cfg_valid/cfg_index/cfg_key` 和 `o_rule_keys_flat/o_rule_counts_flat` 均未接线）

#### 7.4 SM4 Probe（Legacy）
- **文件**：contest_uart_sm4_probe.sv
- **功能**：ACL + SM4 加密验证
- **数据流**：`UART RX → Parser → ACL Core → Crypto Bridge(SM4 only) → UART TX`
- **行为**：
  - ACL 通过的帧送入 Crypto Bridge（`i_algo_sel` 固定为 0，即 SM4）
  - ACL 阻止的帧输出 `D + NL`
  - 错误：回传 `E + NL`
- **已确认限制**：仅支持 SM4，不支持算法选择

#### 7.5 Crypto Probe（完整版 — 当前主线）
- **文件**：contest_uart_crypto_probe.sv
- **功能**：全功能加密网关（最复杂的配置）
- **默认波特率**：2,000,000（2M baud，远高于其他 Probe 的 115200）
- **最大负载**：255 字节（其他 Probe 为 32 字节）
- **帧间超时**：20 个 UART 字符时间
- **当前数据流**：`UART RX → Parser → Protocol Dispatcher → contest_crypto_axis_core → TX Mux → UART TX`
  - 内部展开：`Parser → ACL AXIS Core → Packer(8→128) → Crypto Block Engine(AES/SM4) → Unpacker(128→8) → TX Mux`
- **完整协议命令集**：

| 命令 | 帧格式 | 功能 |
|------|--------|------|
| 查询统计 | `55 01 3F` | 返回 `S total acl aes sm4 err NL` |
| 查询规则计数 | `55 01 48` | 返回 `H c0..c7 NL`（8个槽位命中数） |
| 查询 ACL 键映射 | `55 01 4B` | 返回 `K k0..k7 NL`（8个槽位键值） |
| **查询 PMU** | `55 01 50` | 返回 48 字节性能监控快照（见 §7.5.3） |
| **清除 PMU** | `55 01 4A` | 清零所有 PMU 计数器，返回 ACK |
| ACL 规则配置 | `55 03 03 idx key` | 返回 `C idx key NL`（配置确认） |
| 流式能力查询 | `55 01 57` | 返回 `55 04 57 80 08 xx`（128B块/窗口8） |
| 流式会话启动 | `55 04 4D algo total_hi total_lo` | 返回 `55 02 4D 00`（启动确认） |
| 流式数据块 | `55 81 seq payload[128B]` | 返回加密结果（带序列号） |
| 隐式 SM4 加密 | `55 NN payload` | SM4 加密（首字节为 ACL 键） |
| 显式 AES 加密 | `55 11+AES_PT` | AES 加密（长度>=17且低4位=1，首字节=0x41） |
| 显式 SM4 加密 | `55 11+SM4_PT` | SM4 加密（首字节=0x53） |

#### 7.5.1 统计计数器
- `stat_total_frames_q`：总帧数（8位）
- `stat_acl_blocks_q`：ACL 阻止帧数（8位）
- `stat_aes_frames_q`：AES 加密帧数（8位）
- `stat_sm4_frames_q`：SM4 加密帧数（8位）
- `stat_error_frames_q`：错误帧数（8位）

#### 7.5.2 流式加密会话管理
- 序列号 FIFO（`stream_seq_fifo_q[0:7]`），深度 8
- 窗口控制（`STREAM_WINDOW = 8`），最多 8 个未确认块
- 序列号连续性验证（`stream_expected_seq_q`）
- 会话故障标记（`stream_session_fault_q`）
- ACL 命中中断流式会话
- 流式 TX 多路复用：管理响应帧（CAP/START_ACK/BLOCK/ERROR/CIPHER_HDR）与加密数据的发送优先级

#### 7.5.3 PMU 性能监控单元
- **5 个 64 位硬件计数器**：
  - `pmu_global_cycles_q`：全局时钟周期数
  - `pmu_crypto_active_cycles_q`：密码引擎活跃周期数（来自 `o_pmu_crypto_active`）
  - `pmu_uart_tx_stall_cycles_q`：UART TX 反压周期数
  - `pmu_stream_credit_block_cycles_q`：流式信用阻塞周期数
  - `pmu_acl_block_events_q`：ACL 阻止事件数
- **快照机制**：查询时原子快照所有计数器到 `pmu_snap_*` 寄存器，避免读出不一致
- **PMU 使能**：`pmu_armed_q` 标志，首个非 PMU 帧完成后自动使能
- **PMU 清除**：清零所有计数器并返回 ACK
- **快照响应格式**（48字节）：
  ```
  [0x55][0x2E][0x50][0x01][clk_hz:4B][global:8B][crypto:8B][uart_stall:8B][credit_block:8B][acl_events:8B]
  ```

#### 7.5.4 TX 多路复用器
优先级从高到低：
1. PMU 响应（`pmu_tx_active_w`）
2. 流式响应（`stream_tx_active_w`）
3. 控制响应（`ctrl_tx_valid_w`：错误/阻止/配置ACK/统计/规则/键映射）
4. 密码密文数据（`axis_out_tvalid_w`）

---

### 8. 参考加密 IP 核

#### AES-128/256 核心
- **文件**：aes_core.v 及其子模块
- **来源**：Secworks Sweden AB（开源实现）
- **功能**：AES 加密/解密
- **实现**：
  - 支持 128 位和 256 位密钥（`keylen` 信号）
  - 加密/解密选择（`encdec` 信号）
  - 密钥初始化（`init`）+ 块加密（`next`）两阶段操作
  - 共享 S-Box（`aes_sbox`）在密钥扩展和加密间复用
  - 子模块：`aes_encipher_block`, `aes_decipher_block`, `aes_key_mem`, `aes_sbox`, `aes_inv_sbox`, `sbox_replace`, `one_round_for_encdec`, `transform_for_encdec`, `one_round_for_key_exp`, `transform_for_key_exp`, `get_cki`, `key_expansion`

#### SM4 核心
- **文件**：sm4_top.v
- **来源**：Raymond Rui Chen 实现
- **功能**：SM4 国密加密/解密
- **实现**：
  - 32 轮密钥扩展（`key_expansion` 模块，输出 rk_00~rk_31）
  - 加密/解密选择（`encdec_sel_in`）
  - 用户密钥输入（`user_key_in/user_key_valid_in`）
  - 密钥扩展就绪信号（`key_exp_ready_out`）
  - 子模块：`sm4_encdec`, `key_expansion`

---

### 9. 参考支撑模块

#### async_fifo.sv
- **功能**：异步 FIFO（跨时钟域）
- **实现**：Gray 码指针 + 2-FF 同步器，`ASYNC_REG = "TRUE"` 约束

#### gearbox_128_to_32.sv
- **功能**：128 位→32 位位宽转换器（大端序）
- **实现**：4 拍输出 `[127:96] → [95:64] → [63:32] → [31:0]`，第 4 拍拉高 `dout_last`

#### seven_seg_driver.sv
- **功能**：4 位七段数码管动态扫描驱动
- **实现**：18 位计数器分频，4 位扫描，共阳极译码（0-F + 小数点）

#### crypto_bridge_top.sv
- **功能**：16 实例并行加密桥接器（参考实现，未被 Contest 代码直接使用）
- **实现**：
  - 16 路并行 AES/SM4 实例
  - Round-Robin 调度器
  - 重排序缓冲区（ROB，32 项深度）保证输出顺序
  - 密钥混淆（LFSR XOR）安全措施
  - 上下文指纹缓存（`context_fp_fn`）避免冗余密钥初始化
  - 超时检测（2000 周期）
  - CBC 模式元数据锁存（预留）
  - Gearbox 128→32 + 输出 FIFO

---

### 10. Python 工具链

#### crypto_gateway_protocol.py
- **功能**：协议定义与串行通信库
- **实现**：
  - 数据类：`StatsCounters`, `AclWriteAck`, `AclKeyMap`, `AclRuleCounters`, `ProbeCase`, `ProbeResult`, `FileChunkPlan`, `StreamCapabilities`, `StreamStartAck`, `StreamCipherResponse`, `StreamBlockResponse`, `StreamErrorResponse`, **`PmuSnapshot`**, **`PmuClearAck`**
  - 帧构建：`build_frame()`, `build_stream_capability_query()`, `build_stream_start_frame()`, `build_stream_chunk_frame()`
  - 响应解析：`parse_stats_response()`, `parse_rule_stats_response()`, `parse_acl_write_ack()`, `parse_acl_key_map_response()`, `parse_stream_response()`, **`parse_pmu_snapshot_response()`**, **`parse_pmu_clear_ack()`**
  - PMU 查询用例：**`case_query_pmu()`**, **`case_clear_pmu()`**
  - PMU 快照属性：`crypto_utilization`, `uart_stall_ratio`, `credit_block_ratio`, `elapsed_ms_from_hw`
  - 已知测试向量：AES-128 和 SM4 的 16B/32B/64B/128B 明密文对
  - PKCS#7 填充：`pkcs7_pad()`
  - 文件分块：`plan_file_chunks_for_transport()`, `split_blocks_for_transport()`
  - 串行执行：`run_case_on_serial()`, `read_exact()`

#### crypto_gateway_worker.py
- **功能**：后台工作线程
- **实现**：
  - `GatewayWorker` 类：任务队列 + 事件队列的异步架构
  - 串口连接管理（connect/disconnect）
  - 测试用例执行（`submit_case`）
  - 文件加密（`encrypt_file`）
  - 流式加密 v3 协议（`stream_encrypt_file_v3_on_serial`）：能力查询 → 会话启动 → 滑动窗口数据传输 → 顺序重组
  - 事件驱动回调（`WorkerEvent`）
  - **PMU 自动取证**：
    - `_query_pmu_after_session()`：文件加密完成后自动查询 PMU 快照，含 3 次重试
    - `_clear_pmu_before_session()`：文件加密开始前自动清除 PMU 计数器
    - `_emit_pmu_snapshot()`：发射 `pmu_snapshot` 事件，包含完整性能指标
  - **PMU 异常恢复**：ACL 阻断流式会话后，仍尝试查询 PMU 快照用于诊断
  - **PMU 事件类型**：`pmu_snapshot`（含 clk_hz/global_cycles/crypto_active/uart_stall/credit_block/acl_events/utilization/stall_ratio/elapsed_ms）、`pmu_cleared`

#### rx50t_crypto_gui.py
- **功能**：完整 GUI 控制台
- **实现**：
  - Tkinter 暗色主题界面（1420×980）
  - 串口连接管理面板
  - 快捷操作网格：Query Stats, Rule Hits, SM4/AES 16B/32B/64B/128B, Invalid Selector, ACL Block
  - ACL 规则部署面板（Slot + Rule Byte）
  - 文件加密面板（选择文件 + 算法 + 进度条）
  - 吞吐量心跳图（Canvas 实时绘制）
  - 计数器银行（Total/ACL/AES/SM4/Error，带动画）
  - BRAM ACL 威胁阵列（8 槽位热力图 + 命中计数条形图）
  - **PMU 面板**：
    - "Clear PMU" / "Read PMU" 操作按钮
    - 4 个实时指标：`hw_util`（加密利用率%）、`uart_stall`（TX反压%）、`credit_block`（信用阻塞%）、`acl_events`（ACL阻止数）
    - `_apply_pmu_snapshot()`：消费 `pmu_snapshot` 事件更新面板
    - `_reset_pmu_display()`：消费 `pmu_cleared` 事件重置面板
  - 实时日志区域

#### CLI 发送脚本
- send_rx50t_parser_probe.py：Parser Probe 测试（ASCII/Hex/Invalid-Zero-Len）
- send_rx50t_acl_probe.py：ACL Probe 测试（Pass/Block ASCII）
- send_rx50t_sm4_probe.py：SM4 Probe 测试（已知向量/Block ASCII）
- send_rx50t_crypto_probe.py：Crypto Probe 完整测试（所有向量 + 统计查询 + 规则查询 + **PMU 查询/清除**）

#### Python 测试文件
- **test_crypto_gateway_protocol.py**：38 个单元测试，覆盖帧构建/解析、PMU 快照/清除解析、流式协议、PKCS#7 填充、文件分块等
- **test_crypto_gateway_worker.py**：11 个单元测试，覆盖 PMU 快照/清除事件发射、文件加密前后 PMU 自动取证、ACL 阻断后 PMU 重试查询、流式 v3 超时/seq 回绕等
- **test_rx50t_crypto_gui_layout.py**：5 个布局/事件消费测试（非完整串口 E2E），验证三区域布局、PMU 事件更新和清除、连接事件触发等

---

### 11. 构建与约束

#### rx50t_uart_echo.xdc
- 目标器件：Artix-7 xc7a50tfgg484-1
- 时钟：50MHz（20ns 周期），PIN Y18，LVCMOS33
- 复位：PIN J20，LVCMOS33
- UART RX：PIN K1，UART TX：PIN J1（LVCMOS33）
- 配置电压：3.3V

#### TCL 构建脚本
- 5 个独立 Vivado 项目脚本（crypto/acl/parser/sm4/echo）
- 每个脚本：创建项目 → 添加源文件 → 添加约束 → 添加仿真 → 综合实现 → 生成比特流
- **Crypto Probe 项目源文件清单**（来自 `create_rx50t_uart_crypto_probe_project.tcl`）：
  - 15 个参考加密 IP（aes_core.v + 11 子模块 + sm4_encdec.v + sm4_top.v）
  - 12 个 Contest RTL（主线 `crypto probe` 所需源文件）
  - **说明**：`contest_acl_core.sv` 和 `contest_crypto_bridge.sv` 仍保留在仓库中，由 Legacy ACL/SM4 Probe 的独立工程脚本和对应单元测试使用，但不再加入主线 `crypto probe` 的 `sources_1`

#### PowerShell 构建脚本
- 5 个 `.ps1` 脚本，调用 Vivado 批处理模式执行对应 TCL

---

## 三、已确认的集成点

### 主线 Crypto Probe 集成点

| 集成点 | 连接模块 | 证据 |
|--------|----------|------|
| UART RX → Parser | `contest_uart_rx.o_valid/o_data` → `contest_parser_core.i_valid/i_byte` | 所有 Probe |
| Parser → Protocol Dispatcher | `contest_parser_core.o_payload_valid/o_payload_byte` → `contest_uart_crypto_probe` 帧分类逻辑 | 仅 Crypto Probe |
| Protocol Dispatcher → ACL AXIS | `acl_in_valid_q/acl_in_data_q/acl_in_last_q` → `contest_crypto_axis_core.s_axis_t*` | 仅 Crypto Probe |
| ACL AXIS → Packer | `contest_acl_axis_core.m_axis_t*` → `contest_axis_block_packer.s_axis_t*` | `contest_crypto_axis_core.sv` 内部连线 |
| Packer → Block Engine | `contest_axis_block_packer.m_axis_t*` → `contest_crypto_block_engine.s_axis_t*` | `contest_crypto_axis_core.sv` 内部连线 |
| Block Engine → Unpacker | `contest_crypto_block_engine.m_axis_t*` → `contest_axis_block_unpacker.s_axis_t*` | `contest_crypto_axis_core.sv` 内部连线 |
| Unpacker → TX Mux | `contest_axis_block_unpacker.m_axis_t*` → `contest_uart_crypto_probe` TX 多路复用 | 仅 Crypto Probe |
| ACL Block Pulse → Stats/PMU | `contest_crypto_axis_core.o_acl_block_pulse` → `contest_uart_crypto_probe` 统计和 PMU 逻辑 | 仅 Crypto Probe |
| ACL Config ← Crypto Probe | `contest_uart_crypto_probe` 解析配置帧 → `contest_crypto_axis_core.i_acl_cfg_*` | 仅 Crypto Probe |
| PMU Crypto Active ← Block Engine | `contest_crypto_block_engine.o_pmu_crypto_active` → `contest_uart_crypto_probe.pmu_crypto_active_w` | 仅 Crypto Probe |
| Python → UART → FPGA | `crypto_gateway_protocol.py` 构建帧 → `serial.write()` → FPGA UART RX | 所有 CLI/GUI 工具 |
| GUI → Worker → Serial | `CryptoGatewayApp` → `GatewayWorker.submit_case()` → `run_case_on_serial()` | GUI 工具 |
| Worker PMU Auto → GUI | `GatewayWorker._emit_pmu_snapshot()` → `pmu_snapshot` 事件 → `CryptoGatewayApp._apply_pmu_snapshot()` | GUI 工具 |

### Legacy Probe 集成点（ACL / SM4 Probe）

| 集成点 | 连接模块 | 证据 |
|--------|----------|------|
| Parser → ACL Core | `contest_parser_core.o_payload_valid/o_payload_byte` → `contest_acl_core.parser_valid/parser_payload` | ACL/SM4 Probe |
| ACL Core → Crypto Bridge | `contest_acl_core.acl_valid/acl_data/acl_last` → `contest_crypto_bridge.acl_valid/acl_data/acl_last` | SM4 Probe |
| Crypto Bridge → UART TX | `contest_crypto_bridge.bridge_valid/bridge_data` → `contest_uart_tx.i_valid/i_data` | SM4 Probe |

---

## 四、核心算法确认

| 算法 | 实现位置 | 密钥长度 | 操作模式 | 验证向量 |
|------|----------|----------|----------|----------|
| AES-128 | `aes_core.v` + 11 个子模块 | 128 位 | ECB（单块） | Python 中定义了 2 组已知明密文对 |
| AES-256 | `aes_core.v`（`keylen=1`） | 256 位 | ECB（单块） | 代码支持但 Contest 未使用 |
| SM4 | `sm4_top.v` + `sm4_encdec.v` + `key_expansion.v` | 128 位 | ECB（单块） | Python 中定义了 2 组已知明密文对 |
| ACL 匹配（主线） | `contest_acl_axis_core.sv` | 8×8 位键 | 直接查找表 | 默认 8 个阻止键，运行时可配置 |
| ACL 匹配（旧版） | `contest_acl_core.sv` | 8×8 位键 | 直接查找表 | 同上 |
| 帧协议 | `contest_parser_core.sv` | — | SOF+LEN+PAYLOAD | Python 工具完整实现 |

---

## 五、已确认的操作能力

1. **UART 回环通信**（Echo Probe）
2. **帧协议解析与回传**（Parser Probe）
3. **基于首字节的 ACL 过滤**（ACL/SM4/Crypto Probe）
4. **ACL 运行时规则配置**（仅 Crypto Probe，通过 `contest_crypto_axis_core` 的配置接口）
5. **ACL 统计查询**（仅 Crypto Probe）
6. **ACL 规则命中计数查询**（仅 Crypto Probe）
7. **ACL 键映射查询**（仅 Crypto Probe）
8. **SM4 加密**（SM4/Crypto Probe）
9. **AES-128 加密**（仅 Crypto Probe）
10. **显式算法选择**（仅 Crypto Probe，通过帧长度编码）
11. **多块加密**（16B/32B/64B/128B）
12. **流式加密会话**（仅 Crypto Probe，窗口=8，块大小=128B）
13. **短块 bypass 透传**（不足 16 字节不加密直接输出，通过 `tuser[1]` bypass 路径）
14. **PMU 性能监控**（仅 Crypto Probe，5 个 64 位硬件计数器 + 快照/清除）
15. **文件加密**（Python 工具，PKCS#7 填充 + 分块传输 + 流式 v3 协议）
16. **PMU 自动取证**（Worker 文件加密前后自动清除/查询 PMU，异常后重试查询）
17. **GUI PMU 面板**（实时显示加密利用率、TX 反压率、信用阻塞率、ACL 阻止数）
18. **GUI 实时监控**（吞吐量、计数器、ACL 热力图）
19. **FPGA 比特流生成**（Vivado TCL/PS1 自动化构建）

---

## 六、参考模块与 Contest 模块的关系

| 参考模块 | Contest 对应模块 | 关系 |
|----------|------------------|------|
| `acl_match_engine.sv` | `contest_acl_axis_core.sv` / `contest_acl_core.sv` | 参考为 2 路组相联哈希查找；Contest 为直接 256 项查找表，更简单 |
| `acl_packet_filter.sv` | `contest_uart_acl_probe.sv` | 参考为 AXI-Stream 5 元组过滤；Contest 为 UART 首字节过滤 |
| `crypto_bridge_top.sv` | `contest_crypto_block_engine.sv` / `contest_crypto_bridge.sv` | 参考为 16 实例并行+ROB+密钥混淆；Contest 主线为单实例 AXIS 块引擎；旧版为单实例字节桥 |
| `async_fifo.sv` | `contest_uart_fifo.sv` | 参考为跨时钟域 Gray 码 FIFO；Contest 为同频同步 FIFO |
| `gearbox_128_to_32.sv` | 未使用 | 参考模块，Contest 使用逐字节输出替代 |
| `seven_seg_driver.sv` | 未使用 | 参考模块，Contest 无显示接口 |
| `aes_core.v` + 子模块 | 直接实例化 | `contest_crypto_block_engine` 和 `contest_crypto_bridge` 均实例化 `aes_core` |
| `sm4_top.v` + 子模块 | 直接实例化 | `contest_crypto_block_engine` 和 `contest_crypto_bridge` 均实例化 `sm4_top` |

---

## 七、文件清单

### Contest RTL 源文件（22个）

| 文件路径 | 模块名 | 功能 | 主线使用 |
|----------|--------|------|----------|
| contest_project/rtl/contest/contest_uart_rx.sv | contest_uart_rx | UART 接收器 | ✅ |
| contest_project/rtl/contest/contest_uart_tx.sv | contest_uart_tx | UART 发送器 | ✅ |
| contest_project/rtl/contest/contest_uart_fifo.sv | contest_uart_fifo | 8位同步FIFO | ✅ |
| contest_project/rtl/contest/contest_uart_io.sv | contest_uart_io | UART I/O聚合 | ✅ Echo |
| contest_project/rtl/contest/contest_parser_core.sv | contest_parser_core | 帧协议解析器 | ✅ |
| contest_project/rtl/contest/contest_acl_core.sv | contest_acl_core | ACL匹配引擎（旧版） | ⚠️ Legacy only |
| contest_project/rtl/contest/contest_acl_axis_core.sv | contest_acl_axis_core | ACL匹配引擎（AXIS版） | ✅ 主线 |
| contest_project/rtl/contest/contest_block_fifo.sv | contest_block_fifo | 宽位宽BRAM FIFO | ✅ |
| contest_project/rtl/contest/contest_crypto_bridge.sv | contest_crypto_bridge | 加密桥接器（旧版） | ⚠️ Legacy only |
| contest_project/rtl/contest/contest_axis_block_packer.sv | contest_axis_block_packer | 字节→128bit打包器 | ✅ 主线 |
| contest_project/rtl/contest/contest_axis_block_unpacker.sv | contest_axis_block_unpacker | 128bit→字节拆包器 | ✅ 主线 |
| contest_project/rtl/contest/contest_crypto_block_engine.sv | contest_crypto_block_engine | 128bit块级密码引擎 | ✅ 主线 |
| contest_project/rtl/contest/contest_crypto_axis_core.sv | contest_crypto_axis_core | AXIS密码核心（集成ACL+Packer+Engine+Unpacker） | ✅ 主线 |
| contest_project/rtl/contest/contest_uart_crypto_probe.sv | contest_uart_crypto_probe | 全功能加密探针 | ✅ 主线 |
| contest_project/rtl/contest/contest_uart_sm4_probe.sv | contest_uart_sm4_probe | SM4加密探针 | ⚠️ Legacy |
| contest_project/rtl/contest/contest_uart_acl_probe.sv | contest_uart_acl_probe | ACL过滤探针 | ⚠️ Legacy |
| contest_project/rtl/contest/contest_uart_parser_probe.sv | contest_uart_parser_probe | 解析探针 | ✅ |
| contest_project/rtl/contest/rx50t_uart_crypto_probe_top.sv | rx50t_uart_crypto_probe_top | 顶层（可仿真） | ✅ |
| contest_project/rtl/contest/rx50t_uart_crypto_probe_board_top.sv | rx50t_uart_crypto_probe_board_top | 顶层（板级） | ✅ |
| contest_project/rtl/contest/rx50t_uart_sm4_probe_top.sv | rx50t_uart_sm4_probe_top | 顶层（可仿真） | ⚠️ Legacy |
| contest_project/rtl/contest/rx50t_uart_sm4_probe_board_top.sv | rx50t_uart_sm4_probe_board_top | 顶层（板级） | ⚠️ Legacy |
| contest_project/rtl/contest/rx50t_uart_acl_probe_top.sv | rx50t_uart_acl_probe_top | 顶层（可仿真） | ⚠️ Legacy |
| contest_project/rtl/contest/rx50t_uart_acl_probe_board_top.sv | rx50t_uart_acl_probe_board_top | 顶层（板级） | ⚠️ Legacy |
| contest_project/rtl/contest/rx50t_uart_parser_probe_top.sv | rx50t_uart_parser_probe_top | 顶层（可仿真） | ✅ |
| contest_project/rtl/contest/rx50t_uart_parser_probe_board_top.sv | rx50t_uart_parser_probe_board_top | 顶层（板级） | ✅ |
| contest_project/rtl/contest/rx50t_uart_echo_top.sv | rx50t_uart_echo_top | 顶层（可仿真） | ✅ |
| contest_project/rtl/contest/rx50t_uart_echo_board_top.sv | rx50t_uart_echo_board_top | 顶层（板级） | ✅ |

### 参考 RTL 源文件（21个）

| 文件路径 | 模块名 | 功能 |
|----------|--------|------|
| reference/rtl/core/crypto/aes_core.v | aes_core | AES核心 |
| reference/rtl/core/crypto/aes_encipher_block.v | aes_encipher_block | AES加密块 |
| reference/rtl/core/crypto/aes_decipher_block.v | aes_decipher_block | AES解密块 |
| reference/rtl/core/crypto/aes_key_mem.v | aes_key_mem | AES密钥存储 |
| reference/rtl/core/crypto/aes_sbox.v | aes_sbox | AES S-Box |
| reference/rtl/core/crypto/aes_inv_sbox.v | aes_inv_sbox | AES逆S-Box |
| reference/rtl/core/crypto/sbox_replace.v | sbox_replace | S-Box替换 |
| reference/rtl/core/crypto/one_round_for_encdec.v | one_round_for_encdec | 一轮加解密 |
| reference/rtl/core/crypto/transform_for_encdec.v | transform_for_encdec | 加解密变换 |
| reference/rtl/core/crypto/one_round_for_key_exp.v | one_round_for_key_exp | 密钥扩展轮 |
| reference/rtl/core/crypto/transform_for_key_exp.v | transform_for_key_exp | 密钥扩展变换 |
| reference/rtl/core/crypto/get_cki.v | get_cki | CKI计算 |
| reference/rtl/core/crypto/key_expansion.v | key_expansion | 密钥扩展 |
| reference/rtl/core/crypto/sm4_encdec.v | sm4_encdec | SM4加解密 |
| reference/rtl/core/crypto/sm4_top.v | sm4_top | SM4顶层 |
| reference/rtl/core/crypto/crypto_bridge_top.sv | crypto_bridge_top | 并行加密桥（参考，未使用） |
| reference/rtl/security/acl_match_engine.sv | acl_match_engine | ACL匹配引擎（参考，未使用） |
| reference/rtl/security/acl_packet_filter.sv | acl_packet_filter | ACL包过滤器（参考，未使用） |
| reference/rtl/support/async_fifo.sv | async_fifo | 异步FIFO（参考，未使用） |
| reference/rtl/support/gearbox_128_to_32.sv | gearbox_128_to_32 | 位宽转换器（参考，未使用） |
| reference/rtl/display/seven_seg_driver.sv | seven_seg_driver | 七段数码管（参考，未使用） |

### Python 工具文件（10个）

| 文件路径 | 功能 |
|----------|------|
| contest_project/tools/crypto_gateway_protocol.py | 协议定义与通信库（含 PMU） |
| contest_project/tools/crypto_gateway_worker.py | 后台工作线程（含 PMU 自动取证） |
| contest_project/tools/rx50t_crypto_gui.py | GUI控制台（含 PMU 面板） |
| contest_project/tools/send_rx50t_crypto_probe.py | Crypto Probe CLI（含 PMU 查询/清除） |
| contest_project/tools/send_rx50t_sm4_probe.py | SM4 Probe CLI |
| contest_project/tools/send_rx50t_acl_probe.py | ACL Probe CLI |
| contest_project/tools/send_rx50t_parser_probe.py | Parser Probe CLI |
| contest_project/tools/test_crypto_gateway_protocol.py | 协议库单元测试（38个） |
| contest_project/tools/test_crypto_gateway_worker.py | Worker 单元测试（11个，含 PMU 测试） |
| contest_project/tools/test_rx50t_crypto_gui_layout.py | GUI 布局/事件消费测试（5个，非 E2E） |

### 构建与约束文件（12个）

| 文件路径 | 功能 |
|----------|------|
| contest_project/constraints/rx50t_uart_echo.xdc | 引脚约束 |
| contest_project/scripts/create_rx50t_uart_crypto_probe_project.tcl | Vivado项目创建 |
| contest_project/scripts/create_rx50t_uart_sm4_probe_project.tcl | Vivado项目创建 |
| contest_project/scripts/create_rx50t_uart_acl_probe_project.tcl | Vivado项目创建 |
| contest_project/scripts/create_rx50t_uart_parser_probe_project.tcl | Vivado项目创建 |
| contest_project/scripts/create_rx50t_uart_echo_project.tcl | Vivado项目创建 |
| contest_project/scripts/build_rx50t_uart_crypto_probe.ps1 | PowerShell构建 |
| contest_project/scripts/build_rx50t_uart_sm4_probe.ps1 | PowerShell构建 |
| contest_project/scripts/build_rx50t_uart_acl_probe.ps1 | PowerShell构建 |
| contest_project/scripts/build_rx50t_uart_parser_probe.ps1 | PowerShell构建 |
| contest_project/scripts/build_rx50t_uart_echo.ps1 | PowerShell构建 |

---

## 八、已知限制与注意事项

### Legacy Probe 限制（不影响主线）
1. **ACL Probe**：`contest_uart_acl_probe` 未连接 `contest_acl_core` 的配置接口（`cfg_valid/cfg_index/cfg_key`）和诊断输出（`o_rule_keys_flat/o_rule_counts_flat`），无法运行时修改 ACL 规则或查询规则状态
2. **SM4 Probe**：`contest_uart_sm4_probe` 的 `i_algo_sel` 固定为 0，仅支持 SM4，不支持 AES 算法选择

### 自动化测试边界
3. **GUI 测试**：`test_rx50t_crypto_gui_layout.py` 仅覆盖布局和事件消费，不包含完整串口 E2E 测试

### 报告边界
4. **代码态报告**：本报告描述的是仓库中的实现状态和工程组织，不代替板级 smoke、GUI 彩排或标签对应的实机验证记录

---

*报告修订完毕，所有功能描述均基于实际源代码实现，已对照 TCL 构建脚本和主线数据通路验证。*
