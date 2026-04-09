import unittest

from crypto_gateway_protocol import (
    StatsCounters,
    build_frame,
    case_aes_known_vector,
    case_query_stats,
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

    def test_split_blocks_prefers_32_then_16(self) -> None:
        payload = bytes(range(48))
        chunks = split_blocks_for_transport(payload)
        self.assertEqual([len(chunk) for chunk in chunks], [32, 16])
        self.assertEqual(b"".join(chunks), payload)

    def test_aes_known_vector_frame_has_explicit_selector(self) -> None:
        case = case_aes_known_vector()
        self.assertEqual(case.tx[:3], bytes([0x55, 0x11, 0x41]))


if __name__ == "__main__":
    unittest.main()
