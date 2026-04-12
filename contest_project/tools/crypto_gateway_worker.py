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

from crypto_gateway_protocol import build_frame, plan_file_chunks_for_transport, read_exact, run_case_on_serial


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
        result = run_case_on_serial(ser, case, timeout_s)
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

    def _handle_encrypt_file(
        self, input_path: str, algo: str, timeout_s: float, force_flush: bool = False
    ) -> None:
        ser = self._ensure_serial()
        path = Path(input_path)
        raw = path.read_bytes()
        if not raw:
            raise RuntimeError("Selected file is empty")
        plan = plan_file_chunks_for_transport(raw)
        _reset_serial_buffers(ser)
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
        processed_transport = 0
        total_write_ms = 0.0
        total_read_ms = 0.0
        total_chunk_ms = 0.0
        for result in stream_encrypt_file_on_serial(
            ser, algo, plan.chunks, timeout_s, force_flush=force_flush
        ):
            ciphertext.extend(result.ciphertext)
            processed_transport += result.plaintext_len
            total_write_ms += result.write_elapsed_ms
            total_read_ms += result.read_elapsed_ms
            total_chunk_ms += result.chunk_elapsed_ms
            elapsed = max(total_chunk_ms / 1000.0, 1e-9)
            self._emit(
                "file_progress",
                path=str(path),
                algo=algo.upper(),
                processed=processed_transport,
                total=plan.padded_size,
                original_total=plan.original_size,
                pad_bytes=plan.pad_bytes,
                chunk_index=result.index,
                chunk_count=plan.chunk_count,
                chunk=result.plaintext_len,
                throughput_mbps=(processed_transport * 8) / elapsed / 1_000_000.0,
                elapsed_s=elapsed,
                write_elapsed_ms=result.write_elapsed_ms,
                read_elapsed_ms=result.read_elapsed_ms,
                chunk_elapsed_ms=result.chunk_elapsed_ms,
            )

        elapsed = max(total_chunk_ms / 1000.0, 1e-9)
        chunk_count = max(plan.chunk_count, 1)
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
            duration_s=elapsed,
            throughput_mbps=(plan.padded_size * 8) / elapsed / 1_000_000.0,
            avg_write_ms=total_write_ms / chunk_count,
            avg_read_ms=total_read_ms / chunk_count,
            avg_chunk_ms=total_chunk_ms / chunk_count,
            force_flush=force_flush,
        )
