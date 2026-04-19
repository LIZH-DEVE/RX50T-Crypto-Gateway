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
    if len(payload) > 255:
        raise ValueError("payload length must be <= 255 bytes")
    return bytes([0x55, len(payload)]) + payload


def read_framed_response(ser: serial.Serial, timeout_s: float) -> bytes:
    deadline = time.time() + timeout_s
    buf = bytearray()
    while time.time() < deadline:
        chunk = ser.read(1)
        if not chunk:
            continue
        if chunk == b"\x55" and len(buf) == 0:
            buf.extend(chunk)
            continue
        buf.extend(chunk)
        if len(buf) >= 2:
            payload_len = buf[1]
            if len(buf) >= payload_len + 2:
                break
    return bytes(buf)


def read_simple_response(ser: serial.Serial, timeout_s: float) -> bytes:
    deadline = time.time() + timeout_s
    buf = bytearray()
    while time.time() < deadline:
        chunk = ser.read(1)
        if chunk:
            buf.extend(chunk)
            if buf.endswith(b"D\n") or buf.endswith(b"E\n") or buf.endswith(b"\n"):
                break
    return bytes(buf)


def classify_probe_response(expected_block: bool, tx_payload: bytes, rx: bytes) -> tuple[bool, str]:
    if expected_block:
        if rx == b"D\n":
            return True, "block response"
        return False, f"expected block response D\\n, got {rx.hex(' ')}"

    if rx == b"D\n":
        return False, "payload was blocked unexpectedly"
    if rx == b"E\n":
        return False, "device returned error response"
    if len(rx) != len(tx_payload):
        return False, f"expected {len(tx_payload)}-byte ciphertext, got {len(rx)} bytes"
    return True, "16-byte ciphertext response"


