import unittest
from unittest import mock
import sys

import crypto_gateway_protocol as proto
import send_rx50t_crypto_probe as cli
from crypto_gateway_protocol import (
    AclKeyMap,
    AclRuleCounters,
    AclV2HitCounters,
    AclV2KeyMap,
    AclV2WriteAck,
    AclWriteAck,
    BenchResult,
    TraceEntry,
    TraceMeta,
    TracePage,
    FatalErrorResponse,
    FileChunkPlan,
    PmuClearAck,
    PmuSnapshot,
    ProbeCase,
    ProbeResult,
    StatsCounters,
    StreamBlockResponse,
    StreamCapabilities,
    StreamCipherResponse,
    StreamErrorResponse,
    StreamStartAck,
    build_frame,
    case_clear_pmu,
    case_force_run_onchip_bench,
    case_query_bench_result,
    build_stream_capability_query,
    build_stream_chunk_frame,
    build_stream_start_frame,
    case_query_pmu,
    case_query_trace_meta,
    case_query_trace_page,
    case_run_onchip_bench,
    case_acl_v2_hit_counters,
    case_acl_v2_keymap,
    case_acl_v2_write,
    case_acl_write,
    case_aes_eight_block_vector,
    case_aes_four_block_vector,
    case_aes_known_vector,
    case_block_ascii,
    case_query_acl_keys,
    case_query_rule_stats,
    case_query_stats,
    case_sm4_eight_block_vector,
    case_sm4_four_block_vector,
    extract_first_payload_key,
    pkcs7_pad,
    parse_acl_key_map_response,
    parse_acl_v2_hits_response,
    parse_acl_v2_keymap_response,
    parse_acl_v2_write_ack,
    parse_acl_write_ack,
    parse_bench_result_response,
    parse_pmu_clear_ack,
    parse_pmu_snapshot_response,
    parse_trace_meta_response,
    parse_trace_page_response,
    reconstruct_trace_entries,
    parse_rule_byte_input,
    parse_rule_stats_response,
    parse_stats_response,
    parse_stream_response,
    plan_file_chunks_for_transport,
    run_case_on_serial,
    split_blocks_for_transport,
)


class FakeSerial:
    def __init__(self, response: bytes) -> None:
        self._response = bytearray(response)
        self.reset_input_buffer = mock.Mock()
        self.reset_output_buffer = mock.Mock()
        self.flush = mock.Mock()
        self.writes: list[bytes] = []

    def write(self, data: bytes) -> int:
        self.writes.append(bytes(data))
        return len(data)

    def read(self, size: int) -> bytes:
        if not self._response:
            return b""
        chunk = bytes(self._response[:size])
        del self._response[:size]
        return chunk


class CallbackSerial:
    def __init__(self, on_write) -> None:
        self._on_write = on_write
        self._response = bytearray()
        self.flush = mock.Mock()
        self.writes: list[bytes] = []
        self.reset_input_buffer = mock.Mock(side_effect=self._clear_input)
        self.reset_output_buffer = mock.Mock()

    def _clear_input(self) -> None:
        self._response.clear()

    def queue_rx(self, data: bytes) -> None:
        self._response.extend(data)

    def write(self, data: bytes) -> int:
        payload = bytes(data)
        self.writes.append(payload)
        self._on_write(self, payload)
        return len(payload)

    def read(self, size: int) -> bytes:
        if not self._response:
            return b""
        chunk = bytes(self._response[:size])
        del self._response[:size]
        return chunk


