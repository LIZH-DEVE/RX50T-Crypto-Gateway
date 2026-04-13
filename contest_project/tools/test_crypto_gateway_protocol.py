import unittest

from crypto_gateway_protocol import (
    AclKeyMap,
    AclRuleCounters,
    AclWriteAck,
    FileChunkPlan,
    PmuClearAck,
    PmuSnapshot,
    StatsCounters,
    StreamBlockResponse,
    StreamCapabilities,
    StreamCipherResponse,
    StreamErrorResponse,
    StreamStartAck,
    build_frame,
    case_clear_pmu,
    build_stream_capability_query,
    build_stream_chunk_frame,
    build_stream_start_frame,
    case_query_pmu,
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
    parse_acl_write_ack,
    parse_pmu_clear_ack,
    parse_pmu_snapshot_response,
    parse_rule_byte_input,
    parse_rule_stats_response,
    parse_stats_response,
    parse_stream_response,
    plan_file_chunks_for_transport,
    split_blocks_for_transport,
)


class CryptoGatewayProtocolTests(unittest.TestCase):
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

    def test_case_query_pmu_builds_query_frame(self) -> None:
        case = case_query_pmu()
        self.assertEqual(case.tx, bytes([0x55, 0x01, 0x50]))
        self.assertEqual(case.response_len, 48)

    def test_case_clear_pmu_builds_clear_frame(self) -> None:
        case = case_clear_pmu()
        self.assertEqual(case.tx, bytes([0x55, 0x01, 0x4A]))
        self.assertEqual(case.response_len, 4)

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
            ),
        )
        self.assertAlmostEqual(snapshot.crypto_utilization, 0.25)
        self.assertAlmostEqual(snapshot.uart_stall_ratio, 0.125)
        self.assertAlmostEqual(snapshot.credit_block_ratio, 0.0625)
        self.assertAlmostEqual(snapshot.elapsed_ms_from_hw, 256 / 3_125_000 * 1000.0)

    def test_parse_pmu_clear_ack(self) -> None:
        ack = parse_pmu_clear_ack(bytes([0x55, 0x02, 0x4A, 0x00]))
        self.assertEqual(ack, PmuClearAck(status=0))

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
