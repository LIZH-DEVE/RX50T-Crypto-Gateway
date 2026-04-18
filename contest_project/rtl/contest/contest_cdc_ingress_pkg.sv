package contest_cdc_ingress_pkg;

    localparam integer CDC_META_KIND_W = 5;

    localparam [CDC_META_KIND_W-1:0] CDC_META_KIND_NONE           = 5'd0;
    localparam [CDC_META_KIND_W-1:0] CDC_META_KIND_NORMAL_PAYLOAD = 5'd1;
    localparam [CDC_META_KIND_W-1:0] CDC_META_KIND_STREAM_CAP     = 5'd2;
    localparam [CDC_META_KIND_W-1:0] CDC_META_KIND_STREAM_START   = 5'd3;
    localparam [CDC_META_KIND_W-1:0] CDC_META_KIND_STREAM_CHUNK   = 5'd4;
    localparam [CDC_META_KIND_W-1:0] CDC_META_KIND_PMU_QUERY      = 5'd5;
    localparam [CDC_META_KIND_W-1:0] CDC_META_KIND_PMU_CLEAR      = 5'd6;
    localparam [CDC_META_KIND_W-1:0] CDC_META_KIND_BENCH_QUERY    = 5'd7;
    localparam [CDC_META_KIND_W-1:0] CDC_META_KIND_BENCH_START    = 5'd8;
    localparam [CDC_META_KIND_W-1:0] CDC_META_KIND_BENCH_FORCE    = 5'd9;
    localparam [CDC_META_KIND_W-1:0] CDC_META_KIND_QUERY_STATS    = 5'd10;
    localparam [CDC_META_KIND_W-1:0] CDC_META_KIND_QUERY_HITS     = 5'd11;
    localparam [CDC_META_KIND_W-1:0] CDC_META_KIND_QUERY_KEYMAP   = 5'd12;
    localparam [CDC_META_KIND_W-1:0] CDC_META_KIND_TRACE_META     = 5'd13;
    localparam [CDC_META_KIND_W-1:0] CDC_META_KIND_TRACE_PAGE     = 5'd14;
    localparam [CDC_META_KIND_W-1:0] CDC_META_KIND_ACL_CFG        = 5'd15;
    localparam [CDC_META_KIND_W-1:0] CDC_META_KIND_PROTO_ERROR    = 5'd16;
    localparam [CDC_META_KIND_W-1:0] CDC_META_KIND_ABORT_FLUSH    = 5'd17;

    typedef struct packed {
        logic [CDC_META_KIND_W-1:0] kind;
        logic                       algo;
        logic [7:0]                 payload_len;
        logic [7:0]                 seq;
        logic [15:0]                total;
        logic [2:0]                 cfg_index;
        logic [127:0]               cfg_key;
        logic [3:0]                 trace_page_idx;
        logic                       bench_force;
        logic                       bench_algo_valid;
        logic [7:0]                 error_code;
    } cdc_meta_t;

    localparam integer CDC_META_W = $bits(cdc_meta_t);

    localparam [1:0] CDC_ACTION_KIND_NONE   = 2'd0;
    localparam [1:0] CDC_ACTION_KIND_ACCEPT = 2'd1;
    localparam [1:0] CDC_ACTION_KIND_DRAIN  = 2'd2;

    typedef struct packed {
        logic [1:0] kind;
        logic [7:0] payload_len;
    } cdc_action_t;

    localparam integer CDC_ACTION_W = $bits(cdc_action_t);

endpackage