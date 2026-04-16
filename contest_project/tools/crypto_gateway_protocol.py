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
AES128_PT4 = AES128_PT + AES128_PT2 + AES128_PT + AES128_PT2
AES128_CT4 = AES128_CT + AES128_CT2 + AES128_CT + AES128_CT2
SM4_PT4 = SM4_PT + SM4_PT2 + SM4_PT + SM4_PT2
SM4_CT4 = SM4_CT + SM4_CT2 + SM4_CT + SM4_CT2
AES128_PT8 = AES128_PT4 + AES128_PT4
AES128_CT8 = AES128_CT4 + AES128_CT4
SM4_PT8 = SM4_PT4 + SM4_PT4
SM4_CT8 = SM4_CT4 + SM4_CT4
DEFAULT_ACL_RULE_BYTES = (0x58, 0x59, 0x5A, 0x57, 0x50, 0x52, 0x54, 0x55)
FORCE_BENCH_GUARD_BITS = 2 * 20 * 10
MIN_FORCE_BENCH_GUARD_S = 0.001


def display_rule_byte(value: int) -> str:
    if not 0 <= value <= 0xFF:
        raise ValueError("rule byte must be in 0..255")
    if 32 <= value <= 126:
        return chr(value)
    return f"0x{value:02X}"


DEFAULT_ACL_RULES = tuple(display_rule_byte(value) for value in DEFAULT_ACL_RULE_BYTES)


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
class AclWriteAck:
    index: int
    key: int

    def as_bytes(self) -> bytes:
        return bytes([0x43, self.index, self.key, 0x0A])


@dataclass(frozen=True)
class AclKeyMap:
    keys: tuple[int, ...]

    def __post_init__(self) -> None:
        if len(self.keys) != 8:
            raise ValueError("ACL key map must contain exactly 8 entries")

    def as_bytes(self) -> bytes:
        return bytes([0x4B, *self.keys, 0x0A])

    def display_labels(self) -> tuple[str, ...]:
        return tuple(display_rule_byte(value) for value in self.keys)


@dataclass(frozen=True)
class AclRuleCounters:
    counts: tuple[int, ...]

    def __post_init__(self) -> None:
        if len(self.counts) != 8:
            raise ValueError("ACL rule counters must contain exactly 8 entries")

    def as_bytes(self) -> bytes:
        return bytes([0x48, *self.counts, 0x0A])

    def as_dict(self, labels: tuple[str, ...] | None = None) -> dict[str, int]:
        active_labels = labels or DEFAULT_ACL_RULES
        return dict(zip(active_labels, self.counts))

    def hot_rule(self, labels: tuple[str, ...] | None = None) -> tuple[str | None, int]:
        counts = self.as_dict(labels)
        ordered = labels or DEFAULT_ACL_RULES
        rule = max(ordered, key=lambda item: counts[item])
        hits = counts[rule]
        return (rule if hits > 0 else None, hits)


@dataclass(frozen=True)
class AclV2WriteAck:
    slot: int
    signature: bytes

    def __post_init__(self) -> None:
        if not 0 <= self.slot <= 7:
            raise ValueError("ACL slot must be in 0..7")
        if len(self.signature) != 16:
            raise ValueError("ACL v2 signature must be exactly 16 bytes")

    def as_bytes(self) -> bytes:
        return bytes([0x55, 0x12, 0x43, self.slot]) + self.signature


@dataclass(frozen=True)
class AclV2KeyMap:
    signatures: tuple[bytes, ...]

    def __post_init__(self) -> None:
        if len(self.signatures) != 8:
            raise ValueError("ACL v2 key map must contain exactly 8 signatures")
        for sig in self.signatures:
            if len(sig) != 16:
                raise ValueError("Each ACL v2 signature must be exactly 16 bytes")

    def as_bytes(self) -> bytes:
        return bytes([0x55, 0x81, 0x4B]) + b"".join(self.signatures)

    def display_hex(self) -> tuple[str, ...]:
        return tuple(sig.hex() for sig in self.signatures)


@dataclass(frozen=True)
class AclV2HitCounters:
    counts: tuple[int, ...]

    def __post_init__(self) -> None:
        if len(self.counts) != 8:
            raise ValueError("ACL v2 hit counters must contain exactly 8 entries")

    def as_bytes(self) -> bytes:
        payload = bytearray([0x55, 0x21, 0x48])
        for count in self.counts:
            payload.extend(count.to_bytes(4, "big"))
        return bytes(payload)

    def as_dict(self) -> dict[int, int]:
        return {i: count for i, count in enumerate(self.counts)}



TRACE_DEPTH = 256
TRACE_PAGE_ENTRIES = 16
TRACE_PAGE_COUNT = TRACE_DEPTH // TRACE_PAGE_ENTRIES

TRACE_EVT_STREAM_START = 0x01
TRACE_EVT_STREAM_STOP = 0x02
TRACE_EVT_ACL_BLOCK = 0x03
TRACE_EVT_FATAL = 0x04
TRACE_EVT_BENCH_START = 0x05
TRACE_EVT_BENCH_DONE = 0x06
TRACE_EVT_ACL_CFG_ACK = 0x07
TRACE_EVT_CLOCK_GATED = 0x08
TRACE_EVT_CLOCK_ACTIVE = 0x09


@dataclass(frozen=True)
class TraceEntry:
    timestamp_ms: int
    event_code: int
    arg0: int
    arg1: int

    @classmethod
    def from_bytes(cls, raw: bytes) -> "TraceEntry":
        if len(raw) != 8:
            raise ValueError("Trace entry must be exactly 8 bytes")
        return cls(
            timestamp_ms=int.from_bytes(raw[0:4], "big"),
            event_code=raw[4],
            arg0=raw[5],
            arg1=int.from_bytes(raw[6:8], "big"),
        )

    def as_bytes(self) -> bytes:
        return (
            self.timestamp_ms.to_bytes(4, "big")
            + bytes([self.event_code, self.arg0])
            + self.arg1.to_bytes(2, "big")
        )

    @property
    def event_name(self) -> str:
        names = {
            TRACE_EVT_STREAM_START: "STREAM_START",
            TRACE_EVT_STREAM_STOP: "STREAM_STOP",
            TRACE_EVT_ACL_BLOCK: "ACL_BLOCK",
            TRACE_EVT_FATAL: "FATAL",
            TRACE_EVT_BENCH_START: "BENCH_START",
            TRACE_EVT_BENCH_DONE: "BENCH_DONE",
            TRACE_EVT_ACL_CFG_ACK: "ACL_CFG_ACK",
            TRACE_EVT_CLOCK_GATED: "CLOCK_GATED",
            TRACE_EVT_CLOCK_ACTIVE: "CLOCK_ACTIVE",
        }
        return names.get(self.event_code, f"UNKNOWN_0x{self.event_code:02X}")

    def describe(self) -> str:
        if self.event_code == TRACE_EVT_STREAM_START:
            algo = "AES" if (self.arg0 & 0x1) else "SM4"
            return f"STREAM_START algo={algo} chunks={self.arg1}"
        if self.event_code == TRACE_EVT_STREAM_STOP:
            status_names = {0: "OK", 1: "BLOCK", 2: "ERROR", 3: "FATAL"}
            status = status_names.get(self.arg0, f"0x{self.arg0:02X}")
            return f"STREAM_STOP status={status} acked={self.arg1}"
        if self.event_code == TRACE_EVT_ACL_BLOCK:
            return f"ACL_BLOCK slot={self.arg0}"
        if self.event_code == TRACE_EVT_FATAL:
            reasons = {0x01: "Stream Watchdog Timeout", 0x02: "Crypto Watchdog Timeout"}
            return f"FATAL_0x{self.arg0:02X} {reasons.get(self.arg0, 'Unknown Fatal')}"
        if self.event_code == TRACE_EVT_BENCH_START:
            algo = "AES" if (self.arg0 & 0x1) else "SM4"
            forced = 1 if (self.arg0 & 0x2) else 0
            return f"BENCH_START algo={algo} force={forced} kib={self.arg1}"
        if self.event_code == TRACE_EVT_BENCH_DONE:
            status_names = {0: "OK", 1: "BUSY", 2: "TIMEOUT", 3: "INTERNAL", 4: "NO_RESULT"}
            algo = "AES" if (self.arg1 & 0x1) else "SM4"
            status = status_names.get(self.arg0, f"0x{self.arg0:02X}")
            return f"BENCH_DONE status={status} algo={algo}"
        if self.event_code == TRACE_EVT_ACL_CFG_ACK:
            return f"ACL_CFG_ACK slot={self.arg0}"
        if self.event_code == TRACE_EVT_CLOCK_GATED:
            return "CLOCK_GATED"
        if self.event_code == TRACE_EVT_CLOCK_ACTIVE:
            return "CLOCK_ACTIVE"
        return f"{self.event_name} arg0=0x{self.arg0:02X} arg1=0x{self.arg1:04X}"


@dataclass(frozen=True)
class TraceMeta:
    version: int
    valid_entries: int
    write_ptr: int
    flags: int

    def as_bytes(self) -> bytes:
        return bytes([0x55, 0x06, 0x54, self.version]) + self.valid_entries.to_bytes(2, "big") + bytes([self.write_ptr, self.flags])

    @property
    def wrapped(self) -> bool:
        return bool(self.flags & 0x1)

    @property
    def enabled(self) -> bool:
        return bool(self.flags & 0x2)


@dataclass(frozen=True)
class TracePage:
    page_idx: int
    entry_count: int
    flags: int
    entries: tuple[TraceEntry, ...]

    def __post_init__(self) -> None:
        if not 0 <= self.page_idx < TRACE_PAGE_COUNT:
            raise ValueError("Trace page index out of range")
        if not 0 <= self.entry_count <= TRACE_PAGE_ENTRIES:
            raise ValueError("Trace page entry count out of range")
        if len(self.entries) != TRACE_PAGE_ENTRIES:
            raise ValueError("Trace page must contain exactly 16 entries")

    def as_bytes(self) -> bytes:
        payload = bytearray([0x55, 0x85, 0x54, 0x02, self.page_idx, self.entry_count, self.flags])
        for entry in self.entries:
            payload.extend(entry.as_bytes())
        return bytes(payload)


def reconstruct_trace_entries(meta: TraceMeta, pages: tuple[TracePage, ...]) -> tuple[TraceEntry, ...]:
    page_map = {page.page_idx: page for page in pages}
    for idx in range(TRACE_PAGE_COUNT):
        if idx not in page_map:
            raise ValueError(f"missing trace page {idx}")
    flat = []
    for page_idx in range(TRACE_PAGE_COUNT):
        flat.extend(page_map[page_idx].entries)
    valid = min(meta.valid_entries, TRACE_DEPTH)
    if valid <= 0:
        return tuple()
    if meta.wrapped:
        start = meta.write_ptr % TRACE_DEPTH
        ordered = flat[start:] + flat[:start]
        return tuple(ordered[:valid])
    return tuple(flat[:valid])


@dataclass(frozen=True)
class TraceSnapshot:
    meta: TraceMeta
    pages: tuple[TracePage, ...]
    entries: tuple[TraceEntry, ...]


@dataclass(frozen=True)
class PmuSnapshot:
    clk_hz: int
    global_cycles: int
    crypto_active_cycles: int
    uart_tx_stall_cycles: int
    stream_credit_block_cycles: int
    acl_block_events: int
    version: int = 2
    stream_bytes_in: int | None = None
    stream_bytes_out: int | None = None
    stream_chunk_count: int | None = None
    crypto_clock_gated_cycles: int | None = None
    crypto_clock_status_flags: int | None = None

    def as_bytes(self) -> bytes:
        payload = bytearray([0x50, self.version])
        payload.extend(self.clk_hz.to_bytes(4, "big"))
        payload.extend(self.global_cycles.to_bytes(8, "big"))
        payload.extend(self.crypto_active_cycles.to_bytes(8, "big"))
        payload.extend(self.uart_tx_stall_cycles.to_bytes(8, "big"))
        payload.extend(self.stream_credit_block_cycles.to_bytes(8, "big"))
        payload.extend(self.acl_block_events.to_bytes(8, "big"))
        if self.version >= 2:
            payload.extend((self.stream_bytes_in or 0).to_bytes(8, "big"))
            payload.extend((self.stream_bytes_out or 0).to_bytes(8, "big"))
            payload.extend((self.stream_chunk_count or 0).to_bytes(8, "big"))
        if self.version >= 3:
            payload.extend((self.crypto_clock_gated_cycles or 0).to_bytes(8, "big"))
            payload.extend((self.crypto_clock_status_flags or 0).to_bytes(8, "big"))
        return bytes([0x55, len(payload)]) + bytes(payload)

    @property
    def clock_is_gated(self) -> bool:
        return bool((self.crypto_clock_status_flags or 0) & 0x1)

    @property
    def clock_gating_enabled(self) -> bool:
        return bool((self.crypto_clock_status_flags or 0) & 0x2)

    @property
    def crypto_utilization(self) -> float:
        if self.global_cycles <= 0:
            return 0.0
        return self.crypto_active_cycles / self.global_cycles

    @property
    def uart_stall_ratio(self) -> float:
        if self.global_cycles <= 0:
            return 0.0
        return self.uart_tx_stall_cycles / self.global_cycles

    @property
    def credit_block_ratio(self) -> float:
        if self.global_cycles <= 0:
            return 0.0
        return self.stream_credit_block_cycles / self.global_cycles

    @property
    def elapsed_ms_from_hw(self) -> float:
        if self.clk_hz <= 0:
            return 0.0
        return (self.global_cycles / self.clk_hz) * 1000.0


@dataclass(frozen=True)
class PmuClearAck:
    status: int

    def as_bytes(self) -> bytes:
        return bytes([0x55, 0x02, 0x4A, self.status])


@dataclass(frozen=True)
class BenchResult:
    version: int
    status: int
    algo: int
    byte_count: int
    cycles: int
    crc32: int

    def as_bytes(self) -> bytes:
        payload = bytearray([0x62, self.version, self.status, self.algo])
        payload.extend(self.byte_count.to_bytes(4, "big"))
        payload.extend(self.cycles.to_bytes(8, "big"))
        payload.extend(self.crc32.to_bytes(4, "big"))
        return bytes([0x55, len(payload)]) + bytes(payload)

    @property
    def algo_name(self) -> str:
        if self.algo == 0x41:
            return "AES"
        if self.algo == 0x53:
            return "SM4"
        return f"0x{self.algo:02X}"

    @property
    def status_name(self) -> str:
        mapping = {
            0x00: "SUCCESS",
            0x01: "BUSY",
            0x02: "TIMEOUT",
            0x03: "INTERNAL",
            0x04: "NO_RESULT",
        }
        return mapping.get(self.status, f"0x{self.status:02X}")

    def effective_mbps(self, clk_hz: int) -> float | None:
        if clk_hz <= 0 or self.cycles <= 0:
            return None
        return (self.byte_count * 8 * clk_hz) / self.cycles / 1_000_000.0


@dataclass(frozen=True)
class ProbeCase:
    name: str
    tx: bytes
    response_len: int
    expected: bytes | None
    description: str
    kind: str = "raw"
    response_mode: str = "fixed"
    response_opcode: int | None = None


@dataclass(frozen=True)
class ProbeResult:
    case: ProbeCase
    rx: bytes
    passed: bool
    duration_s: float
    stats: StatsCounters | None = None
    rule_stats: AclRuleCounters | None = None
    acl_write_ack: AclWriteAck | None = None
    acl_key_map: AclKeyMap | None = None
    acl_v2_write_ack: AclV2WriteAck | None = None
    acl_v2_key_map: AclV2KeyMap | None = None
    acl_v2_hits: AclV2HitCounters | None = None
    trace_meta: TraceMeta | None = None
    trace_page: TracePage | None = None
    pmu_snapshot: PmuSnapshot | None = None
    pmu_clear_ack: PmuClearAck | None = None
    bench_result: BenchResult | None = None
    fatal_error: FatalErrorResponse | None = None

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


@dataclass(frozen=True)
class FileChunkPlan:
    chunks: tuple[bytes, ...]
    original_size: int
    padded_size: int
    pad_bytes: int

    @property
    def chunk_count(self) -> int:
        return len(self.chunks)


@dataclass(frozen=True)
class StreamCapabilities:
    chunk_size: int
    window: int
    flags: int


@dataclass(frozen=True)
class StreamStartAck:
    status: int


@dataclass(frozen=True)
class StreamCipherResponse:
    seq: int
    ciphertext: bytes


@dataclass(frozen=True)
class StreamBlockResponse:
    seq: int
    slot: int


@dataclass(frozen=True)
class FatalErrorResponse:
    code: int

    def as_bytes(self) -> bytes:
        return bytes([0x55, 0x02, 0xEE, self.code])


@dataclass(frozen=True)
class StreamErrorResponse:
    code: int


