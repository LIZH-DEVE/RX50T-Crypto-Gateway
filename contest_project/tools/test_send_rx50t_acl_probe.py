import pytest

from send_rx50t_acl_probe import classify_probe_response


def test_classify_probe_response_accepts_16b_pass_ciphertext():
    ok, detail = classify_probe_response(
        expected_block=False,
        tx_payload=bytes.fromhex("0123456789ABCDEFFEDCBA9876543210"),
        rx=bytes.fromhex("681EDF34D206965E86B3E94F536E4246"),
    )
    assert ok is True
    assert "16-byte ciphertext" in detail


def test_classify_probe_response_rejects_block_marker_for_pass_mode():
    ok, detail = classify_probe_response(
        expected_block=False,
        tx_payload=bytes.fromhex("0123456789ABCDEFFEDCBA9876543210"),
        rx=b"D\n",
    )
    assert ok is False
    assert "blocked" in detail.lower()


def test_classify_probe_response_requires_d_newline_for_block_mode():
    ok, detail = classify_probe_response(
        expected_block=True,
        tx_payload=bytes.fromhex("5152535455565758595A303132333435"),
        rx=b"D\n",
    )
    assert ok is True
    assert detail == "block response"


def test_classify_probe_response_rejects_wrong_non_block_frame_for_block_mode():
    ok, detail = classify_probe_response(
        expected_block=True,
        tx_payload=bytes.fromhex("5152535455565758595A303132333435"),
        rx=bytes.fromhex("681EDF34D206965E86B3E94F536E4246"),
    )
    assert ok is False
    assert "expected block" in detail.lower()
