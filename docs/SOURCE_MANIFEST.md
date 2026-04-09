# SOURCE_MANIFEST

下面列出从当前主仓库复制到 `jichuangsai` 的参考文件。

## 参考 RTL

### crypto
- `reference/rtl/core/crypto/aes.v`
- `reference/rtl/core/crypto/aes_core.v`
- `reference/rtl/core/crypto/aes_decipher_block.v`
- `reference/rtl/core/crypto/aes_encipher_block.v`
- `reference/rtl/core/crypto/aes_inv_sbox.v`
- `reference/rtl/core/crypto/aes_key_mem.v`
- `reference/rtl/core/crypto/aes_sbox.v`
- `reference/rtl/core/crypto/crypto_bridge_top.sv`
- `reference/rtl/core/crypto/get_cki.v`
- `reference/rtl/core/crypto/key_expansion.v`
- `reference/rtl/core/crypto/one_round_for_encdec.v`
- `reference/rtl/core/crypto/one_round_for_key_exp.v`
- `reference/rtl/core/crypto/sbox_replace.v`
- `reference/rtl/core/crypto/sm4_encdec.v`
- `reference/rtl/core/crypto/sm4_top.v`
- `reference/rtl/core/crypto/transform_for_encdec.v`
- `reference/rtl/core/crypto/transform_for_key_exp.v`

### security
- `reference/rtl/security/acl_match_engine.sv`
- `reference/rtl/security/acl_packet_filter.sv`

### support
- `reference/rtl/support/async_fifo.sv`
- `reference/rtl/support/gearbox_128_to_32.sv`

### display
- `reference/rtl/display/seven_seg_driver.sv`

## 参考 testbench

- `reference/tb/crypto_vectors_pkg.sv`
- `reference/tb/tb_acl_match_engine_sanity.sv`
- `reference/tb/tb_acl_packet_filter_sanity.sv`
- `reference/tb/tb_aes_core_encdec.sv`
- `reference/tb/tb_crypto_core.sv`
- `reference/tb/tb_seven_seg.sv`
- `reference/tb/tb_sm4_keyexp_gmt.sv`
- `reference/tb/tb_sm4_top_encdec.sv`

## 说明

- 这些文件是“算法和轻量模块参考源”，不是竞赛版完整系统
- 新的 `RX50T` 竞赛版开发应当在 `contest_project/` 下进行
- `contest_project/rtl/contest/` 里的新顶层和新接口不应继续依赖当前 SoC 包装