def build_frame(payload: bytes) -> bytes:
    if not payload:
        raise ValueError("payload must not be empty")
    if len(payload) > 255:
        raise ValueError("payload length must be <= 255 bytes")
    return bytes([0x55, len(payload)]) + payload


def _normalize_algo_tag(algo: str) -> int:
    normalized = algo.strip().upper()
    if normalized == "AES":
        return 0x41
    if normalized == "SM4":
        return 0x53
    raise ValueError("algo must be AES or SM4")


def build_stream_capability_query() -> bytes:
    return build_frame(b"W")


def build_stream_start_frame(algo: str, total_chunks: int) -> bytes:
    if not 0 <= total_chunks <= 0xFFFF:
        raise ValueError("total_chunks must be in 0..65535")
    return build_frame(bytes([0x4D, _normalize_algo_tag(algo), (total_chunks >> 8) & 0xFF, total_chunks & 0xFF]))


def build_stream_chunk_frame(seq: int, payload: bytes) -> bytes:
    if not 0 <= seq <= 0xFF:
        raise ValueError("seq must be in 0..255")
    if len(payload) != 128:
        raise ValueError("stream payload must be exactly 128 bytes")
    return build_frame(bytes([seq]) + payload)


def format_hex(data: bytes) -> str:
    return data.hex(" ") if data else ""


def extract_first_payload_key(frame: bytes) -> str | None:
    if len(frame) < 3 or frame[0] != 0x55:
        return None
    payload_len = frame[1]
    if payload_len < 1 or len(frame) < payload_len + 2:
        return None
    first = frame[2]
    if 32 <= first <= 126:
        return chr(first)
    return f"0x{first:02X}"


def parse_rule_byte_input(text: str) -> int:
    candidate = text.strip()
    if not candidate:
        raise ValueError("rule byte input must not be empty")
    if candidate.lower().startswith("0x"):
        if len(candidate) != 4:
            raise ValueError("hex rule byte must be in the form 0xNN")
        return int(candidate, 16)
    if len(candidate) != 1:
        raise ValueError("ASCII rule byte input must be exactly one character")
    value = ord(candidate)
    if not 0 <= value <= 0xFF:
        raise ValueError("rule byte must fit in one byte")
    return value


def parse_stats_response(raw: bytes) -> StatsCounters:
    if len(raw) != 7 or raw[:1] != b"S" or raw[-1:] != b"\n":
        raise ValueError(f"invalid stats response: {format_hex(raw)}")
    return StatsCounters(raw[1], raw[2], raw[3], raw[4], raw[5])


def parse_rule_stats_response(raw: bytes) -> AclRuleCounters:
    if len(raw) != 10 or raw[:1] != b"H" or raw[-1:] != b"\n":
        raise ValueError(f"invalid rule stats response: {format_hex(raw)}")
    return AclRuleCounters(tuple(raw[1:9]))


def parse_acl_write_ack(raw: bytes) -> AclWriteAck:
    if len(raw) != 4 or raw[:1] != b"C" or raw[-1:] != b"\n":
        raise ValueError(f"invalid ACL write ACK: {format_hex(raw)}")
    return AclWriteAck(index=raw[1], key=raw[2])


def parse_acl_key_map_response(raw: bytes) -> AclKeyMap:
    if len(raw) != 10 or raw[:1] != b"K" or raw[-1:] != b"\n":
        raise ValueError(f"invalid ACL key-map response: {format_hex(raw)}")
    return AclKeyMap(tuple(raw[1:9]))


def parse_acl_v2_write_ack(raw: bytes) -> AclV2WriteAck:
    if len(raw) != 20 or raw[0] != 0x55 or raw[1] != 0x12 or raw[2] != 0x43:
        raise ValueError(f"invalid ACL v2 write ACK: {format_hex(raw)}")
    slot = raw[3]
    signature = raw[4:20]
    return AclV2WriteAck(slot=slot, signature=signature)


def parse_acl_v2_keymap_response(raw: bytes) -> AclV2KeyMap:
    if len(raw) != 131 or raw[0] != 0x55 or raw[1] != 0x81 or raw[2] != 0x4B:
        raise ValueError(f"invalid ACL v2 key-map response: {format_hex(raw)}")
    signatures = []
    for i in range(8):
        offset = 3 + i * 16
        signatures.append(raw[offset:offset + 16])
    return AclV2KeyMap(tuple(signatures))


def parse_acl_v2_hits_response(raw: bytes) -> AclV2HitCounters:
    if len(raw) != 35 or raw[0] != 0x55 or raw[1] != 0x21 or raw[2] != 0x48:
        raise ValueError(f"invalid ACL v2 hits response: {format_hex(raw)}")
    counts = []
    for i in range(8):
        offset = 3 + i * 4
        counts.append(int.from_bytes(raw[offset:offset + 4], "big"))
    return AclV2HitCounters(tuple(counts))



def parse_trace_meta_response(raw: bytes) -> TraceMeta:
    if len(raw) != 8 or raw[0] != 0x55 or raw[1] != 0x06 or raw[2] != 0x54 or raw[3] != 0x01:
        raise ValueError(f"invalid trace meta response: {format_hex(raw)}")
    return TraceMeta(
        version=raw[3],
        valid_entries=int.from_bytes(raw[4:6], "big"),
        write_ptr=raw[6],
        flags=raw[7],
    )


def parse_trace_page_response(raw: bytes) -> TracePage:
    if len(raw) != 135 or raw[0] != 0x55 or raw[1] != 0x85 or raw[2] != 0x54 or raw[3] != 0x02:
        raise ValueError(f"invalid trace page response: {format_hex(raw)}")
    entries = []
    for i in range(TRACE_PAGE_ENTRIES):
        offset = 7 + i * 8
        entries.append(TraceEntry.from_bytes(raw[offset:offset + 8]))
    return TracePage(
        page_idx=raw[4],
        entry_count=raw[5],
        flags=raw[6],
        entries=tuple(entries),
    )


