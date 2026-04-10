import unittest

from crypto_gateway_protocol import (
    AclRuleCounters,
    StatsCounters,
    build_frame,
    case_aes_eight_block_vector,
    case_aes_four_block_vector,
    case_aes_known_vector,
    case_block_ascii,
    case_query_rule_stats,
    case_query_stats,
    case_sm4_eight_block_vector,
    case_sm4_four_block_vector,
    extract_first_payload_key,
    parse_rule_stats_response,
    parse_stats_response,
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
        self.assertEqual(counters, AclRuleCounters(2, 1, 1, 1, 1, 1, 1, 1))

    def test_query_rule_stats_case_uses_expected_bytes_when_provided(self) -> None:
        case = case_query_rule_stats(AclRuleCounters(1, 0, 0, 0, 1, 0, 0, 0))
        self.assertEqual(
            case.expected,
            bytes([0x48, 0x01, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x0A]),
        )
        self.assertEqual(case.response_len, 10)

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

    def test_extract_first_payload_key_for_acl_probe(self) -> None:
        case = case_block_ascii("XYZ")
        self.assertEqual(extract_first_payload_key(case.tx), "X")

    def test_extract_first_payload_key_rejects_short_frame(self) -> None:
        self.assertIsNone(extract_first_payload_key(b"\x55\x00"))


if __name__ == "__main__":
    unittest.main()
