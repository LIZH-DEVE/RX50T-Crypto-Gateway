from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
import queue
import threading
import time

try:
    import serial
    from serial.tools import list_ports
except ImportError as exc:  # pragma: no cover
    raise SystemExit(
        "pyserial is required. Install it with: py -3 -m pip install pyserial"
    ) from exc

from crypto_gateway_protocol import (
    BenchResult,
    StreamBlockResponse,
    FatalErrorResponse,
    StreamCipherResponse,
    StreamErrorResponse,
    StreamStartAck,
    build_frame,
    case_clear_pmu,
    case_query_pmu,
    build_stream_capability_query,
    build_stream_chunk_frame,
    build_stream_start_frame,
    parse_stream_response,
    plan_file_chunks_for_transport,
    read_exact,
    run_host_case_on_serial,
    run_case_on_serial,
)


class HardwareFatalError(RuntimeError):
    def __init__(self, code: int):
        super().__init__(f"Hardware fatal error: 0x{code:02X}")
        self.code = code


@dataclass(frozen=True)
class WorkerEvent:
    kind: str
    payload: dict


@dataclass(frozen=True)
class StreamChunkResult:
    index: int
    plaintext_len: int
    ciphertext: bytes
    write_elapsed_ms: float
    read_elapsed_ms: float
    chunk_elapsed_ms: float


@dataclass(frozen=True)
class StreamSessionResult:
    total_chunks: int
    acked_chunks: int
    ciphertext: bytes
    session_elapsed_s: float
    effective_mbps: float


def _read_framed_response(
    ser: serial.Serial,
    *,
    timeout_s: float,
    watchdog_s: float,
) -> bytes:
    started = time.perf_counter()
    header = bytearray()
    while len(header) < 2:
        chunk = ser.read(2 - len(header))
        if chunk:
            header.extend(chunk)
            continue
        elapsed = time.perf_counter() - started
        if elapsed >= min(timeout_s, watchdog_s):
            raise RuntimeError("Hardware Link Timeout")

    payload_len = header[1]
    payload = bytearray()
    payload_started = time.perf_counter()
    while len(payload) < payload_len:
        chunk = ser.read(payload_len - len(payload))
        if chunk:
            payload.extend(chunk)
            continue
        elapsed = time.perf_counter() - payload_started
        if elapsed >= min(timeout_s, watchdog_s):
            raise RuntimeError("Hardware Link Timeout")

    return bytes(header + payload)


def _reset_serial_buffers(ser: serial.Serial) -> None:
    try:
        ser.reset_input_buffer()
        ser.reset_output_buffer()
    except AttributeError:  # pragma: no cover - older pyserial fallback
        ser.flushInput()
        ser.flushOutput()


def _build_encrypt_frame(algo: str, plaintext: bytes) -> bytes:
    normalized = algo.strip().upper()
    if normalized not in {"AES", "SM4"}:
        raise ValueError("algo must be AES or SM4")
    if len(plaintext) % 16 != 0 or len(plaintext) == 0 or len(plaintext) > 240:
        raise ValueError("plaintext length must be a non-zero multiple of 16 bytes and <= 240 bytes")
    return build_frame((b"A" + plaintext) if normalized == "AES" else plaintext)


def stream_encrypt_file_on_serial(
    ser: serial.Serial,
    algo: str,
    chunks: tuple[bytes, ...],
    timeout_s: float,
    *,
    force_flush: bool = False,
):
    for index, chunk in enumerate(chunks, start=1):
        tx = _build_encrypt_frame(algo, chunk)
        chunk_started = time.perf_counter()
        write_started = time.perf_counter()
        ser.write(tx)
        if force_flush:
            ser.flush()
        write_finished = time.perf_counter()
        read_started = time.perf_counter()
        rx = read_exact(ser, len(chunk), timeout_s)
        read_finished = time.perf_counter()
        if len(rx) != len(chunk):
            raise RuntimeError(f"Unexpected ciphertext length for chunk {index}: {len(rx)}")
        yield StreamChunkResult(
            index=index,
            plaintext_len=len(chunk),
            ciphertext=rx,
            write_elapsed_ms=(write_finished - write_started) * 1000.0,
            read_elapsed_ms=(read_finished - read_started) * 1000.0,
            chunk_elapsed_ms=(read_finished - chunk_started) * 1000.0,
        )