def main() -> int:
    parser = argparse.ArgumentParser(description="Send ACL v2 probe frames to RX50T over UART.")
    parser.add_argument("--port", required=True, help="Serial port, for example COM7 or /dev/ttyUSB0")
    parser.add_argument("--baud", type=int, default=115200, help="Baud rate")
    parser.add_argument("--pass-hex", help="16B hex payload expected to pass through (32 hex chars)")
    parser.add_argument("--block-hex", help="16B hex payload expected to be blocked by ACL (32 hex chars)")
    parser.add_argument("--acl-slot", type=int, choices=range(8), help="ACL slot to query")
    parser.add_argument("--acl-write", help="Write 16B signature to slot: slot:hex32 format")
    parser.add_argument("--acl-keymap", action="store_true", help="Query ACL v2 key map (8x16B)")
    parser.add_argument("--acl-hits", action="store_true", help="Query ACL v2 hit counters (8x32-bit)")
    parser.add_argument("--timeout", type=float, default=2.0, help="Read timeout in seconds")
    args = parser.parse_args()

    if args.acl_write:
        parts = args.acl_write.split(":")
        if len(parts) != 2:
            raise SystemExit("--acl-write must be in format slot:hex32")
        slot = int(parts[0])
        hex_sig = parts[1].replace(" ", "")
        if len(hex_sig) != 32:
            raise SystemExit("ACL v2 signature must be exactly 32 hex chars (16 bytes)")
        sig_bytes = bytes.fromhex(hex_sig)
        payload = bytes([0x43, slot]) + sig_bytes
        tx = build_frame(payload)
        print(f"[TX ACL v2 WRITE] slot={slot} sig={hex_sig}")
        print(f"[TX FRAME] {tx.hex(' ')}")

        with serial.Serial(args.port, args.baud, timeout=0.1) as ser:
            ser.reset_input_buffer()
            ser.reset_output_buffer()
            ser.write(tx)
            ser.flush()
            rx = read_framed_response(ser, args.timeout)

        print(f"[RX] {rx.hex(' ')}")
        if rx and rx[0] == 0x55 and rx[2] == 0x43:
            print("[PASS] ACL v2 write ACK received")
            return 0
        print("[FAIL] ACL v2 write ACK not received")
        return 1

    if args.acl_keymap:
        tx = build_frame(bytes([0x4B]))
        print(f"[TX ACL v2 KEYMAP QUERY]")
        print(f"[TX FRAME] {tx.hex(' ')}")

        with serial.Serial(args.port, args.baud, timeout=0.1) as ser:
            ser.reset_input_buffer()
            ser.reset_output_buffer()
            ser.write(tx)
            ser.flush()
            rx = read_framed_response(ser, args.timeout)

        print(f"[RX] {rx.hex(' ')}")
        if rx and rx[0] == 0x55 and rx[2] == 0x4B:
            print(f"[PASS] ACL v2 keymap received ({len(rx)-3} bytes)")
            return 0
        print("[FAIL] ACL v2 keymap not received")
        return 1

    if args.acl_hits:
        tx = build_frame(bytes([0x48]))
        print(f"[TX ACL v2 HITS QUERY]")
        print(f"[TX FRAME] {tx.hex(' ')}")

        with serial.Serial(args.port, args.baud, timeout=0.1) as ser:
            ser.reset_input_buffer()
            ser.reset_output_buffer()
            ser.write(tx)
            ser.flush()
            rx = read_framed_response(ser, args.timeout)

        print(f"[RX] {rx.hex(' ')}")
        if rx and rx[0] == 0x55 and rx[2] == 0x48:
            print(f"[PASS] ACL v2 hit counters received")
            return 0
        print("[FAIL] ACL v2 hit counters not received")
        return 1

    if args.acl_slot is not None:
        slot = args.acl_slot
        tx = build_frame(bytes([0x4B]))
        print(f"[TX ACL v2 KEYMAP QUERY]")
        print(f"[TX FRAME] {tx.hex(' ')}")

        with serial.Serial(args.port, args.baud, timeout=0.1) as ser:
            ser.reset_input_buffer()
            ser.reset_output_buffer()
            ser.write(tx)
            ser.flush()
            rx = read_framed_response(ser, args.timeout)

        print(f"[RX] {rx.hex(' ')}")
        if rx and rx[0] == 0x55 and rx[2] == 0x4B and len(rx) >= 3 + (slot + 1) * 16:
            sig_start = 3 + slot * 16
            sig = rx[sig_start:sig_start + 16]
            print(f"[INFO] ACL v2 slot {slot} signature: {sig.hex()}")
            return 0
        print("[FAIL] Could not read ACL v2 keymap")
        return 1

    mode_count = sum(
        1 for flag in (args.pass_hex is not None, args.block_hex is not None) if flag
    )
    if mode_count != 1:
        raise SystemExit("Choose exactly one of --pass-hex or --block-hex (16B / 32 hex chars)")

    hex_payload = (args.pass_hex or args.block_hex).replace(" ", "")
    if len(hex_payload) != 32:
        raise SystemExit("ACL v2 payload must be exactly 32 hex chars (16 bytes)")

    payload = bytes.fromhex(hex_payload)
    expect_block = args.block_hex is not None

    tx = build_frame(payload)

    print(f"[TX] {tx.hex(' ')}")
    if expect_block:
        print("[EXPECT] 44 0a")
    else:
        print("[EXPECT] non-blocking 16-byte ciphertext")

    with serial.Serial(args.port, args.baud, timeout=0.1) as ser:
        ser.reset_input_buffer()
        ser.reset_output_buffer()
        ser.write(tx)
        ser.flush()
        rx = read_simple_response(ser, args.timeout)

    print(f"[RX] {rx.hex(' ')}")
    ok, detail = classify_probe_response(expect_block, payload, rx)
    if ok:
        print(f"[PASS] {detail}.")
        return 0

    print(f"[FAIL] {detail}.")
    return 1


if __name__ == "__main__":
    sys.exit(main())
