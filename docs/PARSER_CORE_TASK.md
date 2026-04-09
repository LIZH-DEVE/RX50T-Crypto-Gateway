# contest_parser_core

## 帧格式

- `SOF = 0x55`
- `LEN = 1..MAX_PAYLOAD_BYTES`
- `PAYLOAD = LEN` 个字节

## 当前职责

- 在字节流中识别帧起始
- 解析固定 1 字节长度字段
- 逐字节输出 payload
- 对 `LEN=0` 和 `LEN>MAX_PAYLOAD_BYTES` 给出错误脉冲

## 当前不做

- 校验和
- 多字节长度
- 转义字符
- 超时丢帧
- 回传应答

## 输出语义

- `o_frame_start`：检测到 `SOF` 后拉高 1 个周期
- `o_payload_valid`：每个 payload 字节输出时拉高 1 个周期
- `o_frame_done`：最后一个 payload 字节到达时拉高 1 个周期
- `o_error`：非法长度时拉高 1 个周期