class CryptoGatewayProtocolTests(unittest.TestCase):
    @staticmethod
    def _sample_bench_result(algo: int = 0x53) -> BenchResult:
        return BenchResult(
            version=1,
            status=0x00,
            algo=algo,
            byte_count=0x0010_0000,
            cycles=0x100,
            crc32=0x1234_5678,
        )

    @staticmethod
    def _sample_pmu_snapshot() -> PmuSnapshot:
        return PmuSnapshot(
            clk_hz=50_000_000,
            global_cycles=2048,
            crypto_active_cycles=512,
            uart_tx_stall_cycles=256,
            stream_credit_block_cycles=128,
            acl_block_events=0,
            version=0x03,
            stream_bytes_in=1024,
            stream_bytes_out=768,
            stream_chunk_count=6,
            crypto_clock_gated_cycles=320,
            crypto_clock_status_flags=0x0000_0000_0000_0003,
        )

    def test_build_frame_wraps_payload(self) -> None:
        self.assertEqual(build_frame(b"\xAA\xBB"), bytes([0x55, 0x02, 0xAA, 0xBB]))

    def test_build_frame_rejects_empty_payload(self) -> None:
        with self.assertRaises(ValueError):
            build_frame(b"")

    def test_parse_stats_response(self) -> None:
        stats = parse_stats_response(bytes([0x53, 0x03, 0x01, 0x01, 0x01, 0x01, 0x0A]))
        self.assertEqual(stats, StatsCounters(3, 1, 1, 1, 1))

    def test_query_stats_case_uses_expected_bytes_when_provided(self) -> None:
        case = case_query_stats(StatsCounters(5, 1, 2, 2, 1))
        self.assertEqual(case.expected, bytes([0x53, 0x05, 0x01, 0x02, 0x02, 0x01, 0x0A]))
        self.assertEqual(case.response_len, 7)

    def test_parse_rule_stats_response(self) -> None:
        counters = parse_rule_stats_response(
            bytes([0x48, 0x02, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x0A])
        )
        self.assertEqual(counters, AclRuleCounters((2, 1, 1, 1, 1, 1, 1, 1)))

    def test_query_rule_stats_case_uses_expected_bytes_when_provided(self) -> None:
        case = case_query_rule_stats(AclRuleCounters((1, 0, 0, 0, 1, 0, 0, 0)))
        self.assertEqual(
            case.expected,
            bytes([0x48, 0x01, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x0A]),
        )
        self.assertEqual(case.response_len, 10)

    def test_case_acl_write_builds_control_frame(self) -> None:
        case = case_acl_write(3, 0x51)
        self.assertEqual(case.tx, bytes([0x55, 0x03, 0x03, 0x03, 0x51]))
        self.assertEqual(case.response_len, 4)

    def test_case_query_acl_keys_builds_query_frame(self) -> None:
        case = case_query_acl_keys()
        self.assertEqual(case.tx, bytes([0x55, 0x01, 0x4B]))
        self.assertEqual(case.response_len, 10)

    def test_case_acl_v2_write_builds_framed_control_frame(self) -> None:
        case = case_acl_v2_write(3, "00112233445566778899aabbccddeeff")
        self.assertEqual(
            case.tx,
            bytes.fromhex("55 12 43 03 00 11 22 33 44 55 66 77 88 99 aa bb cc dd ee ff"),
        )
        self.assertEqual(case.response_mode, "framed")
        self.assertEqual(case.response_opcode, 0x43)

    def test_case_acl_v2_keymap_builds_framed_query(self) -> None:
        case = case_acl_v2_keymap()
        self.assertEqual(case.tx, bytes([0x55, 0x01, 0x4B]))
        self.assertEqual(case.response_mode, "framed")
        self.assertEqual(case.response_opcode, 0x4B)

    def test_case_acl_v2_hit_counters_builds_framed_query(self) -> None:
        case = case_acl_v2_hit_counters()
        self.assertEqual(case.tx, bytes([0x55, 0x01, 0x48]))
        self.assertEqual(case.response_mode, "framed")
        self.assertEqual(case.response_opcode, 0x48)

    def test_case_query_pmu_builds_query_frame(self) -> None:
        case = case_query_pmu()
        self.assertEqual(case.tx, bytes([0x55, 0x01, 0x50]))
        self.assertEqual(case.response_len, 0)
        self.assertEqual(case.response_mode, "framed")
        self.assertEqual(case.response_opcode, 0x50)

    def test_case_query_trace_meta_builds_query_frame(self) -> None:
        case = case_query_trace_meta()
        self.assertEqual(case.tx, bytes([0x55, 0x01, 0x54]))
        self.assertEqual(case.response_mode, "framed")
        self.assertEqual(case.response_opcode, 0x54)

    def test_case_query_trace_page_builds_query_frame(self) -> None:
        case = case_query_trace_page(3)
        self.assertEqual(case.tx, bytes([0x55, 0x02, 0x54, 0x03]))
        self.assertEqual(case.response_mode, "framed")
        self.assertEqual(case.response_opcode, 0x54)

    def test_parse_trace_meta_response(self) -> None:
        meta = parse_trace_meta_response(bytes.fromhex('55 06 54 01 00 14 34 03'))
        self.assertEqual(meta, TraceMeta(version=1, valid_entries=20, write_ptr=0x34, flags=0x03))
        self.assertTrue(meta.wrapped)
        self.assertTrue(meta.enabled)

    def test_parse_trace_page_response(self) -> None:
        entries = tuple(TraceEntry(timestamp_ms=i, event_code=0x08, arg0=0, arg1=i) for i in range(16))
        page = parse_trace_page_response(TracePage(page_idx=2, entry_count=16, flags=0x03, entries=entries).as_bytes())
        self.assertEqual(page.page_idx, 2)
        self.assertEqual(page.entry_count, 16)
        self.assertEqual(page.flags, 0x03)
        self.assertEqual(page.entries[5], entries[5])

    def test_reconstruct_trace_entries_handles_wrapped_ring(self) -> None:
        meta = TraceMeta(version=1, valid_entries=4, write_ptr=2, flags=0x03)
        page0_entries = [TraceEntry(timestamp_ms=300 + i, event_code=0x08, arg0=0, arg1=i) for i in range(16)]
        page1_entries = [TraceEntry(timestamp_ms=400 + i, event_code=0x09, arg0=0, arg1=i) for i in range(16)]
        empty = tuple(TraceEntry(timestamp_ms=0, event_code=0, arg0=0, arg1=0) for _ in range(16))
        pages = [
            TracePage(page_idx=0, entry_count=16, flags=0x03, entries=tuple(page0_entries)),
            TracePage(page_idx=1, entry_count=16, flags=0x03, entries=tuple(page1_entries)),
        ]
        for idx in range(2, 16):
            pages.append(TracePage(page_idx=idx, entry_count=0, flags=0x03, entries=empty))
        entries = reconstruct_trace_entries(meta, tuple(pages))
        self.assertEqual([entry.timestamp_ms for entry in entries], [302, 303, 304, 305])

    def test_reconstruct_trace_entries_handles_nonwrapped_second_page(self) -> None:
        meta = TraceMeta(version=1, valid_entries=17, write_ptr=17, flags=0x02)
        page0_entries = tuple(TraceEntry(timestamp_ms=100 + i, event_code=0x08, arg0=0, arg1=i) for i in range(16))
        page1_first = TraceEntry(timestamp_ms=200, event_code=0x04, arg0=1, arg1=0)
        empty_entry = TraceEntry(timestamp_ms=0, event_code=0, arg0=0, arg1=0)
        page1_entries = (page1_first,) + tuple(empty_entry for _ in range(15))
        pages = [
            TracePage(page_idx=0, entry_count=16, flags=0x02, entries=page0_entries),
            TracePage(page_idx=1, entry_count=1, flags=0x02, entries=page1_entries),
        ]
        for idx in range(2, 16):
            pages.append(TracePage(page_idx=idx, entry_count=0, flags=0x02, entries=tuple(empty_entry for _ in range(16))))
        entries = reconstruct_trace_entries(meta, tuple(pages))
        self.assertEqual(len(entries), 17)
        self.assertEqual(entries[0], page0_entries[0])
        self.assertEqual(entries[15], page0_entries[15])
        self.assertEqual(entries[16], page1_first)
    def test_case_clear_pmu_builds_clear_frame(self) -> None:
        case = case_clear_pmu()
        self.assertEqual(case.tx, bytes([0x55, 0x01, 0x4A]))
        self.assertEqual(case.response_len, 4)

    def test_case_run_onchip_bench_builds_control_frame(self) -> None:
        case = case_run_onchip_bench("SM4")
        self.assertEqual(case.tx, bytes([0x55, 0x02, 0x62, 0x53]))
        self.assertEqual(case.response_len, 22)

    def test_case_force_run_onchip_bench_builds_force_control_frame(self) -> None:
        case = case_force_run_onchip_bench("AES")
        self.assertEqual(case.tx, bytes([0x55, 0x03, 0x62, 0xFF, 0x41]))
        self.assertEqual(case.response_len, 22)

    def test_force_guard_seconds_clamps_to_one_ms_at_two_mbaud(self) -> None:
        self.assertEqual(proto.compute_force_guard_s(2_000_000), 0.001)

    def test_force_guard_seconds_scales_with_baud_when_line_is_slower(self) -> None:
        self.assertAlmostEqual(proto.compute_force_guard_s(115_200), (2 * 20 * 10) / 115_200)

    def test_case_query_bench_result_builds_query_frame(self) -> None:
        case = case_query_bench_result()
        self.assertEqual(case.tx, bytes([0x55, 0x01, 0x62]))
        self.assertEqual(case.response_len, 22)

    def test_build_stream_capability_query(self) -> None:
        self.assertEqual(build_stream_capability_query(), bytes([0x55, 0x01, 0x57]))

    def test_build_stream_start_frame_uses_chunk_count(self) -> None:
        self.assertEqual(
            build_stream_start_frame("AES", 0x1234),
            bytes([0x55, 0x04, 0x4D, 0x41, 0x12, 0x34]),
        )

    def test_build_stream_chunk_frame_prefixes_seq_before_128b_payload(self) -> None:
        chunk = bytes([0xAB]) * 128
        frame = build_stream_chunk_frame(0x07, chunk)
        self.assertEqual(frame[:3], bytes([0x55, 0x81, 0x07]))
        self.assertEqual(frame[3:], chunk)

    def test_parse_acl_write_ack(self) -> None:
        ack = parse_acl_write_ack(bytes([0x43, 0x03, 0x51, 0x0A]))
        self.assertEqual(ack, AclWriteAck(index=3, key=0x51))

    def test_parse_acl_key_map_response(self) -> None:
        key_map = parse_acl_key_map_response(
            bytes([0x4B, 0x58, 0x59, 0x5A, 0x51, 0x50, 0x52, 0x54, 0x55, 0x0A])
        )
        self.assertEqual(key_map, AclKeyMap((0x58, 0x59, 0x5A, 0x51, 0x50, 0x52, 0x54, 0x55)))
        self.assertEqual(key_map.display_labels(), ("X", "Y", "Z", "Q", "P", "R", "T", "U"))

    def test_parse_acl_v2_write_ack(self) -> None:
        ack = parse_acl_v2_write_ack(
            bytes.fromhex("55 12 43 03 00 11 22 33 44 55 66 77 88 99 aa bb cc dd ee ff")
        )
        self.assertEqual(ack, AclV2WriteAck(slot=3, signature=bytes.fromhex("00112233445566778899aabbccddeeff")))

    def test_parse_acl_v2_keymap_response(self) -> None:
        frame = bytes([0x55, 0x81, 0x4B]) + b"".join((bytes([value]) * 16) for value in range(8))
        key_map = parse_acl_v2_keymap_response(frame)
        self.assertEqual(key_map, AclV2KeyMap(tuple(bytes([value]) * 16 for value in range(8))))

    def test_parse_acl_v2_hits_response(self) -> None:
        frame = bytes.fromhex("55 21 48") + b"".join(value.to_bytes(4, "big") for value in range(8))
        hits = parse_acl_v2_hits_response(frame)
        self.assertEqual(hits, AclV2HitCounters(tuple(range(8))))

    def test_parse_pmu_snapshot_response(self) -> None:
        snapshot = parse_pmu_snapshot_response(
            bytes.fromhex(
                "55 2E 50 01"
                " 00 2F AF 08"
                " 00 00 00 00 00 00 01 00"
                " 00 00 00 00 00 00 00 40"
                " 00 00 00 00 00 00 00 20"
                " 00 00 00 00 00 00 00 10"
                " 00 00 00 00 00 00 00 03"
            )
        )
        self.assertEqual(
            snapshot,
            PmuSnapshot(
                clk_hz=3_125_000,
                global_cycles=256,
                crypto_active_cycles=64,
                uart_tx_stall_cycles=32,
                stream_credit_block_cycles=16,
                acl_block_events=3,
                version=1,
            ),
        )
        self.assertAlmostEqual(snapshot.crypto_utilization, 0.25)
        self.assertAlmostEqual(snapshot.uart_stall_ratio, 0.125)
        self.assertAlmostEqual(snapshot.credit_block_ratio, 0.0625)
        self.assertAlmostEqual(snapshot.elapsed_ms_from_hw, 256 / 3_125_000 * 1000.0)
        self.assertEqual(snapshot.version, 0x01)
        self.assertIsNone(snapshot.stream_bytes_in)
        self.assertIsNone(snapshot.stream_bytes_out)
        self.assertIsNone(snapshot.stream_chunk_count)

    def test_parse_pmu_snapshot_response_v2(self) -> None:
        snapshot = parse_pmu_snapshot_response(
            bytes.fromhex(
                "55 46 50 02"
                " 02 FA F0 80"
                " 00 00 00 00 00 00 10 00"
                " 00 00 00 00 00 00 04 00"
                " 00 00 00 00 00 00 02 00"
                " 00 00 00 00 00 00 01 00"
                " 00 00 00 00 00 00 00 03"
                " 00 00 00 00 00 00 08 00"
                " 00 00 00 00 00 00 07 80"
                " 00 00 00 00 00 00 00 10"
            )
        )
        self.assertEqual(snapshot.version, 0x02)
        self.assertEqual(snapshot.clk_hz, 50_000_000)
        self.assertEqual(snapshot.global_cycles, 4096)
        self.assertEqual(snapshot.stream_bytes_in, 2048)
        self.assertEqual(snapshot.stream_bytes_out, 1920)
        self.assertEqual(snapshot.stream_chunk_count, 16)

    def test_parse_pmu_snapshot_response_v3(self) -> None:
        snapshot = parse_pmu_snapshot_response(
            bytes.fromhex(
                "55 56 50 03"
                " 02 FA F0 80"
                " 00 00 00 00 00 00 10 00"
                " 00 00 00 00 00 00 04 00"
                " 00 00 00 00 00 00 02 00"
                " 00 00 00 00 00 00 01 00"
                " 00 00 00 00 00 00 00 03"
                " 00 00 00 00 00 00 08 00"
                " 00 00 00 00 00 00 07 80"
                " 00 00 00 00 00 00 00 10"
                " 00 00 00 00 00 00 03 20"
                " 00 00 00 00 00 00 00 03"
            )
        )
        self.assertEqual(snapshot.version, 0x03)
        self.assertEqual(snapshot.crypto_clock_gated_cycles, 800)
        self.assertEqual(snapshot.crypto_clock_status_flags, 0x03)

    def test_sample_pmu_snapshot_v3_roundtrip(self) -> None:
        snapshot = self._sample_pmu_snapshot()
        parsed = parse_pmu_snapshot_response(snapshot.as_bytes())
        self.assertEqual(parsed, snapshot)

    def test_parse_pmu_clear_ack(self) -> None:
        ack = parse_pmu_clear_ack(bytes([0x55, 0x02, 0x4A, 0x00]))
        self.assertEqual(ack, PmuClearAck(status=0))

    def test_parse_bench_result_response(self) -> None:
        result = parse_bench_result_response(
            bytes.fromhex(
                "55 14 62 01"
                " 00 53"
                " 00 10 00 00"
                " 00 00 00 00 00 00 01 00"
                " 12 34 56 78"
            )
        )
        self.assertEqual(
            result,
            BenchResult(
                version=1,
                status=0x00,
                algo=0x53,
                byte_count=0x0010_0000,
                cycles=0x100,
                crc32=0x1234_5678,
            ),
        )

    def test_run_case_on_serial_resyncs_to_framed_bench_response(self) -> None:
        case = case_force_run_onchip_bench("SM4")
        ser = FakeSerial(
            bytes.fromhex(
                "00 FF 7E"
                " 55 14 62 01"
                " 00 53"
                " 00 10 00 00"
                " 00 00 00 00 00 00 01 00"
                " 12 34 56 78"
            )
        )
        result = run_case_on_serial(ser, case, 3.0)
        self.assertTrue(result.passed)
        self.assertEqual(
            result.bench_result,
            BenchResult(
                version=1,
                status=0x00,
                algo=0x53,
                byte_count=0x0010_0000,
                cycles=0x100,
                crc32=0x1234_5678,
            ),
        )

    def test_run_case_on_serial_treats_no_result_bench_status_as_valid_protocol(self) -> None:
        case = case_query_bench_result()
        ser = FakeSerial(
            bytes.fromhex(
                "55 14 62 01"
                " 04 41"
                " 00 00 00 00"
                " 00 00 00 00 00 00 00 00"
                " 00 00 00 00"
            )
        )
        result = run_case_on_serial(ser, case, 3.0)
        self.assertTrue(result.passed)
        self.assertEqual(result.bench_result.status, 0x04)

    def test_run_host_case_on_serial_sleeps_and_resets_before_force_bench_dispatch(self) -> None:
        events: list[tuple[str, float | str | None]] = []
        ser = mock.Mock()
        ser.reset_input_buffer.side_effect = lambda: events.append(("reset_in", None))
        ser.reset_output_buffer.side_effect = lambda: events.append(("reset_out", None))

        bench_probe = ProbeResult(
            case=case_force_run_onchip_bench("AES"),
            rx=self._sample_bench_result(0x41).as_bytes(),
            passed=True,
            duration_s=0.001,
            bench_result=self._sample_bench_result(0x41),
        )

        with mock.patch.object(
            proto,
            "run_case_on_serial",
            side_effect=lambda serial_obj, case, timeout_s: (
                events.append(("dispatch", case.name)) or bench_probe
            ),
        ):
            result = proto.run_host_case_on_serial(
                ser,
                case_force_run_onchip_bench("AES"),
                3.0,
                baud=2_000_000,
                sleep_fn=lambda seconds: events.append(("sleep", seconds)),
            )

        self.assertIs(result, bench_probe)
        self.assertEqual(
            events,
            [
                ("sleep", 0.001),
                ("reset_in", None),
                ("reset_out", None),
                ("dispatch", "Force Run On-Chip Bench (AES)"),
            ],
        )

    def test_query_bench_followed_by_pmu_query_discards_stale_bench_frame(self) -> None:
        bench_case = case_query_bench_result()
        pmu_case = case_query_pmu()
        bench_frame = self._sample_bench_result().as_bytes()
        pmu_snapshot = self._sample_pmu_snapshot()

        def on_write(fake_serial: CallbackSerial, payload: bytes) -> None:
            if payload == bench_case.tx:
                fake_serial.queue_rx(bench_frame + bench_frame)
            elif payload == pmu_case.tx:
                fake_serial.queue_rx(pmu_snapshot.as_bytes())
            else:
                raise AssertionError(f"unexpected write: {payload.hex(' ')}")

        ser = CallbackSerial(on_write)
        bench_result = run_case_on_serial(ser, bench_case, 3.0)
        pmu_result = run_case_on_serial(ser, pmu_case, 3.0)

        self.assertTrue(bench_result.passed)
        self.assertIsNotNone(bench_result.bench_result)
        self.assertEqual(pmu_result.pmu_snapshot, pmu_snapshot)
        self.assertEqual(ser.writes, [bench_case.tx, pmu_case.tx])

    def test_force_bench_followed_by_pmu_query_discards_stale_bench_frame(self) -> None:
        force_case = case_force_run_onchip_bench("SM4")
        pmu_case = case_query_pmu()
        bench_frame = self._sample_bench_result().as_bytes()
        pmu_snapshot = self._sample_pmu_snapshot()

        def on_write(fake_serial: CallbackSerial, payload: bytes) -> None:
            if payload == force_case.tx:
                fake_serial.queue_rx(bench_frame + bench_frame)
            elif payload == pmu_case.tx:
                fake_serial.queue_rx(pmu_snapshot.as_bytes())
            else:
                raise AssertionError(f"unexpected write: {payload.hex(' ')}")

        ser = CallbackSerial(on_write)
        bench_result = proto.run_host_case_on_serial(
            ser,
            force_case,
            3.0,
            baud=2_000_000,
            sleep_fn=lambda _seconds: None,
        )
        pmu_result = run_case_on_serial(ser, pmu_case, 3.0)

        self.assertTrue(bench_result.passed)
        self.assertIsNotNone(bench_result.bench_result)
        self.assertEqual(pmu_result.pmu_snapshot, pmu_snapshot)
        self.assertEqual(ser.writes, [force_case.tx, pmu_case.tx])

    def test_cli_force_run_uses_host_helper_with_baud(self) -> None:
        serial_port = mock.MagicMock()
        serial_ctx = mock.MagicMock()
        serial_ctx.__enter__.return_value = serial_port
        serial_ctx.__exit__.return_value = False
        bench_result = self._sample_bench_result(0x41)
        pmu_snapshot = self._sample_pmu_snapshot()

        with mock.patch.object(cli.serial, "Serial", return_value=serial_ctx):
            with mock.patch.object(
                cli,
                "run_host_case_on_serial",
                return_value=ProbeResult(
                    case=case_force_run_onchip_bench("AES"),
                    rx=bench_result.as_bytes(),
                    passed=True,
                    duration_s=0.001,
                    bench_result=bench_result,
                ),
            ) as host_run:
                with mock.patch.object(
                    cli,
                    "run_case_on_serial",
                    return_value=ProbeResult(
                        case=case_query_pmu(),
                        rx=pmu_snapshot.as_bytes(),
                        passed=True,
                        duration_s=0.001,
                        pmu_snapshot=pmu_snapshot,
                    ),
                ):
                    with mock.patch("builtins.print"):
                        with mock.patch.object(
                            sys,
                            "argv",
                            [
                                "send_rx50t_crypto_probe.py",
                                "--port",
                                "COM12",
                                "--baud",
                                "2000000",
                                "--force-run-onchip-bench",
                                "--algo",
                                "aes",
                            ],
                        ):
                            self.assertEqual(cli.main(), 0)

        host_run.assert_called_once()
        args, kwargs = host_run.call_args
        self.assertIs(args[0], serial_port)
        self.assertEqual(args[1].kind, "bench_force")
        self.assertEqual(args[2], 3.0)
        self.assertEqual(kwargs["baud"], 2_000_000)

    def test_cli_run_onchip_bench_accepts_uppercase_algo(self) -> None:
        serial_port = mock.MagicMock()
        serial_ctx = mock.MagicMock()
        serial_ctx.__enter__.return_value = serial_port
        serial_ctx.__exit__.return_value = False
        bench_result = self._sample_bench_result(0x53)
        pmu_snapshot = self._sample_pmu_snapshot()

        with mock.patch.object(cli.serial, "Serial", return_value=serial_ctx):
            with mock.patch.object(
                cli,
                "run_host_case_on_serial",
                return_value=ProbeResult(
                    case=case_run_onchip_bench("SM4"),
                    rx=bench_result.as_bytes(),
                    passed=True,
                    duration_s=0.001,
                    bench_result=bench_result,
                ),
            ) as host_run:
                with mock.patch.object(
                    cli,
                    "run_case_on_serial",
                    return_value=ProbeResult(
                        case=case_query_pmu(),
                        rx=pmu_snapshot.as_bytes(),
                        passed=True,
                        duration_s=0.001,
                        pmu_snapshot=pmu_snapshot,
                    ),
                ):
                    with mock.patch("builtins.print"):
                        with mock.patch.object(
                            sys,
                            "argv",
                            [
                                "send_rx50t_crypto_probe.py",
                                "--port",
                                "COM12",
                                "--baud",
                                "2000000",
                                "--run-onchip-bench",
                                "--algo",
                                "SM4",
                            ],
                        ):
                            self.assertEqual(cli.main(), 0)

        host_run.assert_called_once()
        args, kwargs = host_run.call_args
        self.assertIs(args[0], serial_port)
        self.assertEqual(args[1].kind, "bench_run")
        self.assertEqual(args[1].tx, case_run_onchip_bench("SM4").tx)
        self.assertEqual(args[2], 3.0)
        self.assertEqual(kwargs["baud"], 2_000_000)

    def test_cli_query_bench_without_pmu_snapshot_does_not_crash(self) -> None:
        serial_port = mock.MagicMock()
        serial_ctx = mock.MagicMock()
        serial_ctx.__enter__.return_value = serial_port
        serial_ctx.__exit__.return_value = False
        bench_result = BenchResult(
            version=1,
            status=0x04,
            algo=0x53,
            byte_count=0,
            cycles=0,
            crc32=0,
        )

        with mock.patch.object(cli.serial, "Serial", return_value=serial_ctx):
            with mock.patch.object(
                cli,
                "run_host_case_on_serial",
                return_value=ProbeResult(
                    case=case_query_bench_result(),
                    rx=bench_result.as_bytes(),
                    passed=True,
                    duration_s=0.001,
                    bench_result=bench_result,
                ),
            ):
                with mock.patch("builtins.print"):
                    with mock.patch.object(
                        sys,
                        "argv",
                        [
                            "send_rx50t_crypto_probe.py",
                            "--port",
                            "COM12",
                            "--baud",
                            "2000000",
                            "--query-bench",
                        ],
                    ):
                        self.assertEqual(cli.main(), 0)

    def test_cli_query_bench_success_without_pmu_snapshot_does_not_crash(self) -> None:
        serial_port = mock.MagicMock()
        serial_ctx = mock.MagicMock()
        serial_ctx.__enter__.return_value = serial_port
        serial_ctx.__exit__.return_value = False
        bench_result = self._sample_bench_result(0x41)

        with mock.patch.object(cli.serial, "Serial", return_value=serial_ctx):
            with mock.patch.object(
                cli,
                "run_host_case_on_serial",
                return_value=ProbeResult(
                    case=case_query_bench_result(),
                    rx=bench_result.as_bytes(),
                    passed=True,
                    duration_s=0.001,
                    bench_result=bench_result,
                ),
            ):
                with mock.patch("builtins.print"):
                    with mock.patch.object(
                        sys,
                        "argv",
                        [
                            "send_rx50t_crypto_probe.py",
                            "--port",
                            "COM12",
                            "--baud",
                            "2000000",
                            "--query-bench",
                        ],
                    ):
                        self.assertEqual(cli.main(), 0)

    def test_parse_stream_capability_response(self) -> None:
        message = parse_stream_response(bytes([0x55, 0x04, 0x57, 0x80, 0x08, 0x07]))
        self.assertEqual(message, StreamCapabilities(chunk_size=128, window=8, flags=0x07))

    def test_parse_stream_start_ack(self) -> None:
        message = parse_stream_response(bytes([0x55, 0x02, 0x4D, 0x00]))
        self.assertEqual(message, StreamStartAck(status=0))

    def test_parse_stream_cipher_response(self) -> None:
        ciphertext = bytes(range(128))
        message = parse_stream_response(bytes([0x55, 0x82, 0x52, 0xFE]) + ciphertext)
        self.assertEqual(message, StreamCipherResponse(seq=0xFE, ciphertext=ciphertext))

    def test_parse_stream_block_response(self) -> None:
        message = parse_stream_response(bytes([0x55, 0x03, 0x42, 0x05, 0x03]))
        self.assertEqual(message, StreamBlockResponse(seq=0x05, slot=0x03))

    def test_parse_stream_error_response(self) -> None:
        message = parse_stream_response(bytes([0x55, 0x02, 0x45, 0x02]))
        self.assertEqual(message, StreamErrorResponse(code=0x02))

    def test_parse_stream_fatal_response(self) -> None:
        message = parse_stream_response(bytes([0x55, 0x02, 0xEE, 0x01]))
        self.assertEqual(message, FatalErrorResponse(code=0x01))

    def test_run_case_on_serial_returns_fatal_error_for_framed_query(self) -> None:
        case = case_query_pmu()
        ser = FakeSerial(bytes([0x55, 0x02, 0xEE, 0x02]))
        result = run_case_on_serial(ser, case, 3.0)
        self.assertFalse(result.passed)
        self.assertEqual(result.fatal_error, FatalErrorResponse(code=0x02))
        self.assertIsNone(result.pmu_snapshot)

    def test_parse_rule_byte_input_accepts_ascii(self) -> None:
        self.assertEqual(parse_rule_byte_input("Q"), 0x51)

    def test_parse_rule_byte_input_accepts_hex(self) -> None:
        self.assertEqual(parse_rule_byte_input("0x51"), 0x51)

    def test_parse_rule_byte_input_rejects_bad_text(self) -> None:
        with self.assertRaises(ValueError):
            parse_rule_byte_input("QQ")

    def test_split_blocks_prefers_64_then_32_then_16(self) -> None:
        payload = bytes(range(112))
        chunks = split_blocks_for_transport(payload)
        self.assertEqual([len(chunk) for chunk in chunks], [64, 32, 16])
        self.assertEqual(b"".join(chunks), payload)

    def test_aes_known_vector_frame_has_explicit_selector(self) -> None:
        case = case_aes_known_vector()
        self.assertEqual(case.tx[:3], bytes([0x55, 0x11, 0x41]))

    def test_aes_64b_vector_frame_has_explicit_selector(self) -> None:
        case = case_aes_four_block_vector()
        self.assertEqual(case.tx[:3], bytes([0x55, 0x41, 0x41]))
        self.assertEqual(case.response_len, 64)

    def test_aes_128b_vector_frame_has_explicit_selector(self) -> None:
        case = case_aes_eight_block_vector()
        self.assertEqual(case.tx[:3], bytes([0x55, 0x81, 0x41]))
        self.assertEqual(case.response_len, 128)

    def test_sm4_64b_vector_response_len(self) -> None:
        case = case_sm4_four_block_vector()
        self.assertEqual(case.tx[:2], bytes([0x55, 0x40]))
        self.assertEqual(case.response_len, 64)

    def test_sm4_128b_vector_response_len(self) -> None:
        case = case_sm4_eight_block_vector()
        self.assertEqual(case.tx[:2], bytes([0x55, 0x80]))
        self.assertEqual(case.response_len, 128)

    def test_split_blocks_uses_single_128b_chunk(self) -> None:
        payload = bytes(range(128))
        chunks = split_blocks_for_transport(payload)
        self.assertEqual([len(chunk) for chunk in chunks], [128])
        self.assertEqual(b"".join(chunks), payload)

    def test_pkcs7_pad_appends_expected_padding(self) -> None:
        padded = pkcs7_pad(b"ABC", 16)
        self.assertEqual(len(padded), 16)
        self.assertEqual(padded[-1], 13)
        self.assertEqual(padded[-13:], bytes([13]) * 13)

    def test_file_chunk_plan_keeps_single_aligned_128b_chunk(self) -> None:
        payload = bytes(range(128))
        plan = plan_file_chunks_for_transport(payload)
        self.assertEqual(plan, FileChunkPlan((payload,), 128, 128, 0))

    def test_file_chunk_plan_pads_oversize_tail_to_128b(self) -> None:
        payload = bytes(range(160))
        plan = plan_file_chunks_for_transport(payload)
        self.assertEqual(plan.original_size, 160)
        self.assertEqual(plan.padded_size, 256)
        self.assertEqual(plan.pad_bytes, 96)
        self.assertEqual([len(chunk) for chunk in plan.chunks], [128, 128])
        self.assertEqual(plan.chunks[0], payload[:128])
        self.assertEqual(plan.chunks[1][:32], payload[128:])
        self.assertEqual(plan.chunks[1][32:], bytes([96]) * 96)

    def test_file_chunk_plan_pads_small_unaligned_file_to_128b(self) -> None:
        payload = b"hello world"
        plan = plan_file_chunks_for_transport(payload)
        self.assertEqual(plan.original_size, len(payload))
        self.assertEqual(plan.padded_size, 128)
        self.assertEqual(plan.pad_bytes, 117)
        self.assertEqual([len(chunk) for chunk in plan.chunks], [128])
        self.assertEqual(plan.chunks[0][: len(payload)], payload)
        self.assertEqual(plan.chunks[0][-1], 117)

    def test_extract_first_payload_key_for_acl_probe(self) -> None:
        case = case_block_ascii("XYZ")
        self.assertEqual(extract_first_payload_key(case.tx), "X")

    def test_extract_first_payload_key_rejects_short_frame(self) -> None:
        self.assertIsNone(extract_first_payload_key(b"\x55\x00"))


if __name__ == "__main__":
    unittest.main()
