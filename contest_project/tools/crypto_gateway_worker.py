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
    case_encrypt_block,
    plan_file_chunks_for_transport,
    run_case_on_serial,
)


@dataclass(frozen=True)
class WorkerEvent:
    kind: str
    payload: dict


class GatewayWorker:
    def __init__(self) -> None:
        self._task_q: queue.Queue[tuple[str, dict] | None] = queue.Queue()
        self._event_q: queue.Queue[WorkerEvent] = queue.Queue()
        self._stop = threading.Event()
        self._thread = threading.Thread(target=self._run, daemon=True)
        self._serial: serial.Serial | None = None
        self._connected_port: str | None = None

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
            ("encrypt_file", {"input_path": input_path, "algo": algo, "timeout_s": timeout_s})
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
                        payload["input_path"], payload["algo"], float(payload["timeout_s"])
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
        self._connected_port = port
        self._emit("connected", port=port, baud=baud)

    def _handle_disconnect(self) -> None:
        port = self._connected_port
        self._close_serial()
        self._emit("disconnected", port=port)

    def _handle_case(self, case, timeout_s: float) -> None:
        ser = self._ensure_serial()
        result = run_case_on_serial(ser, case, timeout_s)
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

    def _handle_encrypt_file(self, input_path: str, algo: str, timeout_s: float) -> None:
        ser = self._ensure_serial()
        path = Path(input_path)
        raw = path.read_bytes()
        if not raw:
            raise RuntimeError("Selected file is empty")
        plan = plan_file_chunks_for_transport(raw)

        ciphertext = bytearray()
        started = time.perf_counter()
        processed_transport = 0
        for index, chunk in enumerate(plan.chunks, start=1):
            case = case_encrypt_block(algo, chunk)
            result = run_case_on_serial(ser, case, timeout_s)
            if len(result.rx) != len(chunk):
                raise RuntimeError(
                    f"Unexpected ciphertext length for chunk {index}: {len(result.rx)}"
                )
            ciphertext.extend(result.rx)
            processed_transport += len(chunk)
            elapsed = max(time.perf_counter() - started, 1e-9)
            self._emit(
                "file_progress",
                path=str(path),
                algo=algo.upper(),
                processed=processed_transport,
                total=plan.padded_size,
                original_total=plan.original_size,
                pad_bytes=plan.pad_bytes,
                chunk_index=index,
                chunk_count=plan.chunk_count,
                chunk=len(chunk),
                throughput_mbps=(processed_transport * 8) / elapsed / 1_000_000.0,
                elapsed_s=elapsed,
            )

        elapsed = max(time.perf_counter() - started, 1e-9)
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
        )