def parse_pmu_snapshot_response(raw: bytes) -> PmuSnapshot:
    if len(raw) < 4 or raw[0] != 0x55 or raw[2] != 0x50:
        raise ValueError(f"invalid PMU snapshot response: {format_hex(raw)}")
    version = raw[3]
    if version == 0x01:
        if len(raw) != 48 or raw[1] != 0x2E:
            raise ValueError(f"invalid PMU v1 snapshot response: {format_hex(raw)}")
        return PmuSnapshot(
            clk_hz=int.from_bytes(raw[4:8], "big"),
            global_cycles=int.from_bytes(raw[8:16], "big"),
            crypto_active_cycles=int.from_bytes(raw[16:24], "big"),
            uart_tx_stall_cycles=int.from_bytes(raw[24:32], "big"),
            stream_credit_block_cycles=int.from_bytes(raw[32:40], "big"),
            acl_block_events=int.from_bytes(raw[40:48], "big"),
            version=1,
        )
    if version == 0x02:
        if len(raw) != 72 or raw[1] != 0x46:
            raise ValueError(f"invalid PMU v2 snapshot response: {format_hex(raw)}")
        return PmuSnapshot(
            clk_hz=int.from_bytes(raw[4:8], "big"),
            global_cycles=int.from_bytes(raw[8:16], "big"),
            crypto_active_cycles=int.from_bytes(raw[16:24], "big"),
            uart_tx_stall_cycles=int.from_bytes(raw[24:32], "big"),
            stream_credit_block_cycles=int.from_bytes(raw[32:40], "big"),
            acl_block_events=int.from_bytes(raw[40:48], "big"),
            stream_bytes_in=int.from_bytes(raw[48:56], "big"),
            stream_bytes_out=int.from_bytes(raw[56:64], "big"),
            stream_chunk_count=int.from_bytes(raw[64:72], "big"),
            version=2,
        )
    if version == 0x03:
        if len(raw) != 88 or raw[1] != 0x56:
            raise ValueError(f"invalid PMU v3 snapshot response: {format_hex(raw)}")
        return PmuSnapshot(
            clk_hz=int.from_bytes(raw[4:8], "big"),
            global_cycles=int.from_bytes(raw[8:16], "big"),
            crypto_active_cycles=int.from_bytes(raw[16:24], "big"),
            uart_tx_stall_cycles=int.from_bytes(raw[24:32], "big"),
            stream_credit_block_cycles=int.from_bytes(raw[32:40], "big"),
            acl_block_events=int.from_bytes(raw[40:48], "big"),
            stream_bytes_in=int.from_bytes(raw[48:56], "big"),
            stream_bytes_out=int.from_bytes(raw[56:64], "big"),
            stream_chunk_count=int.from_bytes(raw[64:72], "big"),
            crypto_clock_gated_cycles=int.from_bytes(raw[72:80], "big"),
            crypto_clock_status_flags=int.from_bytes(raw[80:88], "big"),
            version=3,
        )
    raise ValueError(f"unsupported PMU schema version 0x{version:02X}: {format_hex(raw)}")


def parse_pmu_clear_ack(raw: bytes) -> PmuClearAck:
    if len(raw) != 4 or raw[:3] != bytes([0x55, 0x02, 0x4A]):
        raise ValueError(f"invalid PMU clear ACK: {format_hex(raw)}")
    return PmuClearAck(status=raw[3])


def parse_bench_result_response(raw: bytes) -> BenchResult:
    if len(raw) != 22 or raw[:4] != bytes([0x55, 0x14, 0x62, 0x01]):
        raise ValueError(f"invalid bench result response: {format_hex(raw)}")
    return BenchResult(
        version=raw[3],
        status=raw[4],
        algo=raw[5],
        byte_count=int.from_bytes(raw[6:10], "big"),
        cycles=int.from_bytes(raw[10:18], "big"),
        crc32=int.from_bytes(raw[18:22], "big"),
    )


def parse_stream_response(raw: bytes) -> StreamCapabilities | StreamStartAck | StreamCipherResponse | StreamBlockResponse | StreamErrorResponse | FatalErrorResponse:
    if len(raw) < 3 or raw[0] != 0x55:
        raise ValueError(f"invalid stream frame: {format_hex(raw)}")

    payload_len = raw[1]
    if len(raw) != payload_len + 2:
        raise ValueError(f"stream payload length mismatch: {format_hex(raw)}")

    payload = raw[2:]
    if payload_len == 4 and payload[:1] == b"W":
        return StreamCapabilities(chunk_size=payload[1], window=payload[2], flags=payload[3])
    if payload_len == 2 and payload[:1] == b"M":
        return StreamStartAck(status=payload[1])
    if payload_len == 130 and payload[:1] == b"R":
        return StreamCipherResponse(seq=payload[1], ciphertext=payload[2:])
    if payload_len == 3 and payload[:1] == b"B":
        return StreamBlockResponse(seq=payload[1], slot=payload[2])
    if payload_len == 2 and payload[:1] == b"E":
        return StreamErrorResponse(code=payload[1])
    if payload_len == 2 and payload[:1] == b"\xEE":
        return FatalErrorResponse(code=payload[1])

    raise ValueError(f"unsupported stream response: {format_hex(raw)}")


def reset_serial_buffers(ser: serial.Serial) -> None:
    try:
        ser.reset_input_buffer()
        ser.reset_output_buffer()
    except AttributeError:  # pragma: no cover - older pyserial fallback
        ser.flushInput()
        ser.flushOutput()


