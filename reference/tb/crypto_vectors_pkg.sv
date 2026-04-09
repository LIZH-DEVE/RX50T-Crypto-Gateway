package crypto_vectors_pkg;
    // AES-128 NIST known answer test vectors.
    localparam logic [127:0] AES128_KEY = 128'h000102030405060708090a0b0c0d0e0f;
    localparam logic [127:0] AES128_PT  = 128'h00112233445566778899aabbccddeeff;
    localparam logic [127:0] AES128_CT  = 128'h69c4e0d86a7b0430d8cdb78070b4c55a;

    // SM4 GM/T 0002-2012 known answer test vectors.
    localparam logic [127:0] SM4_KEY = 128'h0123456789abcdeffedcba9876543210;
    localparam logic [127:0] SM4_PT  = 128'h0123456789abcdeffedcba9876543210;
    localparam logic [127:0] SM4_CT  = 128'h681edf34d206965e86b3e94f536e4246;

    // SM4 key schedule checkpoints (encryption order).
    // Note: old debug expectations like rk0=F09279A1 are not GM/T values.
    localparam logic [31:0] SM4_RK_ENC_FIRST4 [0:3] = '{
        32'hf12186f9, 32'h41662b61, 32'h5a6ab19a, 32'h7ba92077
    };
    localparam logic [31:0] SM4_RK_ENC_LAST4 [0:3] = '{
        32'h428d3654, 32'h62293496, 32'h01cf72e5, 32'h9124a012
    };

    // SM4 key schedule checkpoints (decryption order, reversed mapping).
    localparam logic [31:0] SM4_RK_DEC_FIRST4 [0:3] = '{
        32'h9124a012, 32'h01cf72e5, 32'h62293496, 32'h428d3654
    };
    localparam logic [31:0] SM4_RK_DEC_LAST4 [0:3] = '{
        32'h7ba92077, 32'h5a6ab19a, 32'h41662b61, 32'hf12186f9
    };
endpackage
