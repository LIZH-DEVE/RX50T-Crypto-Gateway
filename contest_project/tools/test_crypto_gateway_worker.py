import unittest
from unittest import mock
import threading

import crypto_gateway_worker as worker_mod


class FakeStreamSerial:
    def __init__(self, on_write):
        self._on_write = on_write
        self._rx = bytearray()
        self._lock = threading.Lock()
        self.flush = mock.Mock()
        self.reset_input_buffer = mock.Mock(side_effect=self._clear_rx)
        self.reset_output_buffer = mock.Mock()
        self.writes: list[bytes] = []

    def _clear_rx(self) -> None:
        with self._lock:
            self._rx.clear()

    def queue_rx(self, data: bytes) -> None:
        with self._lock:
            self._rx.extend(data)

    def write(self, data: bytes) -> int:
        payload = bytes(data)
        self.writes.append(payload)
        self._on_write(self, payload)
        return len(payload)

    def read(self, size: int) -> bytes:
        with self._lock:
            if not self._rx:
                return b""
            count = min(size, len(self._rx))
            chunk = bytes(self._rx[:count])
            del self._rx[:count]
            return chunk


class GatewayWorkerTests(unittest.TestCase):
    def test_connect_flushes_uart_buffers_before_emitting_connected(self) -> None:
        worker = worker_mod.GatewayWorker()
        fake_serial = mock.Mock()

        with mock.patch.object(worker_mod.serial, "Serial", return_value=fake_serial):
            with mock.patch.object(worker, "_emit") as emit:
                worker._handle_connect("COM12", 2_000_000)

        fake_serial.reset_input_buffer.assert_called_once_with()
        fake_serial.reset_output_buffer.assert_called_once_with()
        emit.assert_called_once_with("connected", port="COM12", baud=2_000_000)
        self.assertEqual(worker._connected_baud, 2_000_000)

    def test_stream_encrypt_file_on_serial_reports_chunk_metrics_without_flush_by_default(self) -> None:
        fake_serial = mock.Mock()
        chunks = (b"A" * 128, b"B" * 128)

        with mock.patch.object(
            worker_mod, "read_exact", side_effect=[b"\x11" * 128, b"\x22" * 128]
        ):
            with mock.patch.object(
                worker_mod.time,
                "perf_counter",
                side_effect=[
                    0.000,
                    0.001,
                    0.002,
                    0.002,
                    0.010,
                    0.010,
                    0.011,
                    0.012,
                    0.012,
                    0.020,
                ],
            ):
                results = list(
                    worker_mod.stream_encrypt_file_on_serial(
                        fake_serial, "SM4", chunks, 3.0, force_flush=False
                    )
                )

        self.assertEqual(len(results), 2)
        self.assertEqual(results[0].index, 1)
        self.assertAlmostEqual(results[0].write_elapsed_ms, 1.0)
        self.assertAlmostEqual(results[0].read_elapsed_ms, 8.0)
        self.assertAlmostEqual(results[0].chunk_elapsed_ms, 10.0)
        self.assertEqual(results[1].index, 2)
        self.assertAlmostEqual(results[1].write_elapsed_ms, 1.0)
        self.assertAlmostEqual(results[1].read_elapsed_ms, 8.0)
        self.assertAlmostEqual(results[1].chunk_elapsed_ms, 10.0)
        self.assertEqual(fake_serial.write.call_count, 2)
        fake_serial.flush.assert_not_called()

    def test_stream_encrypt_file_on_serial_can_force_flush(self) -> None:
        fake_serial = mock.Mock()

        with mock.patch.object(worker_mod, "read_exact", return_value=b"\x33" * 128):
            with mock.patch.object(
                worker_mod.time,
                "perf_counter",
                side_effect=[0.000, 0.001, 0.002, 0.002, 0.010],
            ):
                results = list(
                    worker_mod.stream_encrypt_file_on_serial(
                        fake_serial, "AES", (b"C" * 128,), 3.0, force_flush=True
                    )
                )

        self.assertEqual(len(results), 1)
        fake_serial.flush.assert_called_once_with()

    def test_handle_encrypt_file_uses_stream_helper_and_emits_extended_metrics(self) -> None:
        worker = worker_mod.GatewayWorker()
        fake_serial = mock.Mock()
        worker._serial = fake_serial
        worker._connected_port = "COM12"
        worker._connected_baud = 2_000_000

        mock_input_path = mock.Mock()
        mock_input_path.read_bytes.return_value = b"A" * 32
        mock_input_path.name = "payload.bin"
        mock_input_path.__str__ = mock.Mock(return_value="payload.bin")
        mock_output_path = mock.Mock()
        mock_output_path.__str__ = mock.Mock(return_value="payload.bin.sm4.bin")
        mock_input_path.with_name.return_value = mock_output_path

        stream_results = iter(
            [
                worker_mod.StreamChunkResult(
                    index=1,
                    plaintext_len=128,
                    ciphertext=b"\x55" * 128,
                    write_elapsed_ms=0.5,
                    read_elapsed_ms=2.5,
                    chunk_elapsed_ms=3.0,
                )
            ]
        )

        with mock.patch.object(worker_mod, "Path", return_value=mock_input_path):
            with mock.patch.object(
                worker_mod, "stream_encrypt_file_on_serial", return_value=stream_results
            ) as stream_call:
                with mock.patch.object(
                    worker_mod, "run_case_on_serial", side_effect=AssertionError("probe path must not run")
                ):
                    worker._handle_encrypt_file("payload.bin", "SM4", 3.0)

        fake_serial.reset_input_buffer.assert_called_once_with()
        fake_serial.reset_output_buffer.assert_called_once_with()
        stream_call.assert_called_once()
        mock_output_path.write_bytes.assert_called_once()

        events = worker.poll_events(8)
        self.assertEqual([event.kind for event in events], ["file_begin", "file_progress", "file_done"])
        progress_payload = events[1].payload
        done_payload = events[2].payload
        self.assertEqual(progress_payload["write_elapsed_ms"], 0.5)
        self.assertEqual(progress_payload["read_elapsed_ms"], 2.5)
        self.assertEqual(progress_payload["chunk_elapsed_ms"], 3.0)
        self.assertEqual(done_payload["avg_write_ms"], 0.5)
        self.assertEqual(done_payload["avg_read_ms"], 2.5)
        self.assertEqual(done_payload["avg_chunk_ms"], 3.0)

    def test_stream_encrypt_file_v3_on_serial_times_out_when_rx_stalls(self) -> None:
        def on_write(fake_serial: FakeStreamSerial, data: bytes) -> None:
            if data == bytes([0x55, 0x01, 0x57]):
                fake_serial.queue_rx(bytes([0x55, 0x04, 0x57, 0x80, 0x01, 0x07]))
            elif data == bytes([0x55, 0x04, 0x4D, 0x53, 0x00, 0x01]):
                fake_serial.queue_rx(bytes([0x55, 0x02, 0x4D, 0x00]))

        fake_serial = FakeStreamSerial(on_write)

        with self.assertRaisesRegex(RuntimeError, "Hardware Link Timeout"):
            worker_mod.stream_encrypt_file_v3_on_serial(
                fake_serial,
                "SM4",
                (b"\x11" * 128,),
                timeout_s=0.01,
                watchdog_s=0.01,
            )

    def test_stream_encrypt_file_v3_on_serial_handles_seq_wrap(self) -> None:
        expected_chunks = tuple(bytes([idx & 0xFF]) * 128 for idx in range(260))

        def on_write(fake_serial: FakeStreamSerial, data: bytes) -> None:
            if data == bytes([0x55, 0x01, 0x57]):
                fake_serial.queue_rx(bytes([0x55, 0x04, 0x57, 0x80, 0x08, 0x07]))
                return
            if data == bytes([0x55, 0x04, 0x4D, 0x41, 0x01, 0x04]):
                fake_serial.queue_rx(bytes([0x55, 0x02, 0x4D, 0x00]))
                return
            self.assertEqual(data[0:2], bytes([0x55, 0x81]))
            seq = data[2]
            ciphertext = bytes([seq]) * 128
            fake_serial.queue_rx(bytes([0x55, 0x82, 0x52, seq]) + ciphertext)

        fake_serial = FakeStreamSerial(on_write)
        result = worker_mod.stream_encrypt_file_v3_on_serial(
            fake_serial,
            "AES",
            expected_chunks,
            timeout_s=0.05,
            watchdog_s=0.05,
        )

        self.assertEqual(result.acked_chunks, 260)
        self.assertEqual(result.total_chunks, 260)
        self.assertEqual(result.ciphertext[:128], bytes([0x00]) * 128)
        self.assertEqual(result.ciphertext[254 * 128 : 255 * 128], bytes([0xFE]) * 128)
        self.assertEqual(result.ciphertext[255 * 128 : 256 * 128], bytes([0xFF]) * 128)
        self.assertEqual(result.ciphertext[256 * 128 : 257 * 128], bytes([0x00]) * 128)
        self.assertEqual(result.ciphertext[259 * 128 : 260 * 128], bytes([0x03]) * 128)

    def test_stream_encrypt_file_v3_on_serial_aborts_after_acl_block(self) -> None:
        def on_write(fake_serial: FakeStreamSerial, data: bytes) -> None:
            if data == bytes([0x55, 0x01, 0x57]):
                fake_serial.queue_rx(bytes([0x55, 0x04, 0x57, 0x80, 0x01, 0x07]))
                return
            if data == bytes([0x55, 0x04, 0x4D, 0x53, 0x00, 0x03]):
                fake_serial.queue_rx(bytes([0x55, 0x02, 0x4D, 0x00]))
                return
            if data[0:2] == bytes([0x55, 0x81]):
                seq = data[2]
                fake_serial.queue_rx(bytes([0x55, 0x03, 0x42, seq, 0x00]))

        fake_serial = FakeStreamSerial(on_write)

        with self.assertRaisesRegex(RuntimeError, "ACL blocked stream chunk"):
            worker_mod.stream_encrypt_file_v3_on_serial(
                fake_serial,
                "SM4",
                (b"\x58" * 128, b"\x11" * 128, b"\x22" * 128),
                timeout_s=0.05,
                watchdog_s=0.05,
            )

        stream_writes = [frame for frame in fake_serial.writes if frame[:2] == bytes([0x55, 0x81])]
        self.assertEqual(len(stream_writes), 1)


if __name__ == "__main__":
    unittest.main()
