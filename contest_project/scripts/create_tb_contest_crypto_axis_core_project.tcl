if {[info exists ::env(RX50T_CRYPTO_AXIS_SIM_DIR)] && $::env(RX50T_CRYPTO_AXIS_SIM_DIR) ne ""} {
    set project_dir [file normalize $::env(RX50T_CRYPTO_AXIS_SIM_DIR)]
} else {
    set project_dir [file normalize "D:/FPGAhanjia/jichuangsai/contest_project/build/sim_tb_contest_crypto_axis_core"]
}
file mkdir $project_dir

create_project sim_tb_contest_crypto_axis_core $project_dir -part xc7a50tfgg484-1 -force

add_files -norecurse {
    D:/FPGAhanjia/jichuangsai/reference/rtl/core/crypto/aes_core.v
    D:/FPGAhanjia/jichuangsai/reference/rtl/core/crypto/aes_encipher_block.v
    D:/FPGAhanjia/jichuangsai/reference/rtl/core/crypto/aes_decipher_block.v
    D:/FPGAhanjia/jichuangsai/reference/rtl/core/crypto/aes_key_mem.v
    D:/FPGAhanjia/jichuangsai/reference/rtl/core/crypto/aes_sbox.v
    D:/FPGAhanjia/jichuangsai/reference/rtl/core/crypto/aes_inv_sbox.v
    D:/FPGAhanjia/jichuangsai/reference/rtl/core/crypto/sbox_replace.v
    D:/FPGAhanjia/jichuangsai/reference/rtl/core/crypto/one_round_for_encdec.v
    D:/FPGAhanjia/jichuangsai/reference/rtl/core/crypto/transform_for_encdec.v
    D:/FPGAhanjia/jichuangsai/reference/rtl/core/crypto/one_round_for_key_exp.v
    D:/FPGAhanjia/jichuangsai/reference/rtl/core/crypto/transform_for_key_exp.v
    D:/FPGAhanjia/jichuangsai/reference/rtl/core/crypto/get_cki.v
    D:/FPGAhanjia/jichuangsai/reference/rtl/core/crypto/key_expansion.v
    D:/FPGAhanjia/jichuangsai/reference/rtl/core/crypto/sm4_encdec.v
    D:/FPGAhanjia/jichuangsai/reference/rtl/core/crypto/sm4_top.v
    D:/FPGAhanjia/jichuangsai/contest_project/rtl/contest/contest_block_fifo.sv
    D:/FPGAhanjia/jichuangsai/contest_project/rtl/contest/contest_acl_axis_core.sv
    D:/FPGAhanjia/jichuangsai/contest_project/rtl/contest/contest_axis_block_packer.sv
    D:/FPGAhanjia/jichuangsai/contest_project/rtl/contest/contest_axis_block_unpacker.sv
    D:/FPGAhanjia/jichuangsai/contest_project/rtl/contest/contest_crypto_block_engine.sv
    D:/FPGAhanjia/jichuangsai/contest_project/rtl/contest/contest_crypto_axis_core.sv
}

add_files -fileset sim_1 -norecurse {
    D:/FPGAhanjia/jichuangsai/contest_project/tb/contest/tb_contest_crypto_axis_core.sv
}

set_property top tb_contest_crypto_axis_core [get_filesets sim_1]
update_compile_order -fileset sources_1
update_compile_order -fileset sim_1

launch_simulation -simset sim_1 -mode behavioral
run all
close_sim
close_project
exit
