import argparse
import sys

try:
    import serial
except ImportError as exc:  # pragma: no cover
    raise SystemExit(
        "pyserial is required. Install it with: py -3 -m pip install pyserial"
    ) from exc

from crypto_gateway_protocol import (
    AclRuleCounters,
    BenchResult,
    PmuSnapshot,
    StatsCounters,
    case_clear_pmu,
    case_aes_eight_block_vector,
    case_aes_four_block_vector,
    case_aes_known_vector,
    case_aes_two_block_vector,
    case_block_ascii,
    case_force_run_onchip_bench,
    case_invalid_selector,
    query_trace_snapshot_on_serial,
    case_query_bench_result,
    case_query_pmu,
    case_query_rule_stats,
    case_query_stats,
    case_run_onchip_bench,
    case_sm4_eight_block_vector,
    case_sm4_four_block_vector,
    case_sm4_known_vector,
    case_sm4_two_block_vector,
    format_hex,
    run_host_case_on_serial,
    run_case_on_serial,
)


def _print_pmu_snapshot(snapshot: PmuSnapshot) -> None:
    clock_status = "GATED" if snapshot.clock_is_gated else "ACTIVE"
    print(
        "[PMU] "
        f"clk_hz={snapshot.clk_hz} "
        f"global={snapshot.global_cycles} "
        f"crypto_active={snapshot.crypto_active_cycles} "
        f"uart_tx_stall={snapshot.uart_tx_stall_cycles} "
        f"credit_block={snapshot.stream_credit_block_cycles} "
        f"acl_block_events={snapshot.acl_block_events} "
        f"stream_bytes_in={snapshot.stream_bytes_in} "
        f"stream_bytes_out={snapshot.stream_bytes_out} "
        f"stream_chunks={snapshot.stream_chunk_count} "
        f"gated_cycles={snapshot.crypto_clock_gated_cycles} "
        f"clock_flags=0x{snapshot.crypto_clock_status_flags:016X} "
        f"clock_status={clock_status}"
    )


def _print_trace_snapshot(snapshot) -> None:
    print(
        f"[TRACE] valid_entries={snapshot.meta.valid_entries} "
        f"write_ptr={snapshot.meta.write_ptr} wrapped={int(snapshot.meta.wrapped)} enabled={int(snapshot.meta.enabled)}"
    )
    for idx, entry in enumerate(snapshot.entries):
        print(
            f"[TRACE_EVT] idx={idx:03d} t_ms={entry.timestamp_ms:.3f} "
            f"code=0x{entry.event_code:02X} {entry.describe()}"
        )



def _print_bench_result(result: BenchResult, snapshot: PmuSnapshot | None = None) -> None:
    print(
        "[BENCH] "
        f"status={result.status_name} "
        f"algo={result.algo_name} "
        f"bytes={result.byte_count} "
        f"cycles={result.cycles} "
        f"crc32=0x{result.crc32:08X}"
    )
    if snapshot is not None:
        mbps = result.effective_mbps(snapshot.clk_hz)
        if mbps is not None:
            print(f"[BENCH_RATE] effective_mbps={mbps:.3f} clk_hz={snapshot.clk_hz}")
        print(
            "[PMU_RATIO] "
            f"hw_util={snapshot.crypto_utilization:.4f} "
            f"uart_stall={snapshot.uart_stall_ratio:.4f} "
            f"credit_block={snapshot.credit_block_ratio:.4f} "
            f"elapsed_ms={snapshot.elapsed_ms_from_hw:.3f}"
        )