def compute_force_guard_s(baud: int) -> float:
    if baud <= 0:
        raise ValueError("baud must be > 0")
    return max(MIN_FORCE_BENCH_GUARD_S, FORCE_BENCH_GUARD_BITS / float(baud))


def read_exact(ser: serial.Serial, expected_len: int, timeout_s: float) -> bytes:
    deadline = time.time() + timeout_s
    buf = bytearray()
    while time.time() < deadline and len(buf) < expected_len:
        chunk = ser.read(expected_len - len(buf))
        if chunk:
            buf.extend(chunk)
    return bytes(buf)


def _read_until_deadline(ser: serial.Serial, expected_len: int, deadline: float) -> bytes | None:
    buf = bytearray()
    while time.time() < deadline and len(buf) < expected_len:
        chunk = ser.read(expected_len - len(buf))
        if chunk:
            buf.extend(chunk)
    if len(buf) != expected_len:
        return None
    return bytes(buf)


def read_framed_response(
    ser: serial.Serial,
    timeout_s: float,
    *,
    expected_opcode: int | None = None,
    frame_gap_s: float = 0.05,
) -> bytes:
    deadline = time.time() + timeout_s
    while time.time() < deadline:
        first = ser.read(1)
        if not first:
            continue
        if first != b"\x55":
            continue

        len_bytes = _read_until_deadline(ser, 1, min(deadline, time.time() + frame_gap_s))
        if len_bytes is None:
            continue
        payload_len = len_bytes[0]
        payload = _read_until_deadline(ser, payload_len, min(deadline, time.time() + frame_gap_s))
        if payload is None:
            continue

        frame = b"\x55" + len_bytes + payload
        if expected_opcode is not None and (payload_len == 0 or (payload[0] != expected_opcode and payload[0] != 0xEE)):
            continue
        return frame

    return b""


def pkcs7_pad(payload: bytes, block_size: int) -> bytes:
    if block_size <= 0 or block_size >= 256:
        raise ValueError("block_size must be between 1 and 255")
    pad_len = block_size - (len(payload) % block_size)
    if pad_len == 0:
        pad_len = block_size
    return payload + bytes([pad_len]) * pad_len


