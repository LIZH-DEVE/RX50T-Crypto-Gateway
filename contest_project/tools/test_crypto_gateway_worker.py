import unittest
from unittest import mock
import threading

import crypto_gateway_worker as worker_mod
from crypto_gateway_protocol import (
    BenchResult,
    PmuClearAck,
    PmuSnapshot,
    ProbeCase,
    ProbeResult,
    case_clear_pmu,
    case_force_run_onchip_bench,
    case_query_bench_result,
    case_query_pmu,
    case_run_onchip_bench,
)


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
    def test_handle_case_emits_bench_result_and_pmu_snapshot_for_run(self) -> None:
        worker = worker_mod.GatewayWorker()
        fake_serial = mock.Mock()
        worker._serial = fake_serial

        bench_case = case_run_onchip_bench("SM4")
        bench_probe = ProbeResult(
            case=bench_case,
            rx=bytes.fromhex(
                "55 14 62 01 00 53 00 10 00 00 00 00 00 00 00 00 01 00 12 34 56 78"
            ),
            passed=True,
            duration_s=0.001,
            bench_result=BenchResult(
                version=1,
                status=0x00,
                algo=0x53,
                byte_count=0x0010_0000,
                cycles=0x100,
                crc32=0x1234_5678,
            ),
        )
        pmu_snapshot = PmuSnapshot(
            clk_hz=50_000_000,
            global_cycles=2048,
            crypto_active_cycles=512,
            uart_tx_stall_cycles=256,
            stream_credit_block_cycles=128,
            acl_block_events=0,
        )
        pmu_probe = ProbeResult(
            case=case_query_pmu(),
            rx=pmu_snapshot.as_bytes(),
            passed=True,
            duration_s=0.001,
            pmu_snapshot=pmu_snapshot,
        )

        with mock.patch.object(worker_mod, "run_host_case_on_serial", return_value=bench_probe):
            with mock.patch.object(worker, "_query_pmu_after_session", return_value=pmu_probe):
                worker._handle_case(bench_case, 3.0)

        events = worker.poll_events(4)
        self.assertEqual([event.kind for event in events], ["bench_result", "pmu_snapshot"])
        self.assertEqual(events[0].payload["status"], 0x00)
        self.assertEqual(events[0].payload["algo"], 0x53)
        self.assertAlmostEqual(
            events[0].payload["effective_mbps"],
            (0x0010_0000 * 8 * 50_000_000) / 0x100 / 1_000_000.0,
        )

    def test_handle_case_emits_bench_result_only_for_query(self) -> None:
        worker = worker_mod.GatewayWorker()
        fake_serial = mock.Mock()
        worker._serial = fake_serial

        case = case_query_bench_result()
        result = ProbeResult(
            case=case,
            rx=bytes.fromhex(
                "55 14 62 01 04 41 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00"
            ),
            passed=True,
            duration_s=0.001,
            bench_result=BenchResult(
                version=1,
                status=0x04,
                algo=0x41,
                byte_count=0,
                cycles=0,
                crc32=0,
            ),
        )

        with mock.patch.object(worker_mod, "run_host_case_on_serial", return_value=result):
            worker._handle_case(case, 3.0)

        events = worker.poll_events(2)
        self.assertEqual([event.kind for event in events], ["bench_result"])
        self.assertEqual(events[0].payload["status"], 0x04)

    def test_handle_case_uses_force_run_helper_for_force_bench(self) -> None:
        worker = worker_mod.GatewayWorker()
        fake_serial = mock.Mock()
        worker._serial = fake_serial
        worker._connected_baud = 2_000_000

        force_case = case_force_run_onchip_bench("SM4")
        bench_probe = ProbeResult(
            case=force_case,
            rx=bytes.fromhex(
                "55 14 62 01 00 53 00 10 00 00 00 00 00 00 00 00 01 00 12 34 56 78"
            ),
            passed=True,
            duration_s=0.001,
            bench_result=BenchResult(
                version=1,
                status=0x00,
                algo=0x53,
                byte_count=0x0010_0000,
                cycles=0x100,
                crc32=0x1234_5678,
            ),
        )
        pmu_snapshot = PmuSnapshot(
            clk_hz=50_000_000,
            global_cycles=2048,
            crypto_active_cycles=512,
            uart_tx_stall_cycles=256,
            stream_credit_block_cycles=128,
            acl_block_events=0,
        )
        pmu_probe = ProbeResult(
            case=case_query_pmu(),
            rx=pmu_snapshot.as_bytes(),
            passed=True,
            duration_s=0.001,
            pmu_snapshot=pmu_snapshot,
        )

        with mock.patch.object(worker_mod, "run_host_case_on_serial", return_value=bench_probe) as host_run:
            with mock.patch.object(worker, "_query_pmu_after_session", return_value=pmu_probe) as query_pmu:
                worker._handle_case(force_case, 3.0)

        host_run.assert_called_once_with(fake_serial, force_case, 3.0, baud=2_000_000)
        query_pmu.assert_called_once_with(fake_serial, 3.0, emit=False)
        events = worker.poll_events(4)
        self.assertEqual([event.kind for event in events], ["bench_result", "pmu_snapshot"])
        self.assertEqual(events[0].payload["algo"], 0x53)

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

    def test_handle_encrypt_file_uses_stream_v3_helper_and_emits_extended_metrics(self) -> None:
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
        pmu_snapshot = PmuSnapshot(
            clk_hz=50_000_000,
            global_cycles=2048,
            crypto_active_cycles=512,
            uart_tx_stall_cycles=256,
            stream_credit_block_cycles=128,
            acl_block_events=0,
        )

        def fake_v3_helper(ser, algo, chunks, timeout_s, **kwargs):
            progress_cb = kwargs["progress_cb"]
            progress_cb(
                acked_chunks=1,
                total_chunks=1,
                processed_bytes=128,
                total_bytes=128,
                chunk_bytes=128,
                elapsed_s=0.003,
                throughput_mbps=(128 * 8) / 0.003 / 1_000_000.0,
            )
            return worker_mod.StreamSessionResult(
                total_chunks=1,
                acked_chunks=1,
                ciphertext=b"\x55" * 128,
                session_elapsed_s=0.003,
                effective_mbps=(128 * 8) / 0.003 / 1_000_000.0,
            )

        def fake_run_case(ser, case, timeout_s):
            if case.kind == "pmu_clear":
                return ProbeResult(
                    case=case,
                    rx=bytes([0x55, 0x02, 0x4A, 0x00]),
                    passed=True,
                    duration_s=0.001,
                    pmu_clear_ack=PmuClearAck(status=0),
                )
            if case.kind == "pmu_query":
                return ProbeResult(
                    case=case,
                    rx=pmu_snapshot.as_bytes(),
                    passed=True,
                    duration_s=0.001,
                    pmu_snapshot=pmu_snapshot,
                )
            raise AssertionError(f"unexpected probe kind: {case.kind}")

        with mock.patch.object(worker_mod, "Path", return_value=mock_input_path):
            with mock.patch.object(worker_mod, "run_case_on_serial", side_effect=fake_run_case):
                with mock.patch.object(
                    worker_mod, "stream_encrypt_file_v3_on_serial", side_effect=fake_v3_helper
                ) as stream_call:
                    with mock.patch.object(
                        worker_mod, "stream_encrypt_file_on_serial", side_effect=AssertionError("legacy V2 path must not run")
                    ):
                        worker._handle_encrypt_file("payload.bin", "SM4", 3.0)

        stream_call.assert_called_once()
        mock_output_path.write_bytes.assert_called_once()

        events = worker.poll_events(8)
        self.assertEqual(
            [event.kind for event in events],
            ["pmu_cleared", "file_begin", "file_progress", "file_done", "pmu_snapshot"],
        )
        progress_payload = events[2].payload
        done_payload = events[3].payload
        self.assertEqual(progress_payload["chunk_index"], 1)
        self.assertEqual(progress_payload["chunk_count"], 1)
        self.assertEqual(progress_payload["chunk"], 128)
        self.assertAlmostEqual(progress_payload["elapsed_s"], 0.003)
        self.assertAlmostEqual(done_payload["duration_s"], 0.003)
        self.assertEqual(done_payload["chunk_count"], 1)
        self.assertEqual(events[0].payload["status"], 0)
        self.assertAlmostEqual(events[-1].payload["crypto_utilization"], 0.25)

    def test_handle_case_emits_pmu_snapshot_event(self) -> None:
        worker = worker_mod.GatewayWorker()
        fake_serial = mock.Mock()
        worker._serial = fake_serial

        snapshot = PmuSnapshot(
            clk_hz=50_000_000,
            global_cycles=1000,
            crypto_active_cycles=250,
            uart_tx_stall_cycles=500,
            stream_credit_block_cycles=125,
            acl_block_events=2,
        )
        case = case_query_pmu()
        result = ProbeResult(
            case=case,
            rx=snapshot.as_bytes(),
            passed=True,
            duration_s=0.001,
            pmu_snapshot=snapshot,
        )

        with mock.patch.object(worker_mod, "run_host_case_on_serial", return_value=result):
            worker._handle_case(case, 3.0)

        events = worker.poll_events(1)
        self.assertEqual(len(events), 1)
        self.assertEqual(events[0].kind, "pmu_snapshot")
        self.assertEqual(events[0].payload["clk_hz"], 50_000_000)
        self.assertAlmostEqual(events[0].payload["crypto_utilization"], 0.25)
        self.assertAlmostEqual(events[0].payload["uart_stall_ratio"], 0.5)
        self.assertAlmostEqual(events[0].payload["credit_block_ratio"], 0.125)
        self.assertEqual(events[0].payload["acl_block_events"], 2)

    def test_handle_case_emits_pmu_cleared_event(self) -> None:
        worker = worker_mod.GatewayWorker()
        fake_serial = mock.Mock()
        worker._serial = fake_serial

        case = case_clear_pmu()
        result = ProbeResult(
            case=case,
            rx=bytes([0x55, 0x02, 0x4A, 0x00]),
            passed=True,
            duration_s=0.001,
            pmu_clear_ack=PmuClearAck(status=0),
        )

        with mock.patch.object(worker_mod, "run_host_case_on_serial", return_value=result):
            worker._handle_case(case, 3.0)

        events = worker.poll_events(1)
        self.assertEqual(len(events), 1)
        self.assertEqual(events[0].kind, "pmu_cleared")
        self.assertEqual(events[0].payload["status"], 0)

    def test_handle_encrypt_file_clears_and_queries_pmu_around_stream_run(self) -> None:
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

        pmu_snapshot = PmuSnapshot(
            clk_hz=50_000_000,
            global_cycles=2000,
            crypto_active_cycles=300,
            uart_tx_stall_cycles=1000,
            stream_credit_block_cycles=200,
            acl_block_events=0,
        )

        def fake_v3_helper(ser, algo, chunks, timeout_s, **kwargs):
            progress_cb = kwargs["progress_cb"]
            progress_cb(
                acked_chunks=1,
                total_chunks=1,
                processed_bytes=128,
                total_bytes=128,
                chunk_bytes=128,
                elapsed_s=0.003,
                throughput_mbps=(128 * 8) / 0.003 / 1_000_000.0,
            )
            return worker_mod.StreamSessionResult(
                total_chunks=1,
                acked_chunks=1,
                ciphertext=b"\xAA" * 128,
                session_elapsed_s=0.003,
                effective_mbps=(128 * 8) / 0.003 / 1_000_000.0,
            )

        def fake_run_case(ser, case, timeout_s):
            if case.kind == "pmu_clear":
                return ProbeResult(
                    case=case,
                    rx=bytes([0x55, 0x02, 0x4A, 0x00]),
                    passed=True,
                    duration_s=0.001,
                    pmu_clear_ack=PmuClearAck(status=0),
                )
            if case.kind == "pmu_query":
                return ProbeResult(
                    case=case,
                    rx=pmu_snapshot.as_bytes(),
                    passed=True,
                    duration_s=0.001,
                    pmu_snapshot=pmu_snapshot,
                )
            raise AssertionError(f"unexpected probe kind: {case.kind}")

        with mock.patch.object(worker_mod, "Path", return_value=mock_input_path):
            with mock.patch.object(worker_mod, "run_case_on_serial", side_effect=fake_run_case):
                with mock.patch.object(
                    worker_mod, "stream_encrypt_file_v3_on_serial", side_effect=fake_v3_helper
                ):
                    worker._handle_encrypt_file("payload.bin", "SM4", 3.0)

        events = worker.poll_events(8)
        self.assertEqual(
            [event.kind for event in events],
            ["pmu_cleared", "file_begin", "file_progress", "file_done", "pmu_snapshot"],
        )
        self.assertAlmostEqual(events[-1].payload["crypto_utilization"], 0.15)
        self.assertEqual(events[-1].payload["acl_block_events"], 0)

    def test_handle_encrypt_file_retries_pmu_query_after_stream_acl_block(self) -> None:
        worker = worker_mod.GatewayWorker()
        fake_serial = mock.Mock()
        worker._serial = fake_serial
        worker._connected_port = "COM12"
        worker._connected_baud = 2_000_000

        mock_input_path = mock.Mock()
        mock_input_path.read_bytes.return_value = b"A" * 128
        mock_input_path.name = "blocked.bin"
        mock_input_path.__str__ = mock.Mock(return_value="blocked.bin")

        pmu_snapshot = PmuSnapshot(
            clk_hz=50_000_000,
            global_cycles=5000,
            crypto_active_cycles=0,
            uart_tx_stall_cycles=250,
            stream_credit_block_cycles=0,
            acl_block_events=1,
        )

        def fake_run_case(ser, case, timeout_s):
            if case.kind == "pmu_clear":
                return ProbeResult(
                    case=case,
                    rx=bytes([0x55, 0x02, 0x4A, 0x00]),
                    passed=True,
                    duration_s=0.001,
                    pmu_clear_ack=PmuClearAck(status=0),
                )
            if case.kind == "pmu_query":
                fake_run_case.pmu_queries += 1
                if fake_run_case.pmu_queries == 1:
                    return ProbeResult(
                        case=case,
                        rx=bytes([0x55, 0x02, 0x45, 0x02]),
                        passed=False,
                    )
                return ProbeResult(
                    case=case,
                    rx=pmu_snapshot.as_bytes(),
                    passed=True,
                    duration_s=0.001,
                    pmu_snapshot=pmu_snapshot,
                )
            raise AssertionError(f"unexpected probe kind: {case.kind}")

        fake_run_case.pmu_queries = 0

        with mock.patch.object(worker_mod, "Path", return_value=mock_input_path):
            with mock.patch.object(worker_mod, "run_case_on_serial", side_effect=fake_run_case):
                with mock.patch.object(
                    worker_mod,
                    "stream_encrypt_file_v3_on_serial",
                    side_effect=RuntimeError("ACL blocked stream chunk seq=0x00 slot=5"),
                ):
                    with mock.patch.object(worker_mod.time, "sleep") as sleep_mock:
                        with self.assertRaisesRegex(RuntimeError, "ACL blocked stream chunk"):
                            worker._handle_encrypt_file("blocked.bin", "SM4", 3.0)

        self.assertEqual(fake_run_case.pmu_queries, 2)
        self.assertTrue(sleep_mock.called)
        events = worker.poll_events(8)
        self.assertEqual(
            [event.kind for event in events],
            ["pmu_cleared", "file_begin", "pmu_snapshot"],
        )
        self.assertEqual(events[-1].payload["acl_block_events"], 1)

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