def stream_encrypt_file_v3_on_serial(
    ser: serial.Serial,
    algo: str,
    chunks: tuple[bytes, ...],
    timeout_s: float,
    *,
    watchdog_s: float = 2.0,
    progress_cb=None,
    report_interval_s: float = 0.1,
) -> StreamSessionResult:
    if not chunks:
        raise ValueError("chunks must not be empty")

    capability_started = time.perf_counter()
    ser.write(build_stream_capability_query())
    capability = parse_stream_response(
        _read_framed_response(ser, timeout_s=timeout_s, watchdog_s=watchdog_s)
    )
    if not hasattr(capability, "chunk_size"):
        raise RuntimeError("Invalid stream capability response")
    if capability.chunk_size != 128:
        raise RuntimeError(f"Unsupported stream chunk size: {capability.chunk_size}")

    ser.write(build_stream_start_frame(algo, len(chunks)))
    start_ack = parse_stream_response(
        _read_framed_response(ser, timeout_s=timeout_s, watchdog_s=watchdog_s)
    )
    if not isinstance(start_ack, StreamStartAck) or start_ack.status != 0:
        raise RuntimeError("Stream session start rejected")

    window = max(1, int(capability.window))
    started = capability_started
    last_progress = time.perf_counter()
    send_index = 0
    committed_index = 0
    outstanding: dict[int, int] = {}
    received: dict[int, bytes] = {}
    ciphertext = bytearray()
    last_reported_chunks = 0
    last_report_time = started

    while committed_index < len(chunks):
        while send_index < len(chunks) and len(outstanding) < window:
            seq = send_index & 0xFF
            if seq in outstanding:
                raise RuntimeError(f"Stream seq collision at 0x{seq:02X}")
            ser.write(build_stream_chunk_frame(seq, chunks[send_index]))
            outstanding[seq] = send_index
            send_index += 1
            last_progress = time.perf_counter()

        response = parse_stream_response(
            _read_framed_response(ser, timeout_s=timeout_s, watchdog_s=watchdog_s)
        )
        last_progress = time.perf_counter()

        if isinstance(response, StreamCipherResponse):
            if response.seq not in outstanding:
                raise RuntimeError(f"Unexpected stream seq 0x{response.seq:02X}")
            absolute_index = outstanding.pop(response.seq)
            received[absolute_index] = response.ciphertext
            while committed_index in received:
                ciphertext.extend(received.pop(committed_index))
                committed_index += 1
            elapsed = max(time.perf_counter() - started, 1e-9)
            should_report = (
                progress_cb is not None and (
                    committed_index == len(chunks) or
                    committed_index != last_reported_chunks and
                    (time.perf_counter() - last_report_time) >= report_interval_s
                )
            )
            if should_report:
                progress_cb(
                    acked_chunks=committed_index,
                    total_chunks=len(chunks),
                    processed_bytes=len(ciphertext),
                    total_bytes=len(chunks) * capability.chunk_size,
                    chunk_bytes=len(response.ciphertext),
                    elapsed_s=elapsed,
                    throughput_mbps=(len(ciphertext) * 8) / elapsed / 1_000_000.0,
                )
                last_reported_chunks = committed_index
                last_report_time = time.perf_counter()
            continue

        if isinstance(response, StreamBlockResponse):
            raise RuntimeError(
                f"ACL blocked stream chunk seq=0x{response.seq:02X} slot={response.slot}"
            )

        if isinstance(response, StreamErrorResponse):
            raise RuntimeError(f"Stream error code=0x{response.code:02X}")

        if isinstance(response, FatalErrorResponse):
            raise HardwareFatalError(response.code)

        raise RuntimeError("Unexpected stream response type")

    elapsed = max(time.perf_counter() - started, 1e-9)
    return StreamSessionResult(
        total_chunks=len(chunks),
        acked_chunks=committed_index,
        ciphertext=bytes(ciphertext),
        session_elapsed_s=elapsed,
        effective_mbps=(len(ciphertext) * 8) / elapsed / 1_000_000.0,
    )


