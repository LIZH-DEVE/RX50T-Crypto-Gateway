import argparse
import sys
import time

try:
    import serial
except ImportError as exc:  # pragma: no cover
    raise SystemExit(
        "pyserial is required. Install it with: py -3 -m pip install pyserial"
    ) from exc


def build_frame(payload: bytes) -> bytes:
    if not payload:
        raise ValueError("payload must not be empty")
    if len(payload) > 32:
        raise ValueError("payload length must be <= 32 bytes")
    return bytes([0x55, len(payload)]) + payload


def read_response(ser: serial.Serial, timeout_s: float) -> bytes:
    deadline = time.time() + timeout_s
    buf = bytearray()
    while time.time() < deadline:
        chunk = ser.read(1)
        if chunk:
            buf.extend(chunk)
            # Blocked path returns D\n, error path returns E\n, passthrough has no forced newline.
            if buf.endswith(b"D\n") or buf.endswith(b"E\n"):
                break
    return bytes(buf)


def main() -> int:
    parser = argparse.ArgumentParser(description="Send an ACL-probe frame to RX50T over UART.")
    parser.add_argument("--port", required=True, help="Serial port, e.g. COM12")
    parser.add_argument("--baud", type=int, default=115200, help="Baud rate")
    parser.add_argument("--pass-ascii", help="ASCII payload expected to pass through unchanged")
    parser.add_argument("--block-ascii", help="ASCII payload expected to be blocked by ACL")
    parser.add_argument("--timeout", type=float, default=2.0, help="Read timeout in seconds")
    args = parser.parse_args()

    mode_count = sum(
        1 for flag in (args.pass_ascii is not None, args.block_ascii is not None) if flag
    )
    if mode_count != 1:
        raise SystemExit("Choose exactly one of --pass-ascii or --block-ascii")

    if args.pass_ascii is not None:
        payload = args.pass_ascii.encode("ascii")
        expected = payload
    else:
        payload = args.block_ascii.encode("ascii")
        expected = b"D\n"

    tx = build_frame(payload)

    print(f"[TX] {tx.hex(' ')}")
    print(f"[EXPECT] {expected.hex(' ')}")

    with serial.Serial(args.port, args.baud, timeout=0.1) as ser:
        ser.reset_input_buffer()
        ser.reset_output_buffer()
        ser.write(tx)
        ser.flush()
        rx = read_response(ser, args.timeout)

    print(f"[RX] {rx.hex(' ')}")
    if rx == expected:
        print("[PASS] acl probe response matched.")
        return 0

    print("[FAIL] acl probe response mismatch.")
    return 1


if __name__ == "__main__":
    sys.exit(main())