def main() -> int:
    parser = argparse.ArgumentParser(description="Send an AES/SM4 crypto probe frame to RX50T over UART.")
    parser.add_argument("--port", required=True, help="Serial port, e.g. COM12")
    parser.add_argument("--baud", type=int, default=2_000_000, help="Baud rate")
    parser.add_argument(
        "--sm4-known-vector",
        action="store_true",
        help="Send the fixed 16-byte SM4 plaintext and expect the fixed SM4 ciphertext",
    )
    parser.add_argument(
        "--aes-known-vector",
        action="store_true",
        help="Send the explicit AES selector plus the fixed 16-byte AES plaintext",
    )
    parser.add_argument(
        "--sm4-two-block-vector",
        action="store_true",
        help="Send a fixed 32-byte SM4 plaintext and expect 32 ciphertext bytes",
    )
    parser.add_argument(
        "--aes-two-block-vector",
        action="store_true",
        help="Send the explicit AES selector plus a fixed 32-byte plaintext",
    )
    parser.add_argument(
        "--sm4-four-block-vector",
        action="store_true",
        help="Send a fixed 64-byte SM4 plaintext and expect 64 ciphertext bytes",
    )
    parser.add_argument(
        "--aes-four-block-vector",
        action="store_true",
        help="Send the explicit AES selector plus a fixed 64-byte plaintext",
    )
    parser.add_argument(
        "--sm4-eight-block-vector",
        action="store_true",
        help="Send a fixed 128-byte SM4 plaintext and expect 128 ciphertext bytes",
    )
    parser.add_argument(
        "--aes-eight-block-vector",
        action="store_true",
        help="Send the explicit AES selector plus a fixed 128-byte plaintext",
    )
    parser.add_argument(
        "--block-ascii",
        help="Send an ASCII payload expected to hit ACL block rule and return D\\n",
    )
    parser.add_argument(
        "--invalid-selector",
        action="store_true",
        help="Send an explicit 17-byte frame with an invalid selector and expect E\\n",
    )
    parser.add_argument(
        "--query-stats",
        action="store_true",
        help="Query the 8-bit counters and expect S total acl aes sm4 err newline",
    )
    parser.add_argument(
        "--query-rule-stats",
        action="store_true",
        help="Query the per-rule ACL counters and expect H x y z w p r t u newline",
    )
    parser.add_argument(
        "--query-pmu",
        action="store_true",
        help="Query the PMU hardware snapshot and print raw counters plus derived ratios",
    )
    parser.add_argument(
        "--clear-pmu",
        action="store_true",
        help="Clear the PMU hardware counters and expect 55 02 4A 00",
    )
    parser.add_argument(
        "--query-trace",
        action="store_true",
        help="Query the hardware trace buffer and print decoded trace events",
    )
    parser.add_argument(
        "--run-onchip-bench",
        action="store_true",
        help="Start a 1MiB on-chip AXIS benchmark session",
    )
    parser.add_argument(
        "--force-run-onchip-bench",
        action="store_true",
        help="Soft-abort the datapath, then start a 1MiB on-chip AXIS benchmark session",
    )
    parser.add_argument(
        "--query-bench",
        action="store_true",
        help="Query the latest on-chip AXIS benchmark result",
    )
    parser.add_argument(
        "--algo",
        type=str.lower,
        choices=("sm4", "aes"),
        help="Algorithm for --run-onchip-bench or --force-run-onchip-bench",
    )
    parser.add_argument(
        "--expect-stats",
        help="Expected counters as total,acl,aes,sm4,err for --query-stats, e.g. 3,1,1,1,1",
    )
    parser.add_argument(
        "--expect-rule-stats",
        help="Expected rule counters as x,y,z,w,p,r,t,u for --query-rule-stats",
    )
    parser.add_argument("--timeout", type=float, default=3.0, help="Read timeout in seconds")
    args = parser.parse_args()

    mode_count = sum(
        1
        for flag in (
            args.sm4_known_vector,
            args.aes_known_vector,
            args.sm4_two_block_vector,
            args.aes_two_block_vector,
            args.sm4_four_block_vector,
            args.aes_four_block_vector,
            args.sm4_eight_block_vector,
            args.aes_eight_block_vector,
            args.block_ascii is not None,
            args.invalid_selector,
            args.query_stats,
            args.query_rule_stats,
            args.query_pmu,
            args.clear_pmu,
            args.query_trace,
            args.run_onchip_bench,
            args.force_run_onchip_bench,
            args.query_bench,
        )
        if flag
    )
    if mode_count != 1:
        raise SystemExit(
            "Choose exactly one of --sm4-known-vector, --aes-known-vector, "
            "--sm4-two-block-vector, --aes-two-block-vector, --sm4-four-block-vector, "
            "--aes-four-block-vector, --sm4-eight-block-vector, --aes-eight-block-vector, "
            "--block-ascii, --invalid-selector, "
            "--query-stats, --query-rule-stats, --query-pmu, --clear-pmu, --query-trace, "
            "--run-onchip-bench, --force-run-onchip-bench, or --query-bench"
        )

    if args.sm4_known_vector:
        case = case_sm4_known_vector()
    elif args.aes_known_vector:
        case = case_aes_known_vector()
    elif args.sm4_two_block_vector:
        case = case_sm4_two_block_vector()
    elif args.aes_two_block_vector:
        case = case_aes_two_block_vector()
    elif args.sm4_four_block_vector:
        case = case_sm4_four_block_vector()
    elif args.aes_four_block_vector:
        case = case_aes_four_block_vector()
    elif args.sm4_eight_block_vector:
        case = case_sm4_eight_block_vector()
    elif args.aes_eight_block_vector:
        case = case_aes_eight_block_vector()
    elif args.invalid_selector:
        case = case_invalid_selector()
    elif args.query_stats:
        expected_stats = None
        if args.expect_stats:
            parts = [int(part, 0) for part in args.expect_stats.split(",")]
            if len(parts) != 5:
                raise SystemExit(
                    "--expect-stats requires 5 comma-separated values: total,acl,aes,sm4,err"
                )
            for value in parts:
                if not 0 <= value <= 255:
                    raise SystemExit("--expect-stats values must be between 0 and 255")
            expected_stats = StatsCounters(*parts)
        case = case_query_stats(expected_stats)
    elif args.query_rule_stats:
        expected_rule_stats = None
        if args.expect_rule_stats:
            parts = [int(part, 0) for part in args.expect_rule_stats.split(",")]
            if len(parts) != 8:
                raise SystemExit(
                    "--expect-rule-stats requires 8 comma-separated values: x,y,z,w,p,r,t,u"
                )
            for value in parts:
                if not 0 <= value <= 255:
                    raise SystemExit("--expect-rule-stats values must be between 0 and 255")
            expected_rule_stats = AclRuleCounters(*parts)
        case = case_query_rule_stats(expected_rule_stats)
    elif args.query_pmu:
        case = case_query_pmu()
    elif args.clear_pmu:
        case = case_clear_pmu()
    elif args.query_trace:
        case = None
    elif args.run_onchip_bench:
        if not args.algo:
            raise SystemExit("--algo is required with --run-onchip-bench")
        case = case_run_onchip_bench(args.algo)
    elif args.force_run_onchip_bench:
        if not args.algo:
            raise SystemExit("--algo is required with --force-run-onchip-bench")
        case = case_force_run_onchip_bench(args.algo)
    elif args.query_bench:
        case = case_query_bench_result()
    else:
        case = case_block_ascii(args.block_ascii)

    if args.query_trace:
        print("[TX] 55 01 54 + 16 paged trace reads")
        print("[EXPECT] trace metadata response plus paged trace data")
    else:
        print(f"[TX] {format_hex(case.tx)}")
    if not args.query_trace and args.query_stats and case.expected is None:
        print("[EXPECT] stats response with 5 counters")
    elif args.query_rule_stats and case.expected is None:
        print("[EXPECT] rule stats response with 8 counters")
    elif not args.query_trace and args.query_pmu and case.expected is None:
        print("[EXPECT] PMU snapshot response (schema v1/v2/v3)")
    elif not args.query_trace and args.clear_pmu and case.expected is None:
        print("[EXPECT] PMU clear ACK 55 02 4A 00")
    elif (args.run_onchip_bench or args.force_run_onchip_bench or args.query_bench) and case.expected is None:
        print("[EXPECT] benchmark result frame 55 14 62 01 status algo bytes cycles crc32")
    else:
        print(f"[EXPECT] {format_hex(case.expected)}")

    with serial.Serial(args.port, args.baud, timeout=0.1) as ser:
        if args.query_trace:
            trace_snapshot = query_trace_snapshot_on_serial(ser, args.timeout)
            result = None
            bench_pmu = None
        else:
            result = run_host_case_on_serial(ser, case, args.timeout, baud=args.baud)
            bench_pmu = None
            if result.bench_result is not None and result.bench_result.cycles > 0:
                pmu_result = run_case_on_serial(ser, case_query_pmu(), args.timeout)
                bench_pmu = pmu_result.pmu_snapshot

    if args.query_trace:
        _print_trace_snapshot(trace_snapshot)
        print("[PASS] trace snapshot query matched format.")
        return 0

    print(f"[RX] {format_hex(result.rx)}")
    if args.query_stats and case.expected is None:
        if result.stats is not None:
            print(
                f"[STATS] total={result.stats.total} acl={result.stats.acl} "
                f"aes={result.stats.aes} sm4={result.stats.sm4} err={result.stats.err}"
            )
            print("[PASS] stats query response matched format.")
            return 0
    elif args.query_rule_stats and case.expected is None:
        if result.rule_stats is not None:
            counts = result.rule_stats.as_dict()
            print(
                "[RULES] "
                + " ".join(f"{key}={counts[key]}" for key in ("X", "Y", "Z", "W", "P", "R", "T", "U"))
            )
            hot_rule, hot_hits = result.rule_stats.hot_rule()
            if hot_rule is None:
                print("[HOT] none")
            else:
                print(f"[HOT] {hot_rule}={hot_hits}")
            print("[PASS] rule stats query response matched format.")
            return 0
    elif args.query_pmu and case.expected is None:
        if result.pmu_snapshot is not None:
            _print_pmu_snapshot(result.pmu_snapshot)
            print("[PASS] PMU snapshot response matched format.")
            return 0
    elif args.clear_pmu and case.expected is None:
        if result.pmu_clear_ack is not None:
            print(f"[PMU_CLEAR] status={result.pmu_clear_ack.status}")
            print("[PASS] PMU clear ACK matched format.")
            return 0
    elif args.run_onchip_bench or args.force_run_onchip_bench or args.query_bench:
        if result.bench_result is not None:
            _print_bench_result(result.bench_result, bench_pmu)
            print("[PASS] benchmark result response matched format.")
            return 0
    elif result.passed:
        print("[PASS] crypto probe response matched.")
        return 0

    print("[FAIL] crypto probe response mismatch.")
    return 1


if __name__ == "__main__":
    sys.exit(main())
