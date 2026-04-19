import argparse
import sys
import time

try:
    import serial
except ImportError as exc:  # pragma: no cover
    raise SystemExit(
        "pyserial is required. Install it with: py -3 -m pip install pyserial"
    ) from exc


def build_frame_from_ascii(payload: str) -> bytes:
    raw = payload.encode("ascii")
    if not raw:
        raise ValueError("payload must not be empty")
    if len(raw) > 32:
        raise ValueError("payload length must be <= 32 bytes")
    return bytes([0x55, len(raw)]) + raw


def build_frame_from_hex(payload_hex: str) -> bytes:
    parts = payload_hex.replace(",", " ").split()
    raw = bytes(int(part, 16) for part in parts)
    if not raw:
        raise ValueError("hex payload must not be empty")
    if len(raw) > 32:
        raise ValueError("payload length must be <= 32 bytes")
    return bytes([0x55, len(raw)]) + raw


def read_response(ser: serial.Serial, timeout_s: float) -> bytes:
    deadline = time.time() + timeout_s
    buf = bytearray()
    while time.time() < deadline:
        chunk = ser.read(1)
        if chunk:
            buf.extend(chunk)
            if chunk == b"\n":
                break
    return bytes(buf)


def main() -> int:
    parser = argparse.ArgumentParser(description="Send a parser-probe frame to RX50T over UART.")
    parser.add_argument("--port", required=True, help="Serial port, for example COM7 or /dev/ttyUSB0")
    parser.add_argument("--baud", type=int, default=115200, help="Baud rate")
    parser.add_argument("--ascii", dest="ascii_payload", help="ASCII payload, e.g. ABC")
    parser.add_argument("--hex", dest="hex_payload", help="Hex payload bytes, e.g. '41 42 43'")
    parser.add_argument("--invalid-zero-len", action="store_true", help="Send 55 00 and expect E\\n")
    parser.add_argument("--timeout", type=float, default=2.0, help="Read timeout in seconds")
    args = parser.parse_args()

    mode_count = sum(
        1
        for flag in (
            args.ascii_payload is not None,
            args.hex_payload is not None,
            args.invalid_zero_len,
        )
        if flag
    )
    if mode_count != 1:
        raise SystemExit("Choose exactly one of --ascii, --hex, or --invalid-zero-len")

    if args.invalid_zero_len:
        tx = bytes([0x55, 0x00])
        expected = b"E\n"
    elif args.ascii_payload is not None:
        tx = build_frame_from_ascii(args.ascii_payload)
        expected = args.ascii_payload.encode("ascii") + b"\n"
    else:
        tx = build_frame_from_hex(args.hex_payload)
        expected = bytes(int(part, 16) for part in args.hex_payload.replace(",", " ").split()) + b"\n"

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
        print("[PASS] parser probe response matched.")
        return 0

    print("[FAIL] parser probe response mismatch.")
    return 1


if __name__ == "__main__":
    sys.exit(main())