class GatewayWorker:
    def __init__(self) -> None:
        self._task_q: queue.Queue[tuple[str, dict] | None] = queue.Queue()
        self._event_q: queue.Queue[WorkerEvent] = queue.Queue()
        self._stop = threading.Event()
        self._thread = threading.Thread(target=self._run, daemon=True)
        self._serial: serial.Serial | None = None
        self._connected_port: str | None = None
        self._connected_baud: int | None = None

    def start(self) -> None:
        if not self._thread.is_alive():
            self._thread.start()

    def stop(self) -> None:
        self._task_q.put(None)
        self._stop.set()
        if self._thread.is_alive():
            self._thread.join(timeout=2.0)
        self._close_serial()

    def connect(self, port: str, baud: int) -> None:
        self._task_q.put(("connect", {"port": port, "baud": baud}))

    def disconnect(self) -> None:
        self._task_q.put(("disconnect", {}))

    def submit_case(self, case, timeout_s: float = 3.0) -> None:
        self._task_q.put(("run_case", {"case": case, "timeout_s": timeout_s}))

    def encrypt_file(self, input_path: str, algo: str, timeout_s: float = 3.0) -> None:
        self._task_q.put(
            (
                "encrypt_file",
                {
                    "input_path": input_path,
                    "algo": algo,
                    "timeout_s": timeout_s,
                    "force_flush": False,
                },
            )
        )

    def poll_events(self, max_items: int = 32) -> list[WorkerEvent]:
        items: list[WorkerEvent] = []
        for _ in range(max_items):
            try:
                items.append(self._event_q.get_nowait())
            except queue.Empty:
                break
        return items

    @staticmethod
    def list_ports() -> list[str]:
        return sorted(port.device for port in list_ports.comports())

    def _emit(self, kind: str, **payload: object) -> None:
        self._event_q.put(WorkerEvent(kind=kind, payload=dict(payload)))

    def _close_serial(self) -> None:
        if self._serial is not None:
            try:
                self._serial.close()
            except Exception:
                pass
        self._serial = None
        self._connected_port = None
        self._connected_baud = None

    def _run(self) -> None:
        while not self._stop.is_set():
            try:
                task = self._task_q.get(timeout=0.1)
            except queue.Empty:
                continue

            if task is None:
                break

            kind, payload = task
            try:
                if kind == "connect":
                    self._handle_connect(payload["port"], int(payload["baud"]))
                elif kind == "disconnect":
                    self._handle_disconnect()
                elif kind == "run_case":
                    self._handle_case(payload["case"], float(payload["timeout_s"]))
                elif kind == "encrypt_file":
                    self._handle_encrypt_file(
                        payload["input_path"],
                        payload["algo"],
                        float(payload["timeout_s"]),
                        bool(payload.get("force_flush", False)),
                    )
            except Exception as exc:  # pragma: no cover
                self._emit("error", message=str(exc))

    def _ensure_serial(self) -> serial.Serial:
        if self._serial is None:
            raise RuntimeError("Serial port is not connected")
        return self._serial

    def _handle_connect(self, port: str, baud: int) -> None:
        self._close_serial()
        self._serial = serial.Serial(port, baud, timeout=0.1)
        _reset_serial_buffers(self._serial)
        self._connected_port = port
        self._connected_baud = baud
        self._emit("connected", port=port, baud=baud)

    def _handle_disconnect(self) -> None:
        port = self._connected_port
        self._close_serial()
        self._emit("disconnected", port=port)

    def _handle_case(self, case, timeout_s: float) -> None:
        ser = self._ensure_serial()
        result = run_host_case_on_serial(ser, case, timeout_s, baud=self._connected_baud)

        if result.fatal_error is not None:
            self._emit(
                "fatal_error",
                name=case.name,
                tx=result.tx,
                rx=result.rx,
                expected=result.expected,
                passed=result.passed,
                duration_s=result.duration_s,
                throughput_mbps=result.throughput_mbps,
                description=case.description,
                code=result.fatal_error.code,
            )
            return

        if result.pmu_snapshot is not None:
            self._emit_pmu_snapshot(result)
            return

        if result.pmu_clear_ack is not None:
            self._emit(
                "pmu_cleared",
                name=case.name,
                tx=result.tx,
                rx=result.rx,
                expected=result.expected,
                passed=result.passed,
                duration_s=result.duration_s,
                throughput_mbps=result.throughput_mbps,
                description=case.description,
                status=result.pmu_clear_ack.status,
            )
            return

        if result.bench_result is not None:
            pmu_result = None
            if case.kind in {"bench_run", "bench_force"}:
                try:
                    pmu_result = self._query_pmu_after_session(ser, timeout_s, emit=False)
                except Exception:
                    pmu_result = None
            self._emit_bench_result(result, pmu_result.pmu_snapshot if pmu_result is not None else None)
            if pmu_result is not None:
                self._emit_pmu_snapshot(pmu_result)
            return

        if result.acl_write_ack is not None:
            self._emit(
                "acl_write_ack",
                name=case.name,
                tx=result.tx,
                rx=result.rx,
                expected=result.expected,
                passed=result.passed,
                duration_s=result.duration_s,
                throughput_mbps=result.throughput_mbps,
                description=case.description,
                index=result.acl_write_ack.index,
                key=result.acl_write_ack.key,
            )
            return

        if case.kind == "acl_write":
            self._emit(
                "acl_write_error",
                name=case.name,
                tx=result.tx,
                rx=result.rx,
                expected=result.expected,
                passed=result.passed,
                duration_s=result.duration_s,
                throughput_mbps=result.throughput_mbps,
                description=case.description,
            )
            return

        if result.acl_key_map is not None:
            self._emit(
                "acl_key_map",
                name=case.name,
                tx=result.tx,
                rx=result.rx,
                expected=result.expected,
                passed=result.passed,
                duration_s=result.duration_s,
                throughput_mbps=result.throughput_mbps,
                description=case.description,
                keys=result.acl_key_map.keys,
                labels=result.acl_key_map.display_labels(),
            )
            return

        self._emit(
            "result",
            name=case.name,
            tx=result.tx,
            rx=result.rx,
            expected=result.expected,
            passed=result.passed,
            duration_s=result.duration_s,
            throughput_mbps=result.throughput_mbps,
            stats=result.stats,
            rule_stats=result.rule_stats,
            description=case.description,
        )

    def _emit_bench_result(self, result, snapshot: PmuSnapshot | None = None) -> None:
        bench = result.bench_result
        if bench is None:
            raise RuntimeError("missing bench result")
        self._emit(
            "bench_result",
            name=result.case.name,
            tx=result.tx,
            rx=result.rx,
            expected=result.expected,
            passed=result.passed,
            duration_s=result.duration_s,
            throughput_mbps=result.throughput_mbps,
            description=result.case.description,
            version=bench.version,
            status=bench.status,
            status_text=bench.status_name,
            algo=bench.algo,
            algo_name=bench.algo_name,
            byte_count=bench.byte_count,
            cycles=bench.cycles,
            crc32=bench.crc32,
            effective_mbps=bench.effective_mbps(snapshot.clk_hz) if snapshot is not None else None,
        )

    def _emit_pmu_snapshot(self, result) -> None:
        snapshot = result.pmu_snapshot
        if snapshot is None:
            raise RuntimeError("missing PMU snapshot")
        self._emit(
            "pmu_snapshot",
            name=result.case.name,
            tx=result.tx,
            rx=result.rx,
            expected=result.expected,
            passed=result.passed,
            duration_s=result.duration_s,
            throughput_mbps=result.throughput_mbps,
            description=result.case.description,
            clk_hz=snapshot.clk_hz,
            global_cycles=snapshot.global_cycles,
            crypto_active_cycles=snapshot.crypto_active_cycles,
            uart_tx_stall_cycles=snapshot.uart_tx_stall_cycles,
            stream_credit_block_cycles=snapshot.stream_credit_block_cycles,
            acl_block_events=snapshot.acl_block_events,
            crypto_utilization=snapshot.crypto_utilization,
            uart_stall_ratio=snapshot.uart_stall_ratio,
            credit_block_ratio=snapshot.credit_block_ratio,
            elapsed_ms_from_hw=snapshot.elapsed_ms_from_hw,
            stream_bytes_in=snapshot.stream_bytes_in,
            stream_bytes_out=snapshot.stream_bytes_out,
            stream_chunk_count=snapshot.stream_chunk_count,
        )

    def _query_pmu_after_session(
        self, ser: serial.Serial, timeout_s: float, *, emit: bool = True
    ):
        last_error: Exception | None = None
        for attempt in range(3):
            try:
                result = run_case_on_serial(ser, case_query_pmu(), timeout_s)
            except Exception as exc:
                last_error = exc
            else:
                if result.pmu_snapshot is not None:
                    if emit:
                        self._emit_pmu_snapshot(result)
                    return result
                last_error = RuntimeError("invalid PMU snapshot response")

            if attempt < 2:
                _reset_serial_buffers(ser)
                time.sleep(0.05)

        if last_error is None:
            raise RuntimeError("invalid PMU snapshot response")
        raise last_error

    def _clear_pmu_before_session(self, ser: serial.Serial, timeout_s: float) -> None:
        result = run_case_on_serial(ser, case_clear_pmu(), timeout_s)
        if result.pmu_clear_ack is None:
            raise RuntimeError("invalid PMU clear response")
        self._emit(
            "pmu_cleared",
            name=result.case.name,
            tx=result.tx,
            rx=result.rx,
            expected=result.expected,
            passed=result.passed,
            duration_s=result.duration_s,
            throughput_mbps=result.throughput_mbps,
            description=result.case.description,
            status=result.pmu_clear_ack.status,
        )

    def _handle_encrypt_file(
        self, input_path: str, algo: str, timeout_s: float, force_flush: bool = False
    ) -> None:
        ser = self._ensure_serial()
        path = Path(input_path)
        raw = path.read_bytes()
        if not raw:
            raise RuntimeError("Selected file is empty")
        plan = plan_file_chunks_for_transport(raw)
        self._clear_pmu_before_session(ser, timeout_s)
        self._emit(
            "file_begin",
            path=str(path),
            algo=algo.upper(),
            original_bytes=plan.original_size,
            total_bytes=plan.padded_size,
            pad_bytes=plan.pad_bytes,
            chunk_count=plan.chunk_count,
            mtu_bytes=128,
        )

        ciphertext = bytearray()
        def emit_progress(
            *,
            acked_chunks: int,
            total_chunks: int,
            processed_bytes: int,
            total_bytes: int,
            chunk_bytes: int,
            elapsed_s: float,
            throughput_mbps: float,
        ) -> None:
            self._emit(
                "file_progress",
                path=str(path),
                algo=algo.upper(),
                processed=processed_bytes,
                total=total_bytes,
                original_total=plan.original_size,
                pad_bytes=plan.pad_bytes,
                chunk_index=acked_chunks,
                chunk_count=total_chunks,
                chunk=chunk_bytes,
                throughput_mbps=throughput_mbps,
                elapsed_s=elapsed_s,
                write_elapsed_ms=0.0,
                read_elapsed_ms=0.0,
                chunk_elapsed_ms=0.0,
            )
        try:
            result = stream_encrypt_file_v3_on_serial(
                ser,
                algo,
                plan.chunks,
                timeout_s,
                progress_cb=emit_progress,
            )
            ciphertext.extend(result.ciphertext)
            suffix = ".aes.bin" if algo.strip().upper() == "AES" else ".sm4.bin"
            output_path = path.with_name(path.name + suffix)
            output_path.write_bytes(bytes(ciphertext))
            self._emit(
                "file_done",
                path=str(path),
                output_path=str(output_path),
                algo=algo.upper(),
                total_bytes=plan.padded_size,
                original_bytes=plan.original_size,
                pad_bytes=plan.pad_bytes,
                chunk_count=plan.chunk_count,
                duration_s=result.session_elapsed_s,
                throughput_mbps=result.effective_mbps,
                avg_write_ms=0.0,
                avg_read_ms=0.0,
                avg_chunk_ms=(result.session_elapsed_s * 1000.0) / max(result.total_chunks, 1),
                force_flush=force_flush,
            )
        except HardwareFatalError as exc:
            self._emit(
                "fatal_error",
                name="Stream Encrypt File",
                path=str(path),
                algo=algo.upper(),
                code=exc.code,
                tx=b"",
                rx=b"",
                expected=None,
                passed=False,
                duration_s=0.0,
                throughput_mbps=0.0,
                description="Hardware watchdog timeout or fatal error during stream operation",
            )
            try:
                self._query_pmu_after_session(ser, timeout_s)
            except Exception:
                pass
            return
        except Exception:
            try:
                self._query_pmu_after_session(ser, timeout_s)
            except Exception:
                pass
            raise

        self._query_pmu_after_session(ser, timeout_s)
