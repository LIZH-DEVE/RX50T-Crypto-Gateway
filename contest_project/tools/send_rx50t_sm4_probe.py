import argparse
import sys
import time

try:
    import serial
except ImportError as exc:  # pragma: no cover
    raise SystemExit(
        "pyserial is required. Install it with: py -3 -m pip install pyserial"
    ) from exc


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
    parser = argparse.ArgumentParser(description="Send an SM4 probe frame to RX50T over UART.")
    parser.add_argument("--port", required=True, help="Serial port, e.g. COM12")
    parser.add_argument("--baud", type=int, default=115200, help="Baud rate")
    parser.add_argument(
        "--sm4-known-vector",
        action="store_true",
        help="Send the fixed 16-byte SM4 plaintext and expect the fixed ciphertext",
    )
    parser.add_argument(
        "--block-ascii",
        help="Send an ASCII payload expected to hit ACL block rule and return D\\n",
    )
    parser.add_argument("--timeout", type=float, default=3.0, help="Read timeout in seconds")
    args = parser.parse_args()

    mode_count = sum(1 for flag in (args.sm4_known_vector, args.block_ascii is not None) if flag)
    if mode_count != 1:
        raise SystemExit("Choose exactly one of --sm4-known-vector or --block-ascii")

    if args.sm4_known_vector:
        tx = build_frame(SM4_PT)
        expected = SM4_CT
    else:
        payload = args.block_ascii.encode("ascii")
        tx = build_frame(payload)
        expected = b"D\n"

    print(f"[TX] {tx.hex(' ')}")
    print(f"[EXPECT] {expected.hex(' ')}")

    with serial.Serial(args.port, args.baud, timeout=0.1) as ser:
        ser.reset_input_buffer()
        ser.reset_output_buffer()
        ser.write(tx)
        ser.flush()
        rx = read_exact(ser, len(expected), args.timeout)

    print(f"[RX] {rx.hex(' ')}")
    if rx == expected:
        print("[PASS] sm4 probe response matched.")
        return 0

    print("[FAIL] sm4 probe response mismatch.")
    return 1


if __name__ == "__main__":
    sys.exit(main())