def plan_file_chunks_for_transport(
    payload: bytes,
    *,
    chunk_size: int = 128,
    block_size: int = 16,
) -> FileChunkPlan:
    if not payload:
        raise ValueError("payload must not be empty")
    if chunk_size <= 0 or chunk_size >= 256:
        raise ValueError("chunk_size must be between 1 and 255")
    if block_size <= 0 or chunk_size % block_size != 0:
        raise ValueError("chunk_size must be a positive multiple of block_size")

    if len(payload) <= chunk_size and len(payload) % block_size == 0:
        return FileChunkPlan((payload,), len(payload), len(payload), 0)

    chunks: list[bytes] = []
    full_aligned_len = (len(payload) // chunk_size) * chunk_size
    if len(payload) > chunk_size and full_aligned_len:
        for index in range(0, full_aligned_len, chunk_size):
            chunks.append(payload[index : index + chunk_size])
        tail = payload[full_aligned_len:]
    else:
        tail = payload

    if tail:
        pad_len = chunk_size - len(tail)
        chunks.append(tail + bytes([pad_len]) * pad_len)
    else:
        pad_len = 0

    padded_size = len(payload) + pad_len
    return FileChunkPlan(tuple(chunks), len(payload), padded_size, pad_len)


def split_blocks_for_transport(payload: bytes) -> list[bytes]:
    if not payload:
        raise ValueError("payload must not be empty")
    if len(payload) % 16 != 0:
        raise ValueError("payload length must be a multiple of 16 bytes")
    chunks: list[bytes] = []
    index = 0
    while index < len(payload):
        remaining = len(payload) - index
        if remaining >= 240:
            chunk_len = 240
        elif remaining >= 128:
            chunk_len = 128
        elif remaining >= 64:
            chunk_len = 64
        elif remaining >= 32:
            chunk_len = 32
        else:
            chunk_len = 16
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


def case_sm4_four_block_vector() -> ProbeCase:
    return ProbeCase(
        name="SM4 64B Vector",
        tx=build_frame(SM4_PT4),
        response_len=len(SM4_CT4),
        expected=SM4_CT4,
        description="Four-block SM4 known vector",
    )


def case_aes_four_block_vector() -> ProbeCase:
    return ProbeCase(
        name="AES 64B Vector",
        tx=build_frame(b"A" + AES128_PT4),
        response_len=len(AES128_CT4),
        expected=AES128_CT4,
        description="Four-block AES known vector",
    )


def case_sm4_eight_block_vector() -> ProbeCase:
    return ProbeCase(
        name="SM4 128B Vector",
        tx=build_frame(SM4_PT8),
        response_len=len(SM4_CT8),
        expected=SM4_CT8,
        description="Eight-block SM4 known vector",
    )


def case_aes_eight_block_vector() -> ProbeCase:
    return ProbeCase(
        name="AES 128B Vector",
        tx=build_frame(b"A" + AES128_PT8),
        response_len=len(AES128_CT8),
        expected=AES128_CT8,
        description="Eight-block AES known vector",
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


def case_query_rule_stats(expected: AclRuleCounters | None = None) -> ProbeCase:
    return ProbeCase(
        name="Query Rule Hits",
        tx=build_frame(b"H"),
        response_len=10,
        expected=expected.as_bytes() if expected else None,
        description="Per-rule ACL counter readback",
        kind="rule_stats",
    )


def case_query_acl_keys(expected: AclKeyMap | None = None) -> ProbeCase:
    return ProbeCase(
        name="Query ACL Key Map",
        tx=build_frame(b"K"),
        response_len=10,
        expected=expected.as_bytes() if expected else None,
        description="ACL slot-key readback",
        kind="acl_key_map",
    )


def case_acl_write(index: int, key: int, expected: AclWriteAck | None = None) -> ProbeCase:
    if not 0 <= index <= 7:
        raise ValueError("ACL rule index must be in 0..7")
    if not 0 <= key <= 0xFF:
        raise ValueError("ACL rule key must be in 0..255")
    return ProbeCase(
        name=f"ACL Write slot {index}",
        tx=build_frame(bytes([0x03, index, key])),
        response_len=4,
        expected=expected.as_bytes() if expected else None,
        description=f"Rewrite ACL slot {index} to {display_rule_byte(key)}",
        kind="acl_write",
    )


def case_acl_v2_write(slot: int, signature_hex: str, expected: AclV2WriteAck | None = None) -> ProbeCase:
    if not 0 <= slot <= 7:
        raise ValueError("ACL v2 slot must be in 0..7")
    signature_bytes = bytes.fromhex(signature_hex.replace(" ", ""))
    if len(signature_bytes) != 16:
        raise ValueError("ACL v2 signature must be exactly 32 hex chars (16 bytes)")
    payload = bytes([0x43, slot]) + signature_bytes
    return ProbeCase(
        name=f"ACL v2 Write slot {slot}",
        tx=build_frame(payload),
        response_len=0,
        expected=expected.as_bytes() if expected else None,
        description=f"Write ACL v2 slot {slot} to {signature_hex}",
        kind="acl_v2_write",
        response_mode="framed",
        response_opcode=0x43,
    )


def case_acl_v2_keymap(expected: AclV2KeyMap | None = None) -> ProbeCase:
    return ProbeCase(
        name="Query ACL v2 Key Map",
        tx=build_frame(bytes([0x4B])),
        response_len=0,
        expected=expected.as_bytes() if expected else None,
        description="ACL v2 8x16B slot-key readback",
        kind="acl_v2_keymap",
        response_mode="framed",
        response_opcode=0x4B,
    )


def case_acl_v2_hit_counters(expected: AclV2HitCounters | None = None) -> ProbeCase:
    return ProbeCase(
        name="Query ACL v2 Hit Counters",
        tx=build_frame(bytes([0x48])),
        response_len=0,
        expected=expected.as_bytes() if expected else None,
        description="ACL v2 8x32-bit hit counter readback",
        kind="acl_v2_hits",
        response_mode="framed",
        response_opcode=0x48,
    )



def case_query_trace_meta(expected: TraceMeta | None = None) -> ProbeCase:
    return ProbeCase(
        name="Query Trace Metadata",
        tx=build_frame(bytes([0x54])),
        response_len=0,
        expected=expected.as_bytes() if expected else None,
        description="Trace ring metadata readback",
        kind="trace_meta",
        response_mode="framed",
        response_opcode=0x54,
    )


def case_query_trace_page(page_idx: int, expected: TracePage | None = None) -> ProbeCase:
    if not 0 <= page_idx < TRACE_PAGE_COUNT:
        raise ValueError("Trace page index must be in 0..15")
    return ProbeCase(
        name=f"Query Trace Page {page_idx}",
        tx=build_frame(bytes([0x54, page_idx])),
        response_len=0,
        expected=expected.as_bytes() if expected else None,
        description=f"Trace ring page {page_idx} readback",
        kind="trace_page",
        response_mode="framed",
        response_opcode=0x54,
    )


def case_query_pmu(expected: PmuSnapshot | None = None) -> ProbeCase:
    return ProbeCase(
        name="Query PMU",
        tx=build_frame(b"P"),
        response_len=0,
        expected=expected.as_bytes() if expected else None,
        description="PMU hardware snapshot readback",
        kind="pmu_query",
        response_mode="framed",
        response_opcode=0x50,
    )


def case_clear_pmu(expected: PmuClearAck | None = None) -> ProbeCase:
    return ProbeCase(
        name="Clear PMU",
        tx=build_frame(b"J"),
        response_len=4,
        expected=expected.as_bytes() if expected else None,
        description="PMU hardware counters clear",
        kind="pmu_clear",
    )


def case_run_onchip_bench(algo: str, expected: BenchResult | None = None) -> ProbeCase:
    algo_tag = _normalize_algo_tag(algo)
    return ProbeCase(
        name=f"Run On-Chip Bench ({algo.strip().upper()})",
        tx=build_frame(bytes([0x62, algo_tag])),
        response_len=22,
        expected=expected.as_bytes() if expected else None,
        description=f"Run 1MiB on-chip AXIS benchmark with {algo.strip().upper()}",
        kind="bench_run",
        response_mode="framed",
        response_opcode=0x62,
    )


def case_force_run_onchip_bench(algo: str, expected: BenchResult | None = None) -> ProbeCase:
    algo_tag = _normalize_algo_tag(algo)
    return ProbeCase(
        name=f"Force Run On-Chip Bench ({algo.strip().upper()})",
        tx=build_frame(bytes([0x62, 0xFF, algo_tag])),
        response_len=22,
        expected=expected.as_bytes() if expected else None,
        description=f"Force-reset datapath, then run 1MiB on-chip AXIS benchmark with {algo.strip().upper()}",
        kind="bench_force",
        response_mode="framed",
        response_opcode=0x62,
    )


def case_query_bench_result(expected: BenchResult | None = None) -> ProbeCase:
    return ProbeCase(
        name="Query Bench Result",
        tx=build_frame(bytes([0x62])),
        response_len=22,
        expected=expected.as_bytes() if expected else None,
        description="Read the latest on-chip AXIS benchmark result",
        kind="bench_query",
        response_mode="framed",
        response_opcode=0x62,
    )


def case_encrypt_block(algo: str, plaintext: bytes) -> ProbeCase:
    normalized = algo.strip().upper()
    if normalized not in {"AES", "SM4"}:
        raise ValueError("algo must be AES or SM4")
    if len(plaintext) % 16 != 0 or len(plaintext) == 0 or len(plaintext) > 240:
        raise ValueError("plaintext length must be a non-zero multiple of 16 bytes and <= 240 bytes")
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
    reset_serial_buffers(ser)
    started = time.perf_counter()
    ser.write(case.tx)
    ser.flush()
    if case.response_mode == "framed":
        rx = read_framed_response(ser, timeout_s, expected_opcode=case.response_opcode)
    else:
        rx = read_exact(ser, case.response_len, timeout_s)
    duration_s = max(time.perf_counter() - started, 1e-9)

    stats = None
    rule_stats = None
    acl_write_ack = None
    acl_key_map = None
    acl_v2_write_ack = None
    acl_v2_key_map = None
    acl_v2_hits = None
    trace_meta = None
    trace_page = None
    pmu_snapshot = None
    pmu_clear_ack = None
    bench_result = None
    passed = False
    if case.kind == "stats":
        try:
            stats = parse_stats_response(rx)
            passed = case.expected is None or rx == case.expected
        except ValueError:
            passed = False
    elif case.kind == "rule_stats":
        try:
            rule_stats = parse_rule_stats_response(rx)
            passed = case.expected is None or rx == case.expected
        except ValueError:
            passed = False
    elif case.kind == "acl_write":
        try:
            acl_write_ack = parse_acl_write_ack(rx)
            passed = case.expected is None or rx == case.expected
        except ValueError:
            passed = False
    elif case.kind == "acl_key_map":
        try:
            acl_key_map = parse_acl_key_map_response(rx)
            passed = case.expected is None or rx == case.expected
        except ValueError:
            passed = False
    elif case.kind == "acl_v2_write":
        try:
            acl_v2_write_ack = parse_acl_v2_write_ack(rx)
            passed = case.expected is None or rx == case.expected
        except ValueError:
            passed = False
    elif case.kind == "acl_v2_keymap":
        try:
            acl_v2_key_map = parse_acl_v2_keymap_response(rx)
            passed = case.expected is None or rx == case.expected
        except ValueError:
            passed = False
    elif case.kind == "acl_v2_hits":
        try:
            acl_v2_hits = parse_acl_v2_hits_response(rx)
            passed = case.expected is None or rx == case.expected
        except ValueError:
            passed = False
    elif case.kind == "trace_meta":
        try:
            trace_meta = parse_trace_meta_response(rx)
            passed = case.expected is None or rx == case.expected
        except ValueError:
            passed = False
    elif case.kind == "trace_page":
        try:
            trace_page = parse_trace_page_response(rx)
            passed = case.expected is None or rx == case.expected
        except ValueError:
            passed = False
    elif case.kind == "pmu_query":
        try:
            pmu_snapshot = parse_pmu_snapshot_response(rx)
            passed = case.expected is None or rx == case.expected
        except ValueError:
            passed = False
    elif case.kind == "pmu_clear":
        try:
            pmu_clear_ack = parse_pmu_clear_ack(rx)
            passed = case.expected is None or rx == case.expected
        except ValueError:
            passed = False
    elif case.kind in {"bench_run", "bench_force", "bench_query"}:
        try:
            bench_result = parse_bench_result_response(rx)
            passed = case.expected is None or rx == case.expected
        except ValueError:
            passed = False
    else:
        passed = case.expected is None or rx == case.expected

    fatal_error = None
    if rx.startswith(b"\x55\x02\xEE"):
        try:
            fatal_error = parse_stream_response(rx)
            passed = False
            stats = None
            rule_stats = None
            acl_write_ack = None
            acl_key_map = None
            trace_meta = None
            trace_page = None
            pmu_snapshot = None
            pmu_clear_ack = None
            bench_result = None
        except ValueError:
            pass

    return ProbeResult(
        case=case,
        rx=rx,
        passed=passed,
        duration_s=duration_s,
        stats=stats,
        rule_stats=rule_stats,
        acl_write_ack=acl_write_ack,
        acl_key_map=acl_key_map,
        acl_v2_write_ack=acl_v2_write_ack,
        acl_v2_key_map=acl_v2_key_map,
        acl_v2_hits=acl_v2_hits,
        trace_meta=trace_meta,
        trace_page=trace_page,
        pmu_snapshot=pmu_snapshot,
        pmu_clear_ack=pmu_clear_ack,
        bench_result=bench_result,
        fatal_error=fatal_error,
    )


def query_trace_snapshot_on_serial(
    ser: serial.Serial,
    timeout_s: float = 3.0,
) -> TraceSnapshot:
    meta_result = run_case_on_serial(ser, case_query_trace_meta(), timeout_s)
    if meta_result.trace_meta is None:
        raise RuntimeError("missing trace metadata response")
    pages = []
    for page_idx in range(TRACE_PAGE_COUNT):
        page_result = run_case_on_serial(ser, case_query_trace_page(page_idx), timeout_s)
        if page_result.trace_page is None:
            raise RuntimeError(f"missing trace page {page_idx} response")
        pages.append(page_result.trace_page)
    entries = reconstruct_trace_entries(meta_result.trace_meta, tuple(pages))
    return TraceSnapshot(meta=meta_result.trace_meta, pages=tuple(pages), entries=entries)


def run_host_case_on_serial(
    ser: serial.Serial,
    case: ProbeCase,
    timeout_s: float = 3.0,
    *,
    baud: int | None = None,
    sleep_fn=time.sleep,
) -> ProbeResult:
    if case.kind == "bench_force":
        if baud is None:
            raise ValueError("baud is required for force bench runs")
        sleep_fn(compute_force_guard_s(int(baud)))
        reset_serial_buffers(ser)
    return run_case_on_serial(ser, case, timeout_s)
