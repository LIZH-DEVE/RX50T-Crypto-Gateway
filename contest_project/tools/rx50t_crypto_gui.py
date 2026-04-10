from __future__ import annotations

from collections import deque
from datetime import datetime
from pathlib import Path
import tkinter as tk
from tkinter import filedialog, messagebox, scrolledtext, ttk

from crypto_gateway_protocol import (
    AclRuleCounters,
    DEFAULT_ACL_RULES,
    StatsCounters,
    case_aes_eight_block_vector,
    case_aes_four_block_vector,
    case_aes_known_vector,
    case_aes_two_block_vector,
    case_block_ascii,
    case_invalid_selector,
    case_query_rule_stats,
    case_query_stats,
    case_sm4_eight_block_vector,
    case_sm4_four_block_vector,
    case_sm4_known_vector,
    case_sm4_two_block_vector,
    extract_first_payload_key,
    format_hex,
)
from crypto_gateway_worker import GatewayWorker, WorkerEvent


class CryptoGatewayApp(tk.Tk):
    def __init__(self) -> None:
        super().__init__()
        self.title("RX50T Crypto Gateway Console")
        self.geometry("1180x860")
        self.minsize(1040, 760)

        self.worker = GatewayWorker()
        self.worker.start()

        self.mbps_history: deque[float] = deque([0.0] * 60, maxlen=60)
        self.current_port = tk.StringVar(value="COM12")
        self.current_baud = tk.IntVar(value=115200)
        self.acl_text = tk.StringVar(value="XYZ")
        self.file_algo = tk.StringVar(value="SM4")
        self.connection_state = tk.StringVar(value="Disconnected")
        self.throughput_label = tk.StringVar(value="0.000 Mbps")
        self.last_latency_label = tk.StringVar(value="-")
        self.banner_text = tk.StringVar(value="Ready. Connect the board and query stats.")
        self.hot_rule_text = tk.StringVar(value="Hot Rule (board): none yet")
        self.rule_refresh_job: str | None = None
        self.stats_vars = {
            "total": tk.StringVar(value="0"),
            "acl": tk.StringVar(value="0"),
            "aes": tk.StringVar(value="0"),
            "sm4": tk.StringVar(value="0"),
            "err": tk.StringVar(value="0"),
        }
        self.stat_value_labels: dict[str, tk.Label] = {}
        self.acl_rule_hit_vars = {key: tk.StringVar(value="0") for key in DEFAULT_ACL_RULES}
        self.acl_rule_hit_labels: dict[str, tk.Label] = {}

        self._build_ui()
        self._refresh_ports()
        self.after(100, self._poll_worker)
        self.protocol("WM_DELETE_WINDOW", self._on_close)

    def _build_ui(self) -> None:
        self.columnconfigure(0, weight=1)
        self.rowconfigure(3, weight=1)

        top = ttk.Frame(self, padding=12)
        top.grid(row=0, column=0, sticky="ew")
        top.columnconfigure(6, weight=1)

        ttk.Label(top, text="Serial Port").grid(row=0, column=0, sticky="w")
        self.port_combo = ttk.Combobox(top, textvariable=self.current_port, width=14, state="readonly")
        self.port_combo.grid(row=1, column=0, padx=(0, 8), sticky="w")

        ttk.Label(top, text="Baud").grid(row=0, column=1, sticky="w")
        ttk.Entry(top, textvariable=self.current_baud, width=10).grid(row=1, column=1, padx=(0, 8), sticky="w")

        ttk.Button(top, text="Refresh Ports", command=self._refresh_ports).grid(row=1, column=2, padx=(0, 8))
        ttk.Button(top, text="Connect", command=self._connect).grid(row=1, column=3, padx=(0, 8))
        ttk.Button(top, text="Disconnect", command=self._disconnect).grid(row=1, column=4, padx=(0, 16))
        ttk.Label(top, text="Link").grid(row=0, column=5, sticky="w")
        ttk.Label(top, textvariable=self.connection_state).grid(row=1, column=5, sticky="w")
        self.banner = tk.Label(
            top,
            textvariable=self.banner_text,
            bg="#e2e8f0",
            fg="#0f172a",
            font=("Segoe UI", 10, "bold"),
            anchor="w",
            padx=10,
            pady=8,
        )
        self.banner.grid(row=2, column=0, columnspan=7, sticky="ew", pady=(12, 0))

        actions = ttk.LabelFrame(self, text="Quick Actions", padding=12)
        actions.grid(row=1, column=0, padx=12, sticky="ew")
        for idx in range(5):
            actions.columnconfigure(idx, weight=1)

        ttk.Button(actions, text="Query Stats", command=lambda: self._submit_case(case_query_stats())).grid(row=0, column=0, sticky="ew", padx=4, pady=4)
        ttk.Button(actions, text="Query Rule Hits", command=lambda: self._submit_case(case_query_rule_stats())).grid(row=0, column=1, sticky="ew", padx=4, pady=4)
        ttk.Button(actions, text="SM4 16B", command=lambda: self._submit_case(case_sm4_known_vector())).grid(row=0, column=2, sticky="ew", padx=4, pady=4)
        ttk.Button(actions, text="AES 16B", command=lambda: self._submit_case(case_aes_known_vector())).grid(row=0, column=3, sticky="ew", padx=4, pady=4)
        ttk.Button(actions, text="Invalid Selector", command=lambda: self._submit_case(case_invalid_selector())).grid(row=0, column=4, sticky="ew", padx=4, pady=4)

        ttk.Button(actions, text="SM4 32B", command=lambda: self._submit_case(case_sm4_two_block_vector())).grid(row=1, column=0, sticky="ew", padx=4, pady=4)
        ttk.Button(actions, text="AES 32B", command=lambda: self._submit_case(case_aes_two_block_vector())).grid(row=1, column=1, sticky="ew", padx=4, pady=4)
        ttk.Button(actions, text="SM4 64B", command=lambda: self._submit_case(case_sm4_four_block_vector())).grid(row=1, column=2, sticky="ew", padx=4, pady=4)
        ttk.Button(actions, text="AES 64B", command=lambda: self._submit_case(case_aes_four_block_vector())).grid(row=1, column=3, sticky="ew", padx=4, pady=4)
        ttk.Button(actions, text="SM4 128B", command=lambda: self._submit_case(case_sm4_eight_block_vector())).grid(row=2, column=0, sticky="ew", padx=4, pady=4)
        ttk.Button(actions, text="AES 128B", command=lambda: self._submit_case(case_aes_eight_block_vector())).grid(row=2, column=1, sticky="ew", padx=4, pady=4)

        acl_frame = ttk.Frame(actions)
        acl_frame.grid(row=3, column=0, columnspan=5, sticky="ew", padx=4, pady=4)
        acl_frame.columnconfigure(1, weight=1)
        ttk.Label(acl_frame, text="ACL Probe").grid(row=0, column=0, padx=(0, 8))
        ttk.Entry(acl_frame, textvariable=self.acl_text, width=14).grid(row=0, column=1, padx=(0, 8), sticky="ew")
        ttk.Button(acl_frame, text="Send Block Test", command=self._send_acl_probe).grid(row=0, column=2)

        acl_rules = ttk.LabelFrame(actions, text="Compiled ACL Rule Table (BRAM + Hardware Counters)", padding=10)
        acl_rules.grid(row=4, column=0, columnspan=5, sticky="ew", padx=4, pady=(8, 0))
        ttk.Label(
            acl_rules,
            text="Current bitstream default blocked first-byte keys. Use 'Query Rule Hits' to refresh board counters:",
        ).grid(row=0, column=0, columnspan=len(DEFAULT_ACL_RULES), sticky="w", pady=(0, 6))
        ttk.Label(
            acl_rules,
            textvariable=self.hot_rule_text,
            foreground="#991b1b",
            font=("Segoe UI", 10, "bold"),
        ).grid(row=0, column=len(DEFAULT_ACL_RULES), sticky="e", padx=(12, 0))
        for idx, key in enumerate(DEFAULT_ACL_RULES):
            cell = ttk.Frame(acl_rules, padding=(0, 0, 6, 0))
            cell.grid(row=1, column=idx, padx=4, sticky="w")
            badge = tk.Label(
                cell,
                text=key,
                bg="#fee2e2",
                fg="#991b1b",
                font=("Segoe UI", 10, "bold"),
                relief="ridge",
                bd=1,
                padx=12,
                pady=4,
            )
            badge.grid(row=0, column=0, sticky="w")
            hit_label = tk.Label(
                cell,
                textvariable=self.acl_rule_hit_vars[key],
                bg="#e2e8f0",
                fg="#0f172a",
                font=("Segoe UI", 10, "bold"),
                relief="ridge",
                bd=1,
                padx=10,
                pady=4,
            )
            hit_label.grid(row=0, column=1, padx=(4, 0), sticky="w")
            self.acl_rule_hit_labels[key] = hit_label

        metrics = ttk.LabelFrame(self, text="Live Metrics", padding=12)
        metrics.grid(row=2, column=0, padx=12, pady=(8, 0), sticky="ew")
        for idx in range(8):
            metrics.columnconfigure(idx, weight=1)

        ttk.Label(metrics, text="Throughput").grid(row=0, column=0, sticky="w")
        ttk.Label(metrics, textvariable=self.throughput_label).grid(row=1, column=0, sticky="w")
        ttk.Label(metrics, text="Last Latency").grid(row=0, column=1, sticky="w")
        ttk.Label(metrics, textvariable=self.last_latency_label).grid(row=1, column=1, sticky="w")

        stat_names = [("total", "Total"), ("acl", "ACL"), ("aes", "AES"), ("sm4", "SM4"), ("err", "Error")]
        for offset, (key, label) in enumerate(stat_names, start=2):
            ttk.Label(metrics, text=label).grid(row=0, column=offset, sticky="w")
            stat_label = tk.Label(
                metrics,
                textvariable=self.stats_vars[key],
                bg="#e2e8f0",
                fg="#0f172a",
                font=("Segoe UI", 12, "bold"),
                width=6,
                relief="ridge",
                bd=1,
                padx=8,
                pady=4,
            )
            stat_label.grid(row=1, column=offset, sticky="w")
            self.stat_value_labels[key] = stat_label

        chart_frame = ttk.LabelFrame(self, text="Throughput Waveform", padding=12)
        chart_frame.grid(row=3, column=0, padx=12, pady=8, sticky="nsew")
        chart_frame.rowconfigure(0, weight=1)
        chart_frame.columnconfigure(0, weight=1)
        self.chart = tk.Canvas(chart_frame, width=900, height=220, bg="#0f172a", highlightthickness=0)
        self.chart.grid(row=0, column=0, sticky="nsew")

        bottom = ttk.Frame(self, padding=(12, 0, 12, 12))
        bottom.grid(row=4, column=0, sticky="nsew")
        bottom.columnconfigure(0, weight=2)
        bottom.columnconfigure(1, weight=1)
        bottom.rowconfigure(0, weight=1)

        log_frame = ttk.LabelFrame(bottom, text="Gateway Event Log", padding=12)
        log_frame.grid(row=0, column=0, sticky="nsew", padx=(0, 8))
        log_frame.rowconfigure(0, weight=1)
        log_frame.columnconfigure(0, weight=1)
        self.log_box = scrolledtext.ScrolledText(log_frame, wrap="word", font=("Consolas", 10))
        self.log_box.grid(row=0, column=0, sticky="nsew")
        self.log_box.tag_config("info", foreground="#0f172a")
        self.log_box.tag_config("pass", foreground="#166534")
        self.log_box.tag_config("warn", foreground="#9a3412")
        self.log_box.tag_config("block", foreground="#b91c1c", font=("Consolas", 10, "bold"))
        self.log_box.tag_config("error", foreground="#991b1b", font=("Consolas", 10, "bold"))

        file_frame = ttk.LabelFrame(bottom, text="File Encryption Demo", padding=12)
        file_frame.grid(row=0, column=1, sticky="nsew")
        file_frame.columnconfigure(1, weight=1)
        ttk.Label(file_frame, text="Algorithm").grid(row=0, column=0, sticky="w")
        ttk.Combobox(file_frame, textvariable=self.file_algo, values=["SM4", "AES"], state="readonly", width=8).grid(row=0, column=1, sticky="w")
        ttk.Label(
            file_frame,
            text="Any non-empty file is accepted.\nFiles larger than 128B are sliced into 128B ping-pong chunks.\nThe final short chunk is padded to 128B with PKCS#7 automatically.",
            justify="left",
            wraplength=280,
        ).grid(row=1, column=0, columnspan=2, sticky="w", pady=(12, 12))
        ttk.Button(file_frame, text="Encrypt File...", command=self._encrypt_file).grid(row=2, column=0, columnspan=2, sticky="ew")

        self._draw_chart()

    def _timestamp(self) -> str:
        return datetime.now().strftime("%H:%M:%S")

    def _append_log(self, message: str, tag: str = "info") -> None:
        self.log_box.insert("end", f"[{self._timestamp()}] {message}\n", tag)
        self.log_box.see("end")

    def _set_banner(self, text: str, level: str = "info") -> None:
        colors = {
            "info": ("#e2e8f0", "#0f172a"),
            "pass": ("#dcfce7", "#166534"),
            "warn": ("#ffedd5", "#9a3412"),
            "block": ("#fee2e2", "#b91c1c"),
            "error": ("#fecaca", "#991b1b"),
        }
        bg, fg = colors.get(level, colors["info"])
        self.banner.configure(bg=bg, fg=fg)
        self.banner_text.set(text)

    def _refresh_ports(self) -> None:
        ports = self.worker.list_ports()
        self.port_combo["values"] = ports
        if ports and self.current_port.get() not in ports:
            self.current_port.set(ports[0])
        self._append_log(f"Detected serial ports: {', '.join(ports) if ports else 'none'}")

    def _connect(self) -> None:
        port = self.current_port.get().strip()
        if not port:
            messagebox.showerror("Port Required", "Select a serial port before connecting.")
            return
        self.worker.connect(port, int(self.current_baud.get()))
        self._append_log(f"Connecting to {port} @ {self.current_baud.get()} baud...")
        self._set_banner(f"Connecting to {port}...", "warn")

    def _disconnect(self) -> None:
        self.worker.disconnect()

    def _submit_case(self, case) -> None:
        self.worker.submit_case(case)
        self._append_log(f"Queued: {case.name}")
        self._set_banner(f"Queued action: {case.name}", "info")

    def _send_acl_probe(self) -> None:
        text = self.acl_text.get().strip()
        if not text:
            messagebox.showerror("ACL Probe", "Enter an ASCII string for ACL testing.")
            return
        self._submit_case(case_block_ascii(text))

    def _encrypt_file(self) -> None:
        path = filedialog.askopenfilename(title="Select a plaintext file to encrypt")
        if not path:
            return
        self.worker.encrypt_file(path, self.file_algo.get())
        self._append_log(f"Queued file encryption: {Path(path).name} with {self.file_algo.get()}")

    def _schedule_rule_stats_refresh(self) -> None:
        if self.rule_refresh_job is not None:
            self.after_cancel(self.rule_refresh_job)
        self.rule_refresh_job = self.after(180, self._run_rule_stats_refresh)

    def _run_rule_stats_refresh(self) -> None:
        self.rule_refresh_job = None
        self.worker.submit_case(case_query_rule_stats())
        self._append_log("Queued: Query Rule Hits (auto-refresh)")

    def _draw_chart(self) -> None:
        self.chart.delete("all")
        width = int(self.chart.winfo_width() or 900)
        height = int(self.chart.winfo_height() or 220)
        margin = 18
        self.chart.create_rectangle(margin, margin, width - margin, height - margin, outline="#334155")
        for step in range(1, 4):
            y = margin + step * (height - 2 * margin) / 4
            self.chart.create_line(margin, y, width - margin, y, fill="#1e293b")
        values = list(self.mbps_history)
        vmax = max(max(values, default=0.0), 1.0)
        points = []
        for idx, value in enumerate(values):
            x = margin + idx * (width - 2 * margin) / max(len(values) - 1, 1)
            normalized = value / vmax
            y = height - margin - normalized * (height - 2 * margin)
            points.extend([x, y])
        if len(points) >= 4:
            self.chart.create_line(*points, fill="#38bdf8", width=2, smooth=True)
        self.chart.create_text(margin + 8, margin + 8, text=f"max {vmax:.3f} Mbps", fill="#94a3b8", anchor="nw")

    def _update_throughput(self, mbps: float, latency_s: float) -> None:
        self.mbps_history.append(mbps)
        self.throughput_label.set(f"{mbps:.3f} Mbps")
        self.last_latency_label.set(f"{latency_s * 1000.0:.1f} ms")
        self._draw_chart()

    def _apply_stats(self, stats: StatsCounters) -> None:
        self.stats_vars["total"].set(str(stats.total))
        self.stats_vars["acl"].set(str(stats.acl))
        self.stats_vars["aes"].set(str(stats.aes))
        self.stats_vars["sm4"].set(str(stats.sm4))
        self.stats_vars["err"].set(str(stats.err))
        palette = {
            "total": ("#dbeafe", "#1d4ed8"),
            "acl": ("#fee2e2" if stats.acl else "#e2e8f0", "#b91c1c" if stats.acl else "#0f172a"),
            "aes": ("#ede9fe" if stats.aes else "#e2e8f0", "#6d28d9" if stats.aes else "#0f172a"),
            "sm4": ("#dcfce7" if stats.sm4 else "#e2e8f0", "#166534" if stats.sm4 else "#0f172a"),
            "err": ("#fecaca" if stats.err else "#e2e8f0", "#991b1b" if stats.err else "#0f172a"),
        }
        for key, label in self.stat_value_labels.items():
            bg, fg = palette[key]
            label.configure(bg=bg, fg=fg)

    def _apply_rule_stats(self, rule_stats: AclRuleCounters) -> None:
        counts = rule_stats.as_dict()
        for rule, label in self.acl_rule_hit_labels.items():
            hits = counts[rule]
            self.acl_rule_hit_vars[rule].set(str(hits))
            if hits > 0:
                label.configure(bg="#fee2e2", fg="#991b1b")
            else:
                label.configure(bg="#e2e8f0", fg="#0f172a")
        hot_rule, hot_hits = rule_stats.hot_rule()
        if hot_rule is not None:
            self.hot_rule_text.set(f"Hot Rule (board): {hot_rule} ({hot_hits} hits)")
        else:
            self.hot_rule_text.set("Hot Rule (board): none yet")

    def _handle_event(self, event: WorkerEvent) -> None:
        kind = event.kind
        payload = event.payload
        if kind == "connected":
            self.connection_state.set(f"Connected: {payload['port']}")
            self._append_log(f"Connected to {payload['port']} @ {payload['baud']} baud", "pass")
            self._set_banner(f"Connected to {payload['port']} @ {payload['baud']} baud", "pass")
        elif kind == "disconnected":
            self.connection_state.set("Disconnected")
            self._append_log("Serial link disconnected", "warn")
            self._set_banner("Disconnected. Reconnect to continue testing.", "warn")
        elif kind == "error":
            self._append_log(f"ERROR: {payload['message']}", "error")
            self._set_banner(f"Error: {payload['message']}", "error")
            messagebox.showerror("Gateway Error", payload["message"])
        elif kind == "result":
            tx = payload["tx"]
            rx = payload["rx"]
            expected = payload["expected"]
            passed = payload["passed"]
            description = payload["description"]
            self._update_throughput(float(payload["throughput_mbps"]), float(payload["duration_s"]))
            if payload["stats"] is not None:
                self._apply_stats(payload["stats"])
            if payload["rule_stats"] is not None:
                self._apply_rule_stats(payload["rule_stats"])
            if rx == b"D\n":
                self._append_log(f"ACL BLOCK: {description} -> {format_hex(rx)}", "block")
                rule = extract_first_payload_key(tx)
                if rule:
                    self._set_banner(f"Hardware firewall blocked the frame (ACL hit: {rule}).", "block")
                else:
                    self._set_banner("Hardware firewall blocked the frame (ACL hit).", "block")
                self._schedule_rule_stats_refresh()
            elif rx == b"E\n":
                self._append_log(f"PROTOCOL ERROR: {description} -> {format_hex(rx)}", "error")
                self._set_banner("Protocol error returned by the board.", "error")
            elif payload["rule_stats"] is not None:
                counters = payload["rule_stats"].as_dict()
                self._append_log(
                    "ACL RULE STATS: "
                    + " ".join(f"{key}={counters[key]}" for key in DEFAULT_ACL_RULES),
                    "pass" if passed else "error",
                )
                hot_rule, hot_hits = payload["rule_stats"].hot_rule()
                if hot_rule is None:
                    self._set_banner("Board-side ACL rule counters refreshed (no hits yet).", "pass")
                else:
                    self._set_banner(
                        f"Board-side ACL rule counters refreshed. Hot rule: {hot_rule} ({hot_hits} hits).",
                        "pass",
                    )
            else:
                self._append_log(
                    f"{payload['name']}: TX={format_hex(tx)} RX={format_hex(rx)} "
                    f"{'PASS' if passed else 'FAIL'}",
                    "pass" if passed else "error",
                )
                self._set_banner(
                    f"{payload['name']} {'passed' if passed else 'failed'} at "
                    f"{float(payload['throughput_mbps']):.3f} Mbps",
                    "pass" if passed else "error",
                )
            if expected is not None and not passed:
                self._append_log(f"Expected {format_hex(expected)}", "error")
        elif kind == "file_progress":
            elapsed_s = max(float(payload.get("elapsed_s", 0.001)), 1e-9)
            self._update_throughput(float(payload["throughput_mbps"]), elapsed_s)
            processed = int(payload["processed"])
            total = int(payload["total"])
            original_total = int(payload.get("original_total", total))
            pad_bytes = int(payload.get("pad_bytes", 0))
            self._append_log(
                f"FILE {payload['algo']}: chunk {payload.get('chunk_index', '?')}/{payload.get('chunk_count', '?')} "
                f"{processed}/{total} bytes over UART (orig {original_total}, pad {pad_bytes}, chunk {payload['chunk']})",
                "info",
            )
            self._set_banner(
                f"Encrypting via {payload['algo']}: {processed}/{total} transport bytes "
                f"(orig {original_total}, pad {pad_bytes}) @ {float(payload['throughput_mbps']):.3f} Mbps",
                "info",
            )
        elif kind == "file_done":
            self._append_log(
                f"FILE DONE {payload['algo']}: {payload['total_bytes']} transport bytes "
                f"(orig {payload.get('original_bytes', payload['total_bytes'])}, pad {payload.get('pad_bytes', 0)}, chunks {payload.get('chunk_count', '?')}) "
                f"-> {payload['output_path']} "
                f"@ {payload['throughput_mbps']:.3f} Mbps",
                "pass",
            )
            self._set_banner(
                f"File encryption finished: {Path(payload['output_path']).name} "
                f"(pad {payload.get('pad_bytes', 0)}, chunks {payload.get('chunk_count', '?')})",
                "pass",
            )
            messagebox.showinfo(
                "File Encryption Complete",
                "Output written to:\n"
                f"{payload['output_path']}\n\n"
                f"Original bytes: {payload.get('original_bytes', payload['total_bytes'])}\n"
                f"Transport bytes: {payload['total_bytes']}\n"
                f"PKCS#7 pad bytes: {payload.get('pad_bytes', 0)}\n"
                f"Chunks: {payload.get('chunk_count', '?')}",
            )

    def _poll_worker(self) -> None:
        for event in self.worker.poll_events():
            self._handle_event(event)
        self.after(100, self._poll_worker)

    def _on_close(self) -> None:
        if self.rule_refresh_job is not None:
            self.after_cancel(self.rule_refresh_job)
            self.rule_refresh_job = None
        self.worker.stop()
        self.destroy()


def main() -> int:
    app = CryptoGatewayApp()
    app.mainloop()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
