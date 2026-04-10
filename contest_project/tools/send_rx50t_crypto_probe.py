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
    StatsCounters,
    case_aes_eight_block_vector,
    case_aes_four_block_vector,
    case_aes_known_vector,
    case_aes_two_block_vector,
    case_block_ascii,
    case_invalid_selector,
    case_query_rule_stats,
    case_query_stats,
    case_sm4_eight_block_vector,
    case_sm4_four_block_vector,
    case_sm4_known_vector,
    case_sm4_two_block_vector,
    format_hex,
    run_case_on_serial,
)


def main() -> int:
    parser = argparse.ArgumentParser(description="Send an AES/SM4 crypto probe frame to RX50T over UART.")
    parser.add_argument("--port", required=True, help="Serial port, e.g. COM12")
    parser.add_argument("--baud", type=int, default=115200, help="Baud rate")
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
        )
        if flag
    )
    if mode_count != 1:
        raise SystemExit(
            "Choose exactly one of --sm4-known-vector, --aes-known-vector, "
            "--sm4-two-block-vector, --aes-two-block-vector, --sm4-four-block-vector, "
            "--aes-four-block-vector, --sm4-eight-block-vector, --aes-eight-block-vector, "
            "--block-ascii, --invalid-selector, "
            "--query-stats, or --query-rule-stats"
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
    else:
        case = case_block_ascii(args.block_ascii)

    print(f"[TX] {format_hex(case.tx)}")
    if args.query_stats and case.expected is None:
        print("[EXPECT] stats response with 5 counters")
    elif args.query_rule_stats and case.expected is None:
        print("[EXPECT] rule stats response with 8 counters")
    else:
        print(f"[EXPECT] {format_hex(case.expected)}")

    with serial.Serial(args.port, args.baud, timeout=0.1) as ser:
        result = run_case_on_serial(ser, case, args.timeout)

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
    elif result.passed:
        print("[PASS] crypto probe response matched.")
        return 0

    print("[FAIL] crypto probe response mismatch.")
    return 1


if __name__ == "__main__":
    sys.exit(main())
