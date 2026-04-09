from __future__ import annotations

from dataclasses import dataclass
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
AES128_PT2 = bytes.fromhex("ff ee dd cc bb aa 99 88 77 66 55 44 33 22 11 00")
AES128_CT2 = bytes.fromhex("1b 87 23 78 79 5f 4f fd 77 28 55 fc 87 ca 96 4d")
SM4_PT2 = bytes.fromhex("00 11 22 33 44 55 66 77 88 99 aa bb cc dd ee ff")
SM4_CT2 = bytes.fromhex("09 32 5c 48 53 83 2d cb 93 37 a5 98 4f 67 1b 9a")


@dataclass(frozen=True)
class StatsCounters:
    total: int
    acl: int
    aes: int
    sm4: int
    err: int

    def as_bytes(self) -> bytes:
        return bytes([0x53, self.total, self.acl, self.aes, self.sm4, self.err, 0x0A])


@dataclass(frozen=True)
class ProbeCase:
    name: str
    tx: bytes
    response_len: int
    expected: bytes | None
    description: str
    kind: str = "raw"


@dataclass(frozen=True)
class ProbeResult:
    case: ProbeCase
    rx: bytes
    passed: bool
    duration_s: float
    stats: StatsCounters | None = None

    @property
    def tx(self) -> bytes:
        return self.case.tx

    @property
    def expected(self) -> bytes | None:
        return self.case.expected

    @property
    def throughput_mbps(self) -> float:
        if self.duration_s <= 0:
            return 0.0
        bits = (len(self.tx) + len(self.rx)) * 8
        return bits / self.duration_s / 1_000_000.0


def build_frame(payload: bytes) -> bytes:
    if not payload:
        raise ValueError("payload must not be empty")
    if len(payload) > 64:
        raise ValueError("payload length must be <= 64 bytes")
    return bytes([0x55, len(payload)]) + payload


def format_hex(data: bytes) -> str:
    return data.hex(" ") if data else ""


def parse_stats_response(raw: bytes) -> StatsCounters:
    if len(raw) != 7 or raw[:1] != b"S" or raw[-1:] != b"\n":
        raise ValueError(f"invalid stats response: {format_hex(raw)}")
    return StatsCounters(raw[1], raw[2], raw[3], raw[4], raw[5])


def read_exact(ser: serial.Serial, expected_len: int, timeout_s: float) -> bytes:
    deadline = time.time() + timeout_s
    buf = bytearray()
    while time.time() < deadline and len(buf) < expected_len:
        chunk = ser.read(expected_len - len(buf))
        if chunk:
            buf.extend(chunk)
    return bytes(buf)


def split_blocks_for_transport(payload: bytes) -> list[bytes]:
    if not payload:
        raise ValueError("payload must not be empty")
    if len(payload) % 16 != 0:
        raise ValueError("payload length must be a multiple of 16 bytes")
    chunks: list[bytes] = []
    index = 0
    while index < len(payload):
        remaining = len(payload) - index
        chunk_len = 32 if remaining >= 32 else 16
        chunks.append(payload[index : index + chunk_len])
        index += chunk_len
    return chunks


def case_sm4_known_vector() -> ProbeCase:
    return ProbeCase(
        name="SM4 Known Vector",
        tx=build_frame(SM4_PT),
        response_len=len(SM4_CT),
        expected=SM4_CT,
        description="Single-block SM4 known vector",
    )


def case_aes_known_vector() -> ProbeCase:
    return ProbeCase(
        name="AES Known Vector",
        tx=build_frame(b"A" + AES128_PT),
        response_len=len(AES128_CT),
        expected=AES128_CT,
        description="Single-block AES known vector",
    )


def case_sm4_two_block_vector() -> ProbeCase:
    return ProbeCase(
        name="SM4 32B Vector",
        tx=build_frame(SM4_PT + SM4_PT2),
        response_len=len(SM4_CT + SM4_CT2),
        expected=SM4_CT + SM4_CT2,
        description="Two-block SM4 known vector",
    )


def case_aes_two_block_vector() -> ProbeCase:
    return ProbeCase(
        name="AES 32B Vector",
        tx=build_frame(b"A" + AES128_PT + AES128_PT2),
        response_len=len(AES128_CT + AES128_CT2),
        expected=AES128_CT + AES128_CT2,
        description="Two-block AES known vector",
    )


def case_invalid_selector() -> ProbeCase:
    return ProbeCase(
        name="Invalid Selector",
        tx=build_frame(b"Q" + AES128_PT),
        response_len=2,
        expected=b"E\n",
        description="Protocol error path",
    )


def case_block_ascii(text: str = "XYZ") -> ProbeCase:
    payload = text.encode("ascii")
    return ProbeCase(
        name=f"ACL Block ({text})",
        tx=build_frame(payload),
        response_len=2,
        expected=b"D\n",
        description="ACL block response",
    )


def case_query_stats(expected: StatsCounters | None = None) -> ProbeCase:
    return ProbeCase(
        name="Query Stats",
        tx=build_frame(b"?"),
        response_len=7,
        expected=expected.as_bytes() if expected else None,
        description="Counter readback",
        kind="stats",
    )


def case_encrypt_block(algo: str, plaintext: bytes) -> ProbeCase:
    normalized = algo.strip().upper()
    if normalized not in {"AES", "SM4"}:
        raise ValueError("algo must be AES or SM4")
    if len(plaintext) not in {16, 32}:
        raise ValueError("plaintext length must be 16 or 32 bytes")
    if normalized == "AES":
        tx = build_frame(b"A" + plaintext)
    else:
        tx = build_frame(plaintext)
    return ProbeCase(
        name=f"{normalized} {len(plaintext)}B",
        tx=tx,
        response_len=len(plaintext),
        expected=None,
        description=f"{normalized} runtime encrypt",
    )


def run_case_on_serial(
    ser: serial.Serial,
    case: ProbeCase,
    timeout_s: float = 3.0,
) -> ProbeResult:
    ser.reset_input_buffer()
    ser.reset_output_buffer()
    started = time.perf_counter()
    ser.write(case.tx)
    ser.flush()
    rx = read_exact(ser, case.response_len, timeout_s)
    duration_s = max(time.perf_counter() - started, 1e-9)

    stats = None
    passed = False
    if case.kind == "stats":
        try:
            stats = parse_stats_response(rx)
            passed = case.expected is None or rx == case.expected
        except ValueError:
            passed = False
    else:
        passed = case.expected is None or rx == case.expected

    return ProbeResult(case=case, rx=rx, passed=passed, duration_s=duration_s, stats=stats)
