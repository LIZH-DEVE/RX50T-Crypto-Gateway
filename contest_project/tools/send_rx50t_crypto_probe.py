import argparse
import sys
import time

try:
    import serial
except ImportError as exc:  # pragma: no cover
    raise SystemExit(
        "pyserial is required. Install it with: py -3 -m pip install pyserial"
    ) from exc


AES128_PT = bytes.fromhex("00 11 22 33 44 55 66 77 88 99 aa bb cc dd ee ff")
AES128_CT = bytes.fromhex("69 c4 e0 d8 6a 7b 04 30 d8 cd b7 80 70 b4 c5 5a")
SM4_PT = bytes.fromhex("01 23 45 67 89 ab cd ef fe dc ba 98 76 54 32 10")
SM4_CT = bytes.fromhex("68 1e df 34 d2 06 96 5e 86 b3 e9 4f 53 6e 42 46")


def build_frame(payload: bytes) -> bytes:
    if not payload:
        raise ValueError("payload must not be empty")
    if len(payload) > 32:
        raise ValueError("payload length must be <= 32 bytes")
    return bytes([0x55, len(payload)]) + payload


def read_exact(ser: serial.Serial, expected_len: int, timeout_s: float) -> bytes:
    deadline = time.time() + timeout_s
    buf = bytearray()
    while time.time() < deadline and len(buf) < expected_len:
        chunk = ser.read(expected_len - len(buf))
        if chunk:
            buf.extend(chunk)
    return bytes(buf)


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
        "--expect-stats",
        help="Expected counters as total,acl,aes,sm4,err for --query-stats, e.g. 3,1,1,1,1",
    )
    parser.add_argument("--timeout", type=float, default=3.0, help="Read timeout in seconds")
    args = parser.parse_args()

    mode_count = sum(
        1
        for flag in (
            args.sm4_known_vector,
            args.aes_known_vector,
            args.block_ascii is not None,
            args.invalid_selector,
            args.query_stats,
        )
        if flag
    )
    if mode_count != 1:
        raise SystemExit("Choose exactly one of --sm4-known-vector, --aes-known-vector, --block-ascii, --invalid-selector, or --query-stats")

    if args.sm4_known_vector:
        tx = build_frame(SM4_PT)
        expected = SM4_CT
    elif args.aes_known_vector:
        tx = build_frame(b"A" + AES128_PT)
        expected = AES128_CT
    elif args.invalid_selector:
        tx = build_frame(b"Q" + AES128_PT)
        expected = b"E\n"
    elif args.query_stats:
        tx = build_frame(b"?")
        if args.expect_stats:
            parts = [int(part, 0) for part in args.expect_stats.split(",")]
            if len(parts) != 5:
                raise SystemExit("--expect-stats requires 5 comma-separated values: total,acl,aes,sm4,err")
            for value in parts:
                if not 0 <= value <= 255:
                    raise SystemExit("--expect-stats values must be between 0 and 255")
            expected = bytes([0x53, *parts, 0x0A])
        else:
            expected = None
    else:
        payload = args.block_ascii.encode("ascii")
        tx = build_frame(payload)
        expected = b"D\n"

    print(f"[TX] {tx.hex(' ')}")
    if expected is None:
        print("[EXPECT] stats response with 5 counters")
    else:
        print(f"[EXPECT] {expected.hex(' ')}")

    with serial.Serial(args.port, args.baud, timeout=0.1) as ser:
        ser.reset_input_buffer()
        ser.reset_output_buffer()
        ser.write(tx)
        ser.flush()
        rx_len = 7 if args.query_stats else len(expected)
        rx = read_exact(ser, rx_len, args.timeout)

    print(f"[RX] {rx.hex(' ')}")
    if args.query_stats and expected is None:
        if len(rx) == 7 and rx[:1] == b"S" and rx[-1:] == b"\n":
            total, acl, aes, sm4, err = rx[1], rx[2], rx[3], rx[4], rx[5]
            print(f"[STATS] total={total} acl={acl} aes={aes} sm4={sm4} err={err}")
            print("[PASS] stats query response matched format.")
            return 0
    elif rx == expected:
        print("[PASS] crypto probe response matched.")
        return 0

    print("[FAIL] crypto probe response mismatch.")
    return 1


if __name__ == "__main__":
    sys.exit(main())
