from __future__ import annotations

from collections import deque
from datetime import datetime
from pathlib import Path
import os
import time
import tkinter as tk
from tkinter import filedialog, messagebox, scrolledtext, ttk

from crypto_gateway_protocol import (
    AclV2HitCounters,
    AclV2KeyMap,
    AclV2WriteAck,
    DEFAULT_ACL_RULE_BYTES,
    StatsCounters,
    case_acl_v2_write,
    case_acl_v2_keymap,
    case_acl_v2_hit_counters,
    case_aes_eight_block_vector,
    case_aes_four_block_vector,
    case_aes_known_vector,
    case_aes_two_block_vector,
    case_block_ascii,
    case_invalid_selector,
    case_force_run_onchip_bench,
    case_query_bench_result,
    case_query_pmu,
    case_query_stats,
    case_run_onchip_bench,
    case_clear_pmu,
    case_sm4_eight_block_vector,
    case_sm4_four_block_vector,
    case_sm4_known_vector,
    case_sm4_two_block_vector,
    display_rule_byte,
    format_hex,
    parse_rule_byte_input,
)
from crypto_gateway_worker import GatewayWorker, WorkerEvent


class CryptoGatewayApp(tk.Tk):
    def _init_tk_root(self) -> None:
        try:
            super().__init__()
        except tk.TclError as exc:
            if "zh_cn.msg" not in str(exc).lower():
                raise
            env_backup = {key: os.environ.get(key) for key in ("LANG", "LC_ALL", "LC_MESSAGES")}
            try:
                os.environ["LANG"] = "C"
                os.environ["LC_ALL"] = "C"
                os.environ["LC_MESSAGES"] = "C"
                super().__init__()
            finally:
                for key, value in env_backup.items():
                    if value is None:
                        os.environ.pop(key, None)
                    else:
                        os.environ[key] = value

    def __init__(self) -> None:
        self._init_tk_root()
        self.title("RX50T Crypto Gateway Console")
        self.geometry("1420x980")
        self.minsize(1260, 860)
        self.design_mode_label = tk.StringVar(value="Modular Grid")
        self._setup_theme()

        self.worker = GatewayWorker()
        self.worker.start()

        self.mbps_history: deque[float] = deque([0.0] * 60, maxlen=60)
        self.current_port = tk.StringVar(value="COM12")
        self.current_baud = tk.IntVar(value=2_000_000)
        self.acl_text = tk.StringVar(value="XYZ")
        self.deploy_rule_slot = tk.IntVar(value=0)
        self.deploy_rule_key = tk.StringVar(value="Q")
        self.file_algo = tk.StringVar(value="SM4")
        self.bench_algo = tk.StringVar(value="SM4")
        self.connection_state = tk.StringVar(value="Disconnected")
        self.throughput_label = tk.StringVar(value="0.000 Mbps")
        self.last_latency_label = tk.StringVar(value="-")
        self.banner_text = tk.StringVar(value="Ready. Connect the board and query stats.")
        self.hot_rule_text = tk.StringVar(value="Hot Rule (board): none yet")
        self.pmu_vars = {
            "hw_util": tk.StringVar(value="0.0%"),
            "uart_stall": tk.StringVar(value="0.0%"),
            "credit_block": tk.StringVar(value="0.0%"),
            "acl_events": tk.StringVar(value="0"),
            "stream_bytes_in": tk.StringVar(value="0"),
            "stream_bytes_out": tk.StringVar(value="0"),
            "stream_chunks": tk.StringVar(value="0"),
            "clock_status": tk.StringVar(value="ACTIVE"),
        }
        self.bench_vars = {
            "status": tk.StringVar(value="-"),
            "mbps": tk.StringVar(value="-"),
            "cycles": tk.StringVar(value="-"),
            "crc32": tk.StringVar(value="-"),
        }
        self.rule_refresh_job: str | None = None
        self.file_name_text = tk.StringVar(value="No file queued")
        self.file_status_vars = {
            "logical": tk.StringVar(value="-"),
            "padding": tk.StringVar(value="-"),
            "transport": tk.StringVar(value="-"),
            "chunks": tk.StringVar(value="-"),
            "progress": tk.StringVar(value="0 / 0 ACKed"),
            "pulse": tk.StringVar(value="IDLE"),
        }
        self.evidence_live_vars = {
            "wire_mbps": tk.StringVar(value="- Mbps"),
            "chip_mbps": tk.StringVar(value="- Mbps"),
            "gap_ratio": tk.StringVar(value="-"),
            "hw_util": tk.StringVar(value="-"),
            "uart_stall": tk.StringVar(value="-"),
            "credit_block": tk.StringVar(value="-"),
            "stream_in": tk.StringVar(value="-"),
            "stream_out": tk.StringVar(value="-"),
            "stream_chunks": tk.StringVar(value="-"),
            "clock_status": tk.StringVar(value="ACTIVE"),
        }
        self.evidence_frozen_vars = {
            "wire_mbps": tk.StringVar(value="- Mbps"),
            "chip_mbps": tk.StringVar(value="- Mbps"),
            "gap_ratio": tk.StringVar(value="-"),
            "hw_util": tk.StringVar(value="-"),
            "uart_stall": tk.StringVar(value="-"),
            "credit_block": tk.StringVar(value="-"),
            "stream_in": tk.StringVar(value="-"),
            "stream_out": tk.StringVar(value="-"),
            "clock_status": tk.StringVar(value="-"),
            "stream_chunks": tk.StringVar(value="-"),
        }
        self.evidence_frozen_active = False
        self.file_done_chunks = 0
        self.file_total_chunks = 0
        self.file_pulse_job: str | None = None
        self.throughput_sample_job: str | None = None
        self.pending_transport_bytes = 0
        self.last_sample_at = time.perf_counter()
        self.stats_vars = {
            "total": tk.StringVar(value="0"),
            "acl": tk.StringVar(value="0"),
            "aes": tk.StringVar(value="0"),
            "sm4": tk.StringVar(value="0"),
            "err": tk.StringVar(value="0"),
        }
        self.stat_numeric_cache = {key: 0 for key in self.stats_vars}
        self.stat_anim_jobs: dict[str, str] = {}
        self.stat_value_labels: dict[str, tk.Label] = {}
        self.rule_slot_keys = list(DEFAULT_ACL_RULE_BYTES)
        self.rule_slot_labels = [display_rule_byte(value) for value in self.rule_slot_keys]
        self.acl_rule_hit_vars = {idx: tk.StringVar(value="0") for idx in range(8)}
        self.acl_rule_hit_labels: dict[int, tk.Label] = {}
        self.acl_rule_bar_canvases: dict[int, tk.Canvas] = {}
        self.acl_rule_bar_fills: dict[int, int] = {}
        self.acl_rule_cells: dict[int, tk.Frame] = {}
        self.acl_rule_title_labels: dict[int, tk.Label] = {}
        self.acl_rule_flash_jobs: dict[int, list[str]] = {}
        self.acl_rule_last_counts = {idx: 0 for idx in range(8)}

        self._build_ui()
        self._refresh_ports()
        self.after(80, self._poll_worker)
        self.after(80, self._sample_throughput)
        self.protocol("WM_DELETE_WINDOW", self._on_close)

    def _setup_theme(self) -> None:
        self.colors = {
            "app_bg": "#202226",
            "shell_bg": "#2a2c31",
            "panel_bg": "#0f1218",
            "panel_alt": "#141820",
            "panel_soft": "#1b1f28",
            "border": "#6c7280",
            "muted_border": "#343a46",
            "text": "#f8fafc",
            "muted": "#c5ccd8",
            "subtle": "#94a3b8",
            "accent": "#4f8cff",
            "accent_soft": "#16213d",
            "accent2": "#34d399",
            "good": "#22c55e",
            "warn": "#f59e0b",
            "danger": "#ef4444",
            "danger_soft": "#3a171c",
            "purple": "#a78bfa",
            "teal": "#34d399",
            "cyan": "#7dd3fc",
            "track": "#08111f",
        }
        self.configure(bg=self.colors["app_bg"])
        self.style = ttk.Style(self)
        self.style.theme_use("clam")
        self.style.configure(
            "Dark.TCombobox",
            fieldbackground=self.colors["panel_bg"],
            background=self.colors["panel_bg"],
            foreground=self.colors["text"],
            arrowcolor=self.colors["text"],
            bordercolor=self.colors["border"],
            lightcolor=self.colors["border"],
            darkcolor=self.colors["border"],
            insertcolor=self.colors["text"],
            padding=6,
        )
        self.style.map(
            "Dark.TCombobox",
            fieldbackground=[("readonly", self.colors["panel_bg"])],
            foreground=[("readonly", self.colors["text"])],
            selectforeground=[("readonly", self.colors["text"])],
            selectbackground=[("readonly", self.colors["panel_bg"])],
            background=[("readonly", self.colors["panel_bg"])],
        )
        self.option_add("*TCombobox*Listbox.background", self.colors["panel_bg"])
        self.option_add("*TCombobox*Listbox.foreground", self.colors["text"])
        self.option_add("*TCombobox*Listbox.selectBackground", self.colors["accent"])
        self.option_add("*TCombobox*Listbox.selectForeground", self.colors["text"])
        self.option_add("*Font", "{Segoe UI} 10")

    def _section_heading(self, parent: tk.Widget, title: str) -> tk.Frame:
        heading = tk.Frame(parent, bg=parent.cget("bg"))
        heading.pack(fill="x", pady=(0, 12))
        tk.Frame(heading, bg=self.colors["accent"], width=5, height=26).pack(side="left", padx=(0, 12))
        tk.Label(
            heading,
            text=title,
            bg=parent.cget("bg"),
            fg=self.colors["text"],
            font=("Segoe UI", 16, "bold"),
            anchor="w",
        ).pack(side="left")
        return heading

    def _make_panel(self, parent: tk.Widget) -> tk.Frame:
        return tk.Frame(
            parent,
            bg=self.colors["panel_bg"],
            highlightbackground=self.colors["border"],
            highlightthickness=1,
            bd=0,
            padx=16,
            pady=16,
        )

    def _make_header_metric(self, parent: tk.Widget, title: str, value_var: tk.Variable) -> None:
        box = tk.Frame(parent, bg=self.colors["shell_bg"])
        box.pack(side="left", padx=(0, 26))
        tk.Label(
            box,
            text=title,
            bg=self.colors["shell_bg"],
            fg="#d7b98a",
            font=("Segoe UI", 10, "bold"),
            anchor="w",
        ).pack(anchor="w")
        tk.Label(
            box,
            textvariable=value_var,
            bg=self.colors["shell_bg"],
            fg=self.colors["text"],
            font=("Consolas", 12, "bold"),
            anchor="w",
        ).pack(anchor="w", pady=(4, 0))

    def _make_action_button(self, parent: tk.Widget, text: str, command) -> tk.Button:
        return tk.Button(
            parent,
            text=text,
            command=command,
            bg=self.colors["panel_alt"],
            fg=self.colors["text"],
            activebackground=self.colors["accent"],
            activeforeground=self.colors["text"],
            relief="flat",
            bd=0,
            padx=10,
            pady=5,
            font=("Segoe UI", 8, "bold"),
            cursor="hand2",
        )

    def _make_value_card(self, parent: tk.Widget, title: str, text_var: tk.Variable) -> tuple[tk.Frame, tk.Label]:
        card = tk.Frame(
            parent,
            bg=self.colors["panel_alt"],
            highlightbackground=self.colors["muted_border"],
            highlightthickness=1,
            padx=8,
            pady=8,
        )
        tk.Label(
            card,
            text=title.upper(),
            bg=self.colors["panel_alt"],
            fg=self.colors["subtle"],
            font=("Segoe UI", 9, "bold"),
            anchor="w",
        ).pack(anchor="w")
        label = tk.Label(
            card,
            textvariable=text_var,
            bg=self.colors["panel_alt"],
            fg=self.colors["text"],
            font=("Consolas", 12, "bold"),
            anchor="w",
        )
        label.pack(anchor="w", pady=(6, 0))
        return card, label

    def _make_metric_tile(
        self,
        parent: tk.Widget,
        title: str,
        text_var: tk.Variable,
        *,
        title_fg: str,
        value_fg: str | None = None,
    ) -> tuple[tk.Frame, tk.Label]:
        tile = tk.Frame(
            parent,
            bg="#0f172a",
            highlightbackground=self.colors["muted_border"],
            highlightthickness=1,
            padx=10,
            pady=10,
        )
        tk.Label(
            tile,
            text=title.upper(),
            bg="#0f172a",
            fg=title_fg,
            font=("Segoe UI", 10, "bold"),
            anchor="w",
        ).pack(anchor="w")
        value_label = tk.Label(
            tile,
            textvariable=text_var,
            bg="#0f172a",
            fg=value_fg or self.colors["text"],
            font=("Consolas", 18, "bold"),
            anchor="w",
        )
        value_label.pack(anchor="w", pady=(10, 0))
        return tile, value_label

    def _set_link_visual(self, dot_bg: str, text: str, text_fg: str | None = None) -> None:
        if hasattr(self, "link_dot"):
            self.link_dot.configure(bg=dot_bg)
        if hasattr(self, "link_badge"):
            self.link_badge.configure(text=text, fg=text_fg or self.colors["text"])

    def _build_ui(self) -> None:
        self.columnconfigure(0, weight=1)
        self.rowconfigure(0, weight=1)

        shell = tk.Frame(self, bg=self.colors["shell_bg"], padx=22, pady=18)
        shell.grid(row=0, column=0, sticky="nsew")
        shell.columnconfigure(0, weight=1)
        shell.rowconfigure(1, weight=6)
        shell.rowconfigure(2, weight=4, minsize=180)
        self.shell = shell

        header = tk.Frame(shell, bg=self.colors["shell_bg"])
        header.grid(row=0, column=0, sticky="ew")
        header.columnconfigure(0, weight=1)
        tk.Label(
            header,
            text="RX50T Console Wireframe Explorer",
            bg=self.colors["shell_bg"],
            fg=self.colors["text"],
            font=("Segoe UI", 18, "bold"),
            anchor="w",
        ).grid(row=0, column=0, sticky="w", pady=(0, 12))
        metrics_strip = tk.Frame(header, bg=self.colors["shell_bg"])
        metrics_strip.grid(row=0, column=1, sticky="e", pady=(0, 12))
        self._make_header_metric(metrics_strip, "STATUS", self.connection_state)
        self._make_header_metric(metrics_strip, "LATENCY", self.last_latency_label)
        self._make_header_metric(metrics_strip, "PACKETS", self.stats_vars["total"])
        self._make_header_metric(metrics_strip, "DESIGN MODE", self.design_mode_label)

        dashboard = tk.Frame(shell, bg=self.colors["shell_bg"])
        dashboard.grid(row=1, column=0, sticky="nsew", pady=(0, 16))
        dashboard.columnconfigure(0, weight=7)
        dashboard.columnconfigure(1, weight=3)
        dashboard.rowconfigure(0, weight=1)

        self.main_zone = tk.Frame(dashboard, bg=self.colors["shell_bg"])
        self.main_zone.grid(row=0, column=0, sticky="nsew", padx=(0, 12))
        self.main_zone.columnconfigure(0, weight=1)
        self.main_zone.rowconfigure(0, weight=6, minsize=380)
        self.main_zone.rowconfigure(1, weight=3)

        self.aux_zone = tk.Frame(dashboard, bg=self.colors["shell_bg"])
        self.aux_zone.grid(row=0, column=1, sticky="nsew")
        self.aux_zone.columnconfigure(0, weight=1)
        self.aux_zone.rowconfigure(0, weight=0)
        self.aux_zone.rowconfigure(1, weight=1, minsize=220)

        self.file_demo_zone = self._make_panel(self.main_zone)
        self.file_demo_zone.grid(row=0, column=0, sticky="nsew", pady=(0, 12))
        self._section_heading(self.file_demo_zone, "FILE DEMO STATUS")

        file_body = tk.Frame(self.file_demo_zone, bg=self.colors["panel_bg"])
        file_body.pack(fill="both", expand=True)
        file_body.columnconfigure(0, weight=1)

        file_top = tk.Frame(file_body, bg=self.colors["panel_bg"])
        file_top.grid(row=0, column=0, sticky="ew")
        file_top.columnconfigure(0, weight=1)
        tk.Label(
            file_top,
            textvariable=self.file_name_text,
            bg="#020617",
            fg=self.colors["text"],
            font=("Consolas", 10, "bold"),
            anchor="w",
            padx=12,
            pady=8,
            highlightbackground=self.colors["muted_border"],
            highlightthickness=1,
        ).grid(row=0, column=0, sticky="ew", padx=(0, 12))
        ttk.Combobox(
            file_top,
            textvariable=self.file_algo,
            values=["SM4", "AES"],
            state="readonly",
            width=8,
            style="Dark.TCombobox",
        ).grid(row=0, column=1, padx=(0, 10), sticky="e")
        self._make_action_button(file_top, "Encrypt File...", self._encrypt_file).grid(row=0, column=2, sticky="e")
        self._build_file_status_panel(file_body)

        self.wave_zone = self._make_panel(self.main_zone)
        self.wave_zone.grid(row=1, column=0, sticky="nsew")
        self._section_heading(self.wave_zone, "THROUGHPUT HEARTBEAT")
        wave_header = tk.Frame(self.wave_zone, bg=self.colors["panel_bg"])
        wave_header.pack(fill="x", pady=(0, 12))
        wave_header.columnconfigure(0, weight=1)
        tk.Label(
            wave_header,
            textvariable=self.throughput_label,
            bg=self.colors["panel_bg"],
            fg=self.colors["cyan"],
            font=("Consolas", 24, "bold"),
            anchor="w",
        ).grid(row=0, column=0, sticky="w")
        tk.Label(
            wave_header,
            textvariable=self.last_latency_label,
            bg=self.colors["panel_bg"],
            fg=self.colors["subtle"],
            font=("Consolas", 12, "bold"),
            anchor="e",
        ).grid(row=0, column=1, sticky="e")
        self.chart = tk.Canvas(
            self.wave_zone,
            height=230,
            bg="#020617",
            highlightthickness=1,
            highlightbackground=self.colors["muted_border"],
        )
        self.chart.pack(fill="both", expand=True)

        control_panel = self._make_panel(self.aux_zone)
        self.control_panel = control_panel
        self.control_panel.configure(padx=12, pady=11)
        control_panel.grid(row=0, column=0, sticky="ew", pady=(0, 10))
        self._section_heading(control_panel, "CONNECTION + QUICK ACTIONS")
        signal_row = tk.Frame(control_panel, bg=self.colors["panel_bg"])
        signal_row.pack(fill="x", pady=(0, 6))
        self.link_dot = tk.Label(signal_row, text=" ", bg="#fca5a5", width=2, padx=0, pady=0)
        self.link_dot.pack(side="left", padx=(0, 10))
        self.link_badge = tk.Label(
            signal_row,
            text="SIGNAL LOST",
            bg=self.colors["panel_bg"],
            fg="#f8b4b4",
            font=("Consolas", 12, "bold"),
            anchor="w",
        )
        self.link_badge.pack(side="left")

        form = tk.Frame(control_panel, bg=self.colors["panel_bg"])
        form.pack(fill="x")
        form.columnconfigure(0, weight=1)
        form.columnconfigure(1, weight=1)
        tk.Label(form, text="Serial Port", bg=self.colors["panel_bg"], fg=self.colors["muted"], anchor="w").grid(row=0, column=0, sticky="w")
        self.port_combo = ttk.Combobox(form, textvariable=self.current_port, width=14, state="readonly", style="Dark.TCombobox")
        self.port_combo.grid(row=1, column=0, sticky="ew", padx=(0, 10), pady=(4, 6))
        tk.Label(form, text="Baud", bg=self.colors["panel_bg"], fg=self.colors["muted"], anchor="w").grid(row=0, column=1, sticky="w")
        self.baud_entry = tk.Entry(
            form,
            textvariable=self.current_baud,
            bg=self.colors["panel_alt"],
            fg=self.colors["text"],
            insertbackground=self.colors["text"],
            relief="flat",
            highlightthickness=1,
            highlightbackground=self.colors["muted_border"],
            highlightcolor=self.colors["accent"],
        )
        self.baud_entry.grid(row=1, column=1, sticky="ew", pady=(4, 6))

        conn_buttons = tk.Frame(control_panel, bg=self.colors["panel_bg"])
        conn_buttons.pack(fill="x")
        conn_buttons.columnconfigure((0, 1, 2), weight=1)
        self._make_action_button(conn_buttons, "Refresh Ports", self._refresh_ports).grid(row=0, column=0, sticky="ew", padx=(0, 8))
        self._make_action_button(conn_buttons, "Connect", self._connect).grid(row=0, column=1, sticky="ew", padx=(0, 8))
        self._make_action_button(conn_buttons, "Disconnect", self._disconnect).grid(row=0, column=2, sticky="ew")

        quick_panel = tk.Frame(control_panel, bg=self.colors["panel_bg"])
        quick_panel.pack(fill="x", expand=False, pady=(6, 0))
        tk.Label(
            quick_panel,
            text="TACTICAL ACTION GRID",
            bg=self.colors["panel_bg"],
            fg=self.colors["muted"],
            font=("Segoe UI", 10, "bold"),
            anchor="w",
        ).pack(anchor="w", pady=(0, 6))
        action_grid = tk.Frame(quick_panel, bg=self.colors["panel_bg"])
        action_grid.pack(fill="x")
        for idx in range(4):
            action_grid.columnconfigure(idx, weight=1)
        action_specs = [
            ("Query Stats", lambda: self._submit_case(case_query_stats())),
            ("Rule Hits", lambda: self._submit_case(case_acl_v2_hit_counters())),
            ("Invalid", lambda: self._submit_case(case_invalid_selector())),
            ("SM4 16B", lambda: self._submit_case(case_sm4_known_vector())),
            ("AES 16B", lambda: self._submit_case(case_aes_known_vector())),
            ("SM4 32B", lambda: self._submit_case(case_sm4_two_block_vector())),
            ("AES 32B", lambda: self._submit_case(case_aes_two_block_vector())),
            ("SM4 64B", lambda: self._submit_case(case_sm4_four_block_vector())),
            ("AES 64B", lambda: self._submit_case(case_aes_four_block_vector())),
            ("SM4 128B", lambda: self._submit_case(case_sm4_eight_block_vector())),
            ("AES 128B", lambda: self._submit_case(case_aes_eight_block_vector())),
        ]
        for idx, (label, command) in enumerate(action_specs):
            row, col = divmod(idx, 4)
            self._make_action_button(action_grid, label, command).grid(row=row, column=col, sticky="ew", padx=4, pady=3)

        acl_bar = tk.Frame(quick_panel, bg=self.colors["panel_bg"])
        acl_bar.pack(fill="x", pady=(8, 0))
        acl_bar.columnconfigure(1, weight=1)
        tk.Label(acl_bar, text="ACL Probe", bg=self.colors["panel_bg"], fg=self.colors["muted"], anchor="w").grid(row=0, column=0, padx=(0, 10), sticky="w")
        self.acl_entry = tk.Entry(
            acl_bar,
            textvariable=self.acl_text,
            bg=self.colors["panel_alt"],
            fg=self.colors["text"],
            insertbackground=self.colors["text"],
            relief="flat",
            highlightthickness=1,
            highlightbackground=self.colors["muted_border"],
            highlightcolor=self.colors["accent"],
        )
        self.acl_entry.grid(row=0, column=1, sticky="ew", padx=(0, 10))
        self._make_action_button(acl_bar, "Send Block Test", self._send_acl_probe).grid(row=0, column=2, sticky="ew")

        deploy_panel = tk.Frame(quick_panel, bg=self.colors["panel_bg"])
        deploy_panel.pack(fill="x", pady=(10, 0))
        tk.Label(
            deploy_panel,
            text="DEPLOY THREAT SIGNATURE",
            bg=self.colors["panel_bg"],
            fg="#fda4af",
            font=("Segoe UI", 10, "bold"),
            anchor="w",
        ).grid(row=0, column=0, columnspan=6, sticky="w", pady=(0, 6))
        for col in range(6):
            deploy_panel.columnconfigure(col, weight=1 if col in (1, 3) else 0)
        tk.Label(
            deploy_panel,
            text="Slot",
            bg=self.colors["panel_bg"],
            fg=self.colors["muted"],
            anchor="w",
        ).grid(row=1, column=0, sticky="w", padx=(0, 10))
        ttk.Combobox(
            deploy_panel,
            textvariable=self.deploy_rule_slot,
            values=list(range(8)),
            state="readonly",
            width=5,
            style="Dark.TCombobox",
        ).grid(row=1, column=1, sticky="ew", padx=(0, 10))
        tk.Label(
            deploy_panel,
            text="Rule Byte",
            bg=self.colors["panel_bg"],
            fg=self.colors["muted"],
            anchor="w",
        ).grid(row=1, column=2, sticky="w", padx=(0, 10))
        self.deploy_rule_entry = tk.Entry(
            deploy_panel,
            textvariable=self.deploy_rule_key,
            bg=self.colors["panel_alt"],
            fg=self.colors["text"],
            insertbackground=self.colors["text"],
            relief="flat",
            highlightthickness=1,
            highlightbackground=self.colors["muted_border"],
            highlightcolor=self.colors["accent"],
        )
        self.deploy_rule_entry.grid(row=1, column=3, sticky="ew")
        self._make_action_button(deploy_panel, "Deploy", self._deploy_acl_rule).grid(
            row=1, column=4, sticky="ew", padx=(10, 8)
        )
        self._make_action_button(deploy_panel, "Refresh Rules", self._refresh_acl_key_map).grid(
            row=1, column=5, sticky="ew"
        )

        pmu_panel = tk.Frame(quick_panel, bg=self.colors["panel_bg"])
        pmu_panel.pack(fill="x", pady=(10, 0))
        for col in range(8):
            pmu_panel.columnconfigure(col, weight=1 if col >= 3 else 0)
        tk.Label(
            pmu_panel,
            text="PMU",
            bg=self.colors["panel_bg"],
            fg="#93c5fd",
            font=("Segoe UI", 10, "bold"),
            anchor="w",
        ).grid(row=0, column=0, sticky="w", pady=(0, 6), padx=(0, 10))
        self._make_action_button(pmu_panel, "Clear PMU", self._clear_pmu).grid(
            row=0, column=1, sticky="ew", padx=(0, 8), pady=(0, 6)
        )
        self._make_action_button(pmu_panel, "Read PMU", self._read_pmu).grid(
            row=0, column=2, sticky="ew", pady=(0, 6)
        )
        self._make_action_button(pmu_panel, "Read Trace", self._read_trace).grid(
            row=0, column=3, sticky="ew", padx=(8, 0), pady=(0, 6)
        )
        metric_strip = tk.Frame(pmu_panel, bg=self.colors["panel_bg"])
        metric_strip.grid(row=1, column=0, columnspan=8, sticky="ew")
        for col in range(8):
            metric_strip.columnconfigure(col, weight=1)
        for idx, (label, key, color) in enumerate(
            [
                ("HW Util", "hw_util", "#93c5fd"),
                ("UART Stall", "uart_stall", "#f59e0b"),
                ("Credit Block", "credit_block", "#fda4af"),
                ("ACL Events", "acl_events", "#86efac"),
                ("Clock", "clock_status", "#fbbf24"),
            ]
        ):
            tk.Label(
                metric_strip,
                text=label.upper(),
                bg=self.colors["panel_bg"],
                fg=color,
                font=("Segoe UI", 7, "bold"),
                anchor="w",
            ).grid(row=0, column=idx * 2, sticky="w", padx=(0, 4) if idx == 0 else (8, 4))
            tk.Label(
                metric_strip,
                textvariable=self.pmu_vars[key],
                bg=self.colors["panel_bg"],
                fg=self.colors["text"],
                font=("Consolas", 9, "bold"),
                anchor="w",
            ).grid(row=0, column=idx * 2 + 1, sticky="w")

        self.bench_panel = tk.Frame(quick_panel, bg=self.colors["panel_bg"])
        self.bench_panel.pack(fill="x", pady=(10, 0))
        for col in range(8):
            self.bench_panel.columnconfigure(col, weight=1 if col in (1, 4, 5, 6, 7) else 0)
        tk.Label(
            self.bench_panel,
            text="ON-CHIP BENCHMARK",
            bg=self.colors["panel_bg"],
            fg="#facc15",
            font=("Segoe UI", 10, "bold"),
            anchor="w",
        ).grid(row=0, column=0, columnspan=8, sticky="w", pady=(0, 6))
        tk.Label(
            self.bench_panel,
            text="Algo",
            bg=self.colors["panel_bg"],
            fg=self.colors["muted"],
            anchor="w",
        ).grid(row=1, column=0, sticky="w", padx=(0, 10))
        ttk.Combobox(
            self.bench_panel,
            textvariable=self.bench_algo,
            values=("SM4", "AES"),
            state="readonly",
            width=6,
            style="Dark.TCombobox",
        ).grid(row=1, column=1, sticky="ew", padx=(0, 10))
        self._make_action_button(self.bench_panel, "Run Bench", self._run_bench).grid(
            row=1, column=2, sticky="ew", padx=(0, 8)
        )
        self._make_action_button(self.bench_panel, "Force Run", self._force_run_bench).grid(
            row=1, column=3, sticky="ew", padx=(0, 8)
        )
        self._make_action_button(self.bench_panel, "Read Result", self._read_bench_result).grid(
            row=1, column=4, sticky="ew", padx=(0, 8)
        )
        for idx, (label, key, color) in enumerate(
            [
                ("Status", "status", "#facc15"),
                ("Effective Mbps", "mbps", "#93c5fd"),
                ("Cycles", "cycles", "#fda4af"),
                ("CRC32", "crc32", "#86efac"),
            ]
        ):
            tk.Label(
                self.bench_panel,
                text=label.upper(),
                bg=self.colors["panel_bg"],
                fg=color,
                font=("Segoe UI", 7, "bold"),
                anchor="w",
            ).grid(row=2, column=idx * 2, sticky="w", padx=(0, 4) if idx == 0 else (8, 4), pady=(8, 0))
            tk.Label(
                self.bench_panel,
                textvariable=self.bench_vars[key],
                bg=self.colors["panel_bg"],
                fg=self.colors["text"],
                font=("Consolas", 9, "bold"),
                anchor="w",
            ).grid(row=2, column=idx * 2 + 1, sticky="w", pady=(8, 0))

        self.live_log_zone = self._make_panel(self.aux_zone)
        self.live_log_zone.grid(row=1, column=0, sticky="nsew")
        self._section_heading(self.live_log_zone, "LIVE LOG AREA")
        self.log_box = scrolledtext.ScrolledText(
            self.live_log_zone,
            wrap="word",
            font=("Consolas", 10),
            bg="#0b0f16",
            fg=self.colors["text"],
            insertbackground=self.colors["text"],
            relief="flat",
            bd=0,
            padx=10,
            pady=10,
            height=14,
        )
        self.log_box.pack(fill="both", expand=True)
        self.log_box.tag_config("info", foreground="#d7e3f4")
        self.log_box.tag_config("pass", foreground="#86efac")
        self.log_box.tag_config("warn", foreground="#fdba74")
        self.log_box.tag_config("block", foreground="#fca5a5", font=("Consolas", 10, "bold"))
        self.log_box.tag_config("error", foreground="#fda4af", font=("Consolas", 10, "bold"))

        self.trace_panel = tk.Frame(self.live_log_zone, bg=self.colors["panel_bg"])
        self.trace_panel.pack(fill="both", expand=False, pady=(10, 0))
        tk.Label(
            self.trace_panel,
            text="TRACE BUFFER",
            bg=self.colors["panel_bg"],
            fg="#facc15",
            font=("Segoe UI", 10, "bold"),
            anchor="w",
        ).pack(anchor="w", pady=(0, 6))
        self.trace_box = scrolledtext.ScrolledText(
            self.trace_panel,
            wrap="word",
            font=("Consolas", 9),
            bg="#0b0f16",
            fg=self.colors["text"],
            insertbackground=self.colors["text"],
            relief="flat",
            bd=0,
            padx=10,
            pady=8,
            height=8,
        )
        self.trace_box.pack(fill="both", expand=True)
        self.trace_box.configure(state="disabled")

        self.footer_zone = tk.Frame(shell, bg=self.colors["shell_bg"])
        self.footer_zone.grid(row=2, column=0, sticky="nsew", pady=(16, 0))
        self.footer_zone.columnconfigure(0, weight=3)
        self.footer_zone.columnconfigure(1, weight=7)
        self.footer_zone.rowconfigure(0, weight=1)
        self.telemetry_zone = self._make_panel(self.footer_zone)
        self.telemetry_zone.grid(row=0, column=0, sticky="nsew", padx=(0, 12))
        self._section_heading(self.telemetry_zone, "COUNTER BANK")
        counter_grid = tk.Frame(self.telemetry_zone, bg=self.colors["panel_bg"])
        counter_grid.pack(fill="both", expand=True)
        for idx in range(5):
            counter_grid.columnconfigure(idx, weight=1)
        for idx, (key, label, color) in enumerate(
            [
                ("total", "Total", "#93c5fd"),
                ("acl", "ACL", "#fca5a5"),
                ("aes", "AES", "#c4b5fd"),
                ("sm4", "SM4", "#86efac"),
                ("err", "Error", "#fca5a5"),
            ]
        ):
            card, value_label = self._make_metric_tile(counter_grid, label, self.stats_vars[key], title_fg=color, value_fg=self.colors["text"])
            card.grid(row=0, column=idx, sticky="nsew", padx=4, pady=4)
            self.stat_value_labels[key] = value_label

        self.acl_zone = self._make_panel(self.footer_zone)
        self.acl_zone.grid(row=0, column=1, sticky="nsew")
        self._section_heading(self.acl_zone, "BRAM ACL THREAT ARRAY")
        acl_header = tk.Frame(self.acl_zone, bg=self.colors["panel_bg"])
        acl_header.pack(fill="x", pady=(0, 6))
        tk.Label(
            acl_header,
            text="RULE HIT INTENSITY",
            bg=self.colors["panel_bg"],
            fg=self.colors["muted"],
            font=("Segoe UI", 10, "bold"),
        ).pack(side="left")
        tk.Label(
            acl_header,
            textvariable=self.hot_rule_text,
            bg=self.colors["panel_bg"],
            fg="#fda4af",
            font=("Segoe UI", 10, "bold"),
        ).pack(side="right")
        rules_grid = tk.Frame(self.acl_zone, bg=self.colors["panel_bg"])
        rules_grid.pack(fill="x")
        for idx in range(8):
            rules_grid.columnconfigure(idx, weight=1)
        for idx, label in enumerate(self.rule_slot_labels):
            cell = tk.Frame(
                rules_grid,
                bg="#111827",
                highlightbackground=self.colors["muted_border"],
                highlightthickness=1,
                padx=3,
                pady=3,
            )
            cell.grid(row=0, column=idx, sticky="nsew", padx=3, pady=3)
            title_label = tk.Label(
                cell,
                text=f"SLOT {idx}: {label}",
                bg="#111827",
                fg="#fb7185",
                font=("Segoe UI", 6, "bold"),
            )
            title_label.pack(anchor="w")
            hit_label = tk.Label(
                cell,
                textvariable=self.acl_rule_hit_vars[idx],
                bg="#111827",
                fg=self.colors["text"],
                font=("Consolas", 10, "bold"),
                anchor="w",
            )
            hit_label.pack(anchor="w", pady=(3, 2))
            bar_canvas = tk.Canvas(cell, width=98, height=12, bg="#0b1120", highlightthickness=0, bd=0)
            bar_canvas.pack(fill="x")
            fill_id = bar_canvas.create_rectangle(0, 0, 0, 18, fill="#07111f", outline="")
            self.acl_rule_cells[idx] = cell
            self.acl_rule_title_labels[idx] = title_label
            self.acl_rule_hit_labels[idx] = hit_label
            self.acl_rule_bar_canvases[idx] = bar_canvas
            self.acl_rule_bar_fills[idx] = fill_id

        self._set_link_visual("#fca5a5", "SIGNAL LOST", "#f8b4b4")
        self._draw_chart()

    def _build_file_status_panel(self, parent: tk.Widget) -> None:
        status_shell = tk.Frame(parent, bg=self.colors["panel_bg"])
        status_shell.grid(row=1, column=0, sticky="nsew", pady=(14, 0))
        for idx in range(4):
            status_shell.columnconfigure(idx, weight=1)
        status_shell.rowconfigure(0, weight=0)
        status_shell.rowconfigure(1, weight=0, minsize=34)
        status_shell.rowconfigure(2, weight=0, minsize=84)

        cards = [
            ("Logical Payload", "logical", "#38bdf8"),
            ("PKCS#7 Padding", "padding", "#f59e0b"),
            ("Transport MTU Size", "transport", "#a78bfa"),
            ("Chunk Matrix", "chunks", "#34d399"),
        ]
        for idx, (label, key, accent) in enumerate(cards):
            card = tk.Frame(
                status_shell,
                bg="#0b1220",
                highlightbackground=self.colors["muted_border"],
                highlightthickness=1,
                padx=7,
                pady=7,
            )
            card.grid(row=0, column=idx, sticky="nsew", padx=6, pady=(0, 12))
            tk.Label(
                card,
                text=label,
                bg="#0b1220",
                fg=accent,
                font=("Segoe UI", 10, "bold"),
                anchor="w",
            ).pack(anchor="w")
            tk.Label(
                card,
                textvariable=self.file_status_vars[key],
                bg="#0b1220",
                fg="#f8fafc",
                font=("Consolas", 15, "bold"),
                anchor="w",
            ).pack(anchor="w", pady=(12, 0))

        pulse_row = tk.Frame(status_shell, bg=self.colors["panel_bg"])
        pulse_row.grid(row=1, column=0, columnspan=4, sticky="ew")
        pulse_row.columnconfigure(1, weight=1)
        self.pulse_indicator = tk.Label(
            pulse_row,
            textvariable=self.file_status_vars["pulse"],
            bg="#1f2937",
            fg="#cbd5e1",
            font=("Segoe UI", 8, "bold"),
            width=10,
            padx=8,
            pady=5,
            relief="ridge",
            bd=1,
        )
        self.pulse_indicator.grid(row=0, column=0, padx=(0, 8), sticky="w")
        tk.Label(
            pulse_row,
            textvariable=self.file_status_vars["progress"],
            bg=self.colors["panel_bg"],
            fg=self.colors["text"],
            font=("Consolas", 9, "bold"),
            anchor="w",
        ).grid(row=0, column=1, sticky="w", padx=(6, 0))

        self.file_progress_canvas = tk.Canvas(
            status_shell,
            height=84,
            bg="#020617",
            highlightthickness=1,
            highlightbackground=self.colors["muted_border"],
        )
        self.file_progress_canvas.grid(row=2, column=0, columnspan=4, sticky="ew", pady=(12, 0))
        self._draw_file_progress()

    def _timestamp(self) -> str:
        return datetime.now().strftime("%H:%M:%S")

    def _append_log(self, message: str, tag: str = "info") -> None:
        self.log_box.insert("end", f"[{self._timestamp()}] {message}\n", tag)
        self.log_box.see("end")

    def _set_banner(self, text: str, level: str = "info") -> None:
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
        self._set_link_visual("#fde68a", "LINKING", "#fde68a")
        self._set_banner(f"Connecting to {port}...", "warn")

    def _disconnect(self) -> None:
        self.worker.disconnect()

    def _submit_case(self, case) -> None:
        self.worker.submit_case(case)
        self._append_log(f"Queued: {case.name}")
        self._set_banner(f"Queued action: {case.name}", "info")

    def _refresh_runtime_views(self) -> None:
        self.worker.submit_case(case_acl_v2_keymap())
        self.worker.submit_case(case_acl_v2_hit_counters())
        self._append_log("Queued: Query ACL Key Map")
        self._append_log("Queued: Query Rule Hits")

    def _refresh_acl_key_map(self) -> None:
        self.worker.submit_case(case_acl_v2_keymap())
        self._append_log("Queued: Query ACL Key Map")
        self._set_banner("Queued ACL key-map refresh.", "info")

    def _clear_pmu(self) -> None:
        self.worker.submit_case(case_clear_pmu())
        self._append_log("Queued: Clear PMU")
        self._set_banner("Queued PMU clear.", "warn")

    def _read_pmu(self) -> None:
        self.worker.submit_case(case_query_pmu())
        self._append_log("Queued: Query PMU")
        self._set_banner("Queued PMU snapshot readback.", "info")

    def _read_trace(self) -> None:
        self.worker.query_trace()
        self._append_log("Queued: Query Trace")
        self._set_banner("Queued trace snapshot readback.", "info")

    def _run_bench(self) -> None:
        case = case_run_onchip_bench(self.bench_algo.get())
        self.worker.submit_case(case)
        self._append_log(f"Queued: {case.name}")
        self._set_banner(f"Queued on-chip benchmark via {self.bench_algo.get()}.", "warn")

    def _force_run_bench(self) -> None:
        case = case_force_run_onchip_bench(self.bench_algo.get())
        self.worker.submit_case(case)
        self._append_log(f"Queued: {case.name}")
        self._set_banner(f"Queued force benchmark via {self.bench_algo.get()}.", "warn")

    def _read_bench_result(self) -> None:
        self.worker.submit_case(case_query_bench_result())
        self._append_log("Queued: Query Bench Result")
        self._set_banner("Queued on-chip benchmark result readback.", "info")

    def _send_acl_probe(self) -> None:
        text = self.acl_text.get().strip()
        if not text:
            messagebox.showerror("ACL Probe", "Enter an ASCII string for ACL testing.")
            return
        self._submit_case(case_block_ascii(text))

    def _deploy_acl_rule(self) -> None:
        try:
            slot = int(self.deploy_rule_slot.get())
            hex_sig = self.deploy_rule_key.get().strip().replace(" ", "")
            if len(hex_sig) != 32:
                messagebox.showerror(
                    "Deploy Threat Signature",
                    "Must be exactly 32 hex chars (16 bytes) for ACL v2",
                )
                return
            bytes.fromhex(hex_sig)
            self.worker.submit_case(case_acl_v2_write(slot, hex_sig))
            self._append_log(
                f"Queued ACL v2 write: slot {slot} -> {hex_sig[:16]}...",
                "warn",
            )
            self._set_banner(
                f"Deploying ACL v2 slot {slot}",
                "warn",
            )
        except ValueError as exc:
            messagebox.showerror("Deploy Threat Signature", str(exc))

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
        self.worker.submit_case(case_acl_v2_hit_counters())
        self._append_log("Queued: Query Rule Hits (auto-refresh)")

    @staticmethod
    def _extract_first_payload_byte(frame: bytes) -> int | None:
        if len(frame) < 3 or frame[0] != 0x55:
            return None
        payload_len = frame[1]
        if payload_len < 1 or len(frame) < payload_len + 2:
            return None
        return frame[2]

    @staticmethod
    def _format_acl_v2_signature(signature: bytes) -> str:
        hex_text = signature.hex().upper()
        if len(hex_text) != 32:
            return hex_text or "--"
        preview = "".join(chr(value) if 32 <= value <= 126 else "." for value in signature[:4])
        return f"{hex_text[:8]}...{hex_text[-8:]} [{preview}]"

    def _apply_acl_key_map(self, keys: tuple[int, ...] | tuple[bytes, ...]) -> None:
        if len(keys) != 8:
            return
        first = keys[0]
        if isinstance(first, (bytes, bytearray)):
            signatures = tuple(bytes(value) for value in keys)
            self.rule_slot_keys = [sig[0] if sig else 0 for sig in signatures]
            self.rule_slot_labels = [self._format_acl_v2_signature(sig) for sig in signatures]
        else:
            self.rule_slot_keys = [int(value) for value in keys]
            self.rule_slot_labels = [display_rule_byte(value) for value in self.rule_slot_keys]
        for idx, label in enumerate(self.rule_slot_labels):
            title = self.acl_rule_title_labels.get(idx)
            if title is not None:
                title.configure(text=f"SLOT {idx}: {label}")

    def _reset_pmu_display(self) -> None:
        self.pmu_vars["hw_util"].set("0.0%")
        self.pmu_vars["uart_stall"].set("0.0%")
        self.pmu_vars["credit_block"].set("0.0%")
        self.pmu_vars["acl_events"].set("0")
        self.pmu_vars["stream_bytes_in"].set("0")
        self.pmu_vars["stream_bytes_out"].set("0")
        self.pmu_vars["stream_chunks"].set("0")
        self.pmu_vars["clock_status"].set("ACTIVE")

    def _reset_frozen_evidence(self) -> None:
        self.evidence_frozen_vars["wire_mbps"].set("- Mbps")
        self.evidence_frozen_vars["chip_mbps"].set("- Mbps")
        self.evidence_frozen_vars["gap_ratio"].set("-")
        self.evidence_frozen_vars["hw_util"].set("-")
        self.evidence_frozen_vars["uart_stall"].set("-")
        self.evidence_frozen_vars["credit_block"].set("-")
        self.evidence_frozen_vars["stream_in"].set("-")
        self.evidence_frozen_vars["stream_out"].set("-")
        self.evidence_frozen_vars["stream_chunks"].set("-")
        self.evidence_frozen_vars["clock_status"].set("-")
        self.evidence_frozen_active = False

    def _apply_pmu_snapshot(self, payload: dict) -> None:
        self.pmu_vars["hw_util"].set(f"{float(payload['crypto_utilization']) * 100.0:.2f}%")
        self.pmu_vars["uart_stall"].set(f"{float(payload['uart_stall_ratio']) * 100.0:.2f}%")
        self.pmu_vars["credit_block"].set(f"{float(payload['credit_block_ratio']) * 100.0:.2f}%")
        self.pmu_vars["acl_events"].set(str(int(payload["acl_block_events"])))
        self.pmu_vars["stream_bytes_in"].set(str(int(payload.get("stream_bytes_in", 0))))
        self.pmu_vars["stream_bytes_out"].set(str(int(payload.get("stream_bytes_out", 0))))
        self.pmu_vars["stream_chunks"].set(str(int(payload.get("stream_chunk_count", 0))))
        self.pmu_vars["clock_status"].set("GATED" if (int(payload.get("crypto_clock_status_flags", 0)) & 0x1) else "ACTIVE")

    def _freeze_evidence_snapshot(self, wire_mbps: float, total_bytes: int, chunk_count: int) -> None:
        self.evidence_frozen_vars["wire_mbps"].set(f"{wire_mbps:.3f} Mbps")
        self.evidence_frozen_vars["chip_mbps"].set(self.evidence_live_vars["chip_mbps"].get())
        self.evidence_frozen_vars["gap_ratio"].set(self.evidence_live_vars["gap_ratio"].get())
        self.evidence_frozen_vars["hw_util"].set(self.evidence_live_vars["hw_util"].get())
        self.evidence_frozen_vars["uart_stall"].set(self.evidence_live_vars["uart_stall"].get())
        self.evidence_frozen_vars["credit_block"].set(self.evidence_live_vars["credit_block"].get())
        self.evidence_frozen_vars["stream_in"].set(self.evidence_live_vars["stream_in"].get())
        self.evidence_frozen_vars["stream_out"].set(self.evidence_live_vars["stream_out"].get())
        self.evidence_frozen_vars["stream_chunks"].set(str(chunk_count))
        self.evidence_frozen_vars["clock_status"].set(self.evidence_live_vars["clock_status"].get())
        self.evidence_frozen_active = True

    def _update_live_evidence(self, payload: dict) -> None:
        stream_in = int(payload.get("stream_bytes_in", 0))
        stream_out = int(payload.get("stream_bytes_out", 0))
        global_cycles = int(payload.get("global_cycles", 1))
        crypto_active = int(payload.get("crypto_active_cycles", 0))
        hw_util = float(payload["crypto_utilization"]) if "crypto_utilization" in payload else 0.0
        self.evidence_live_vars["hw_util"].set(f"{hw_util * 100.0:.2f}%")
        self.evidence_live_vars["uart_stall"].set(f"{float(payload.get('uart_stall_ratio', 0.0)) * 100.0:.2f}%")
        self.evidence_live_vars["credit_block"].set(f"{float(payload.get('credit_block_ratio', 0.0)) * 100.0:.2f}%")
        self.evidence_live_vars["clock_status"].set("GATED" if (int(payload.get("crypto_clock_status_flags", 0)) & 0x1) else "ACTIVE")
        self.evidence_live_vars["stream_in"].set(self._format_bytes(stream_in))
        self.evidence_live_vars["stream_out"].set(self._format_bytes(stream_out))
        self.evidence_live_vars["stream_chunks"].set(str(int(payload.get("stream_chunk_count", 0))))
        if global_cycles > 0 and stream_out > 0:
            chip_mbps = (stream_out * 8) / (global_cycles / int(payload.get("clk_hz", 50_000_000))) / 1_000_000.0
            self.evidence_live_vars["chip_mbps"].set(f"{chip_mbps:.3f} Mbps")
        wire_mbps_str = self.evidence_live_vars["wire_mbps"].get()
        if wire_mbps_str not in ("- Mbps", "") and " Mbps" in wire_mbps_str:
            try:
                wire_val = float(wire_mbps_str.split()[0])
                if wire_val > 0:
                    chip_val_str = self.evidence_live_vars["chip_mbps"].get()
                    if " Mbps" in chip_val_str:
                        chip_val = float(chip_val_str.split()[0])
                        gap = (wire_val - chip_val) / wire_val
                        self.evidence_live_vars["gap_ratio"].set(f"{gap * 100.0:.1f}%")
                    else:
                        self.evidence_live_vars["gap_ratio"].set("-")
                else:
                    self.evidence_live_vars["gap_ratio"].set("-")
            except (ValueError, IndexError):
                self.evidence_live_vars["gap_ratio"].set("-")
        else:
            self.evidence_live_vars["gap_ratio"].set("-")

    def _format_bytes(self, n: int) -> str:
        if n >= 1_048_576:
            return f"{n / 1_048_576:.2f} MiB"
        elif n >= 1024:
            return f"{n / 1024:.2f} KiB"
        else:
            return f"{n} B"

    def _apply_bench_result(self, payload: dict) -> None:
        status_value = payload.get("status_text")
        if status_value is None:
            status_map = {
                0x00: "SUCCESS",
                0x01: "BUSY",
                0x02: "TIMEOUT",
                0x03: "INTERNAL",
                0x04: "NO_RESULT",
            }
            raw_status = payload.get("status")
            status_value = status_map.get(raw_status, str(raw_status if raw_status is not None else "-"))
        self.bench_vars["status"].set(str(status_value))
        effective_mbps = payload.get("effective_mbps")
        if effective_mbps is None:
            self.bench_vars["mbps"].set("-")
        else:
            self.bench_vars["mbps"].set(f"{float(effective_mbps):.3f} Mbps")
        self.bench_vars["cycles"].set(str(int(payload.get("cycles", 0))))
        self.bench_vars["crc32"].set(f"0x{int(payload.get('crc32', 0)):08X}")

    def _apply_trace_snapshot(self, payload: dict) -> None:
        entries = payload.get("entries", [])[-32:]
        lines = [
            f"t={float(entry['timestamp_ms']):.3f} ms | {entry['description']}"
            for entry in entries
        ]
        self.trace_box.configure(state="normal")
        self.trace_box.delete("1.0", "end")
        if lines:
            self.trace_box.insert("end", "\n".join(lines))
        else:
            self.trace_box.insert("end", "(trace buffer empty)")
        self.trace_box.configure(state="disabled")

    def _apply_pmu_snapshot_to_evidencelive(self, payload: dict) -> None:
        self.evidence_live_vars["hw_util"].set(f"{float(payload['crypto_utilization']) * 100.0:.2f}%")
        self.evidence_live_vars["uart_stall"].set(f"{float(payload['uart_stall_ratio']) * 100.0:.2f}%")
        self.evidence_live_vars["credit_block"].set(f"{float(payload['credit_block_ratio']) * 100.0:.2f}%")
        self.evidence_live_vars["clock_status"].set("GATED" if (int(payload.get("crypto_clock_status_flags", 0)) & 0x1) else "ACTIVE")
        self.evidence_live_vars["stream_in"].set(str(int(payload.get("stream_bytes_in", 0))))
        self.evidence_live_vars["stream_out"].set(str(int(payload.get("stream_bytes_out", 0))))
        self.evidence_live_vars["stream_chunks"].set(str(int(payload.get("stream_chunk_count", 0))))

    def _update_frozen_from_live(self) -> None:
        chip_mbps_live = self.evidence_live_vars["chip_mbps"].get()
        if chip_mbps_live not in ("- Mbps", ""):
            self.evidence_frozen_vars["chip_mbps"].set(chip_mbps_live)
        gap_live = self.evidence_live_vars["gap_ratio"].get()
        if gap_live not in ("-", ""):
            self.evidence_frozen_vars["gap_ratio"].set(gap_live)
        hw_live = self.evidence_live_vars["hw_util"].get()
        if hw_live not in ("-", ""):
            self.evidence_frozen_vars["hw_util"].set(hw_live)
        us_live = self.evidence_live_vars["uart_stall"].get()
        if us_live not in ("-", ""):
            self.evidence_frozen_vars["uart_stall"].set(us_live)
        cb_live = self.evidence_live_vars["credit_block"].get()
        if cb_live not in ("-", ""):
            self.evidence_frozen_vars["credit_block"].set(cb_live)
        si_live = self.evidence_live_vars["stream_in"].get()
        if si_live not in ("-", ""):
            self.evidence_frozen_vars["stream_in"].set(si_live)
        so_live = self.evidence_live_vars["stream_out"].get()
        if so_live not in ("-", ""):
            self.evidence_frozen_vars["stream_out"].set(so_live)
        sc_live = self.evidence_live_vars["stream_chunks"].get()
        if sc_live not in ("-", "", "0"):
            self.evidence_frozen_vars["stream_chunks"].set(sc_live)
        clock_live = self.evidence_live_vars["clock_status"].get()
        if clock_live not in ("-", ""):
            self.evidence_frozen_vars["clock_status"].set(clock_live)

    def _draw_chart(self) -> None:
        self.chart.delete("all")
        width = int(self.chart.winfo_width() or 900)
        height = int(self.chart.winfo_height() or 230)
        margin = 16
        self.chart.create_rectangle(margin, margin, width - margin, height - margin, outline="#1e293b")
        for step in range(1, 4):
            y = margin + step * (height - 2 * margin) / 4
            self.chart.create_line(margin, y, width - margin, y, fill="#0f2239")
        values = list(self.mbps_history)
        vmax = max(max(values, default=0.0), 1.0)
        raw_points = []
        for idx, value in enumerate(values):
            x = margin + idx * (width - 2 * margin) / max(len(values) - 1, 1)
            normalized = value / vmax
            y = height - margin - normalized * (height - 2 * margin)
            raw_points.append((x, y))
        step_points: list[float] = []
        if raw_points:
            step_points.extend(raw_points[0])
            for (prev_x, prev_y), (x, y) in zip(raw_points, raw_points[1:]):
                step_points.extend([x, prev_y, x, y])
        if len(step_points) >= 4:
            self.chart.create_line(*step_points, fill="#22d3ee", width=3)
        baseline_y = height - margin
        self.chart.create_line(margin, baseline_y, width - margin, baseline_y, fill="#164e63", width=2)
        self.chart.create_text(
            margin + 10,
            margin + 8,
            text=f"PEAK {vmax:.3f} Mbps",
            fill=self.colors["subtle"],
            anchor="nw",
            font=("Consolas", 10, "bold"),
        )

    def _record_transport_activity(self, byte_count: int, latency_s: float) -> None:
        self.pending_transport_bytes += max(byte_count, 0)
        self.last_latency_label.set(f"{latency_s * 1000.0:.1f} ms")

    def _sample_throughput(self) -> None:
        now = time.perf_counter()
        elapsed = max(now - self.last_sample_at, 1e-6)
        mbps = (self.pending_transport_bytes * 8) / elapsed / 1_000_000.0
        self.pending_transport_bytes = 0
        self.last_sample_at = now
        self.mbps_history.append(mbps)
        self.throughput_label.set(f"{mbps:.3f} Mbps")
        self._draw_chart()
        self.throughput_sample_job = self.after(80, self._sample_throughput)

    def _draw_file_progress(self) -> None:
        canvas = self.file_progress_canvas
        canvas.delete("all")
        width = int(canvas.winfo_width() or 560)
        height = int(canvas.winfo_height() or 54)
        margin = 10
        total = max(self.file_total_chunks, 1)
        done = min(self.file_done_chunks, total)
        usable_width = max(width - 2 * margin, 1)
        cell_gap = 8
        cell_width = max((usable_width - cell_gap * (total - 1)) / total, 8)
        for idx in range(total):
            x0 = margin + idx * (cell_width + cell_gap)
            x1 = x0 + cell_width
            acked = idx < done
            canvas.create_rectangle(
                x0,
                margin,
                x1,
                height - margin,
                fill="#22d3ee" if acked else "#111827",
                outline="#334155",
                width=1,
            )
            canvas.create_text(
                (x0 + x1) / 2,
                (height / 2) - 1,
                text=str(idx + 1),
                fill="#082f49" if acked else self.colors["subtle"],
                font=("Consolas", 10, "bold"),
            )
    def _flash_file_pulse(self, text: str, bg: str, fg: str) -> None:
        if self.file_pulse_job is not None:
            self.after_cancel(self.file_pulse_job)
        self.file_status_vars["pulse"].set(text)
        self.pulse_indicator.configure(bg=bg, fg=fg)
        self.file_pulse_job = self.after(140, self._reset_file_pulse)

    def _reset_file_pulse(self) -> None:
        self.file_pulse_job = None
        self.file_status_vars["pulse"].set("IDLE")
        self.pulse_indicator.configure(bg="#1f2937", fg="#cbd5e1")

    def _begin_file_status(self, payload: dict) -> None:
        original = int(payload["original_bytes"])
        total = int(payload["total_bytes"])
        pad_bytes = int(payload["pad_bytes"])
        chunk_count = int(payload["chunk_count"])
        mtu = int(payload.get("mtu_bytes", 128))
        self.file_name_text.set(f"{Path(payload['path']).name} | {payload['algo']} | LIVE PING-PONG")
        self.file_status_vars["logical"].set(f"{original} Bytes")
        self.file_status_vars["padding"].set(f"{pad_bytes} Bytes")
        self.file_status_vars["transport"].set(f"{total} Bytes")
        self.file_status_vars["chunks"].set(f"{chunk_count} Blocks ({mtu}B/Block)")
        self.file_status_vars["progress"].set(f"0 / {chunk_count} ACKed")
        self.file_done_chunks = 0
        self.file_total_chunks = chunk_count
        self._draw_file_progress()
        self._set_banner(
            f"File scheduler armed: {original}B logical -> {total}B transport, {chunk_count} chunks.",
            "warn",
        )

    def _apply_stats(self, stats: StatsCounters) -> None:
        target_values = {
            "total": stats.total,
            "acl": stats.acl,
            "aes": stats.aes,
            "sm4": stats.sm4,
            "err": stats.err,
        }
        for key, target in target_values.items():
            self._animate_stat_value(key, target)
        palette = {
            "total": ("#0b2a47", "#93c5fd"),
            "acl": ("#3a171c" if stats.acl else "#0f172a", "#fca5a5" if stats.acl else self.colors["text"]),
            "aes": ("#2e1065" if stats.aes else "#0f172a", "#c4b5fd" if stats.aes else self.colors["text"]),
            "sm4": ("#123524" if stats.sm4 else "#0f172a", "#86efac" if stats.sm4 else self.colors["text"]),
            "err": ("#451a1a" if stats.err else "#0f172a", "#fca5a5" if stats.err else self.colors["text"]),
        }
        for key, label in self.stat_value_labels.items():
            bg, fg = palette[key]
            label.configure(bg=bg, fg=fg)

    def _apply_rule_stats(self, rule_stats: AclV2HitCounters | tuple[int, ...]) -> None:
        if isinstance(rule_stats, tuple):
            counts = tuple(int(value) for value in rule_stats)
        else:
            counts = tuple(rule_stats.counts)
        max_hits = max(max(counts, default=0), 1)
        for idx, label in self.acl_rule_hit_labels.items():
            hits = counts[idx]
            self.acl_rule_hit_vars[idx].set(str(hits))
            label.configure(bg="#111827", fg="#f8fafc")
            canvas = self.acl_rule_bar_canvases.get(idx)
            fill_id = self.acl_rule_bar_fills.get(idx)
            if canvas is not None and fill_id is not None:
                width = 220.0 * (hits / max_hits if max_hits else 0.0)
                canvas.coords(fill_id, 0, 0, width, 18)
                canvas.itemconfigure(fill_id, fill=self.colors["accent2"] if hits else "#07111f")
            last_hits = self.acl_rule_last_counts.get(idx, 0)
            if hits > last_hits:
                self._flash_rule_heat(idx)
            self.acl_rule_last_counts[idx] = hits

        hot_idx = max(range(8), key=lambda slot: counts[slot]) if counts else 0
        hot_hits = counts[hot_idx] if counts else 0
        if hot_hits > 0:
            self.hot_rule_text.set(
                f"Hot Rule (board): slot {hot_idx} / {self.rule_slot_labels[hot_idx]} ({hot_hits} hits)"
            )
        else:
            self.hot_rule_text.set("Hot Rule (board): none yet")

    def _animate_stat_value(self, key: str, target: int) -> None:
        if key in self.stat_anim_jobs:
            self.after_cancel(self.stat_anim_jobs[key])
            del self.stat_anim_jobs[key]
        current = self.stat_numeric_cache.get(key, 0)
        if current == target:
            self.stats_vars[key].set(str(target))
            return
        distance = target - current
        step = 1 if abs(distance) <= 8 else max(1, abs(distance) // 6)
        current += step if distance > 0 else -step
        if (distance > 0 and current > target) or (distance < 0 and current < target):
            current = target
        self.stat_numeric_cache[key] = current
        self.stats_vars[key].set(str(current))
        if current != target:
            self.stat_anim_jobs[key] = self.after(28, lambda k=key, t=target: self._animate_stat_value(k, t))

    def _flash_rule_heat(self, rule_slot: int) -> None:
        for job in self.acl_rule_flash_jobs.get(rule_slot, []):
            self.after_cancel(job)
        self.acl_rule_flash_jobs[rule_slot] = []
        cell = self.acl_rule_cells.get(rule_slot)
        title = self.acl_rule_title_labels.get(rule_slot)
        value = self.acl_rule_hit_labels.get(rule_slot)
        canvas = self.acl_rule_bar_canvases.get(rule_slot)
        if cell is None or title is None or value is None or canvas is None:
            return

        start_rgb = (255, 0, 0)
        end_rgb = (17, 24, 39)

        def mix(step: int, total: int) -> str:
            ratio = step / total
            r = int(start_rgb[0] + (end_rgb[0] - start_rgb[0]) * ratio)
            g = int(start_rgb[1] + (end_rgb[1] - start_rgb[1]) * ratio)
            b = int(start_rgb[2] + (end_rgb[2] - start_rgb[2]) * ratio)
            return f"#{r:02x}{g:02x}{b:02x}"

        def apply_frame(index: int) -> None:
            bg = mix(index, 9)
            cell.configure(bg=bg, highlightbackground="#fb7185" if index < 3 else self.colors["muted_border"])
            title.configure(bg=bg)
            value.configure(bg=bg, fg="#fecaca" if index < 5 else "#f8fafc")
            canvas.configure(bg="#2a0b0b" if index < 3 else "#0b1120")

        for idx in range(10):
            if idx == 0:
                apply_frame(idx)
            else:
                job = self.after(idx * 50, lambda i=idx: apply_frame(i))
                self.acl_rule_flash_jobs[rule_slot].append(job)

    def _handle_event(self, event: WorkerEvent) -> None:
        kind = event.kind
        payload = event.payload
        if kind == "connected":
            self.connection_state.set(f"Connected: {payload['port']}")
            self._set_link_visual("#86efac", "LINK ONLINE", "#bbf7d0")
            self._append_log(f"Connected to {payload['port']} @ {payload['baud']} baud", "pass")
            self._set_banner(f"Connected to {payload['port']} @ {payload['baud']} baud", "pass")
            self._refresh_runtime_views()
        elif kind == "disconnected":
            self.connection_state.set("Disconnected")
            self._set_link_visual("#fca5a5", "SIGNAL LOST", "#fecaca")
            self._append_log("Serial link disconnected", "warn")
            self._set_banner("Disconnected. Reconnect to continue testing.", "warn")
        elif kind == "error":
            self._set_link_visual("#fca5a5", "PORT FAULT", "#fecaca")
            self._append_log(f"ERROR: {payload['message']}", "error")
            self._set_banner(f"Error: {payload['message']}", "error")
        elif kind == "fatal_error":
            self._set_link_visual("#fca5a5", "FATAL ERROR", "#fecaca")
            fatal_reason = f"code=0x{int(payload['code']):02X}"
            if int(payload['code']) == 0x01:
                fatal_reason = "Stream Watchdog Timeout"
            elif int(payload['code']) == 0x02:
                fatal_reason = "Crypto Watchdog Timeout"
            self._append_log(f"FATAL: {fatal_reason} during {payload.get('name', 'unknown')}", "error")
            self._set_banner(f"FATAL ERROR: {fatal_reason}", "error")
        elif kind == "result":
            tx = payload["tx"]
            rx = payload["rx"]
            expected = payload["expected"]
            passed = payload["passed"]
            description = payload["description"]
            self._record_transport_activity(len(rx), float(payload["duration_s"]))
            if payload["stats"] is not None:
                self._apply_stats(payload["stats"])
            if payload["rule_stats"] is not None:
                self._apply_rule_stats(payload["rule_stats"])
            if rx == b"D\n":
                self._append_log(f"ACL BLOCK: {description} -> {format_hex(rx)}", "block")
                first_byte = self._extract_first_payload_byte(tx)
                if first_byte is not None and first_byte in self.rule_slot_keys:
                    slot = self.rule_slot_keys.index(first_byte)
                    label = self.rule_slot_labels[slot]
                    self._flash_rule_heat(slot)
                    self._set_banner(
                        f"Hardware firewall blocked the frame (ACL hit: slot {slot} / {label}).",
                        "block",
                    )
                else:
                    self._set_banner("Hardware firewall blocked the frame (ACL hit).", "block")
                self._schedule_rule_stats_refresh()
            elif rx == b"E\n":
                self._append_log(f"PROTOCOL ERROR: {description} -> {format_hex(rx)}", "error")
                self._set_banner("Protocol error returned by the board.", "error")
            elif payload["rule_stats"] is not None:
                counters = {
                    f"slot{idx}:{self.rule_slot_labels[idx]}": payload["rule_stats"].counts[idx]
                    for idx in range(8)
                }
                self._append_log(
                    "ACL RULE STATS: "
                    + " ".join(f"{key}={value}" for key, value in counters.items()),
                    "pass" if passed else "error",
                )
                counts = tuple(payload["rule_stats"].counts)
                hot_idx = max(range(8), key=lambda slot: counts[slot])
                hot_hits = counts[hot_idx]
                if hot_hits == 0:
                    self._set_banner("Board-side ACL rule counters refreshed (no hits yet).", "pass")
                else:
                    self._set_banner(
                        "Board-side ACL rule counters refreshed. "
                        f"Hot rule: slot {hot_idx} / {self.rule_slot_labels[hot_idx]} ({hot_hits} hits).",
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
        elif kind == "acl_v2_key_map":
            self._record_transport_activity(len(payload["rx"]), float(payload["duration_s"]))
            signatures = tuple(bytes(value) for value in payload["signatures"])
            self._apply_acl_key_map(signatures)
            rendered = " ".join(
                f"slot{idx}={self.rule_slot_labels[idx]}" for idx in range(len(self.rule_slot_labels))
            )
            self._append_log(f"ACL V2 KEY MAP: {rendered}", "pass" if payload["passed"] else "error")
            self._set_banner("Board-side ACL v2 key map refreshed.", "pass" if payload["passed"] else "error")
        elif kind == "acl_v2_write_ack":
            self._record_transport_activity(len(payload["rx"]), float(payload["duration_s"]))
            slot = int(payload["slot"])
            signature = bytes(payload["signature"])
            label = self._format_acl_v2_signature(signature)
            self._append_log(
                f"ACL V2 WRITE ACK: slot {slot} -> {label} ({format_hex(payload['rx'])})",
                "pass",
            )
            self.acl_rule_hit_vars[slot].set("0")
            self.acl_rule_last_counts[slot] = 0
            canvas = self.acl_rule_bar_canvases.get(slot)
            fill_id = self.acl_rule_bar_fills.get(slot)
            if canvas is not None and fill_id is not None:
                canvas.coords(fill_id, 0, 0, 0, 18)
                canvas.itemconfigure(fill_id, fill="#07111f")
            self._set_banner(
                f"ACL v2 slot {slot} deployed. Refreshing board view...",
                "pass",
            )
            self.worker.submit_case(case_acl_v2_keymap())
            self.worker.submit_case(case_acl_v2_hit_counters())
        elif kind == "acl_v2_hits":
            self._record_transport_activity(len(payload["rx"]), float(payload["duration_s"]))
            counts = tuple(int(value) for value in payload["counts"])
            self._apply_rule_stats(counts)
            counters = {
                f"slot{idx}:{self.rule_slot_labels[idx]}": counts[idx]
                for idx in range(8)
            }
            self._append_log(
                "ACL V2 HITS: " + " ".join(f"{key}={value}" for key, value in counters.items()),
                "pass" if payload["passed"] else "error",
            )
            self._set_banner(
                "Board-side ACL v2 hit counters refreshed.",
                "pass" if payload["passed"] else "error",
            )
        elif kind == "acl_key_map":
            self._record_transport_activity(len(payload["rx"]), float(payload["duration_s"]))
            keys = tuple(int(value) for value in payload["keys"])
            self._apply_acl_key_map(keys)
            rendered = " ".join(
                f"slot{idx}={self.rule_slot_labels[idx]}" for idx in range(len(self.rule_slot_labels))
            )
            self._append_log(f"ACL KEY MAP: {rendered}", "pass" if payload["passed"] else "error")
            self._set_banner("Board-side ACL key map refreshed.", "pass" if payload["passed"] else "error")
        elif kind == "acl_write_ack":
            self._record_transport_activity(len(payload["rx"]), float(payload["duration_s"]))
            slot = int(payload["index"])
            key = int(payload["key"])
            self._append_log(
                f"ACL WRITE ACK: slot {slot} -> {display_rule_byte(key)} ({format_hex(payload['rx'])})",
                "pass",
            )
            self.acl_rule_hit_vars[slot].set("0")
            self.acl_rule_last_counts[slot] = 0
            canvas = self.acl_rule_bar_canvases.get(slot)
            fill_id = self.acl_rule_bar_fills.get(slot)
            if canvas is not None and fill_id is not None:
                canvas.coords(fill_id, 0, 0, 0, 18)
                canvas.itemconfigure(fill_id, fill="#07111f")
            self._set_banner(
                f"ACL slot {slot} deployed to {display_rule_byte(key)}. Refreshing board view...",
                "pass",
            )
            self.worker.submit_case(case_acl_v2_keymap())
            self.worker.submit_case(case_acl_v2_hit_counters())
        elif kind == "acl_write_error":
            self._record_transport_activity(len(payload["rx"]), float(payload["duration_s"]))
            self._append_log(
                f"ACL WRITE REJECTED: {payload['description']} -> {format_hex(payload['rx'])}",
                "error",
            )
            self._set_banner("ACL runtime update rejected by the board.", "error")
        elif kind == "pmu_cleared":
            self._record_transport_activity(len(payload["rx"]), float(payload["duration_s"]))
            self._reset_pmu_display()
            self._append_log(
                f"PMU CLEARED: status={payload['status']} RX={format_hex(payload['rx'])}",
                "pass" if payload["passed"] else "error",
            )
            self._set_banner("Hardware PMU counters cleared.", "pass" if payload["passed"] else "error")
        elif kind == "trace_snapshot":
            self._apply_trace_snapshot(payload)
            self._append_log(
                f"TRACE SNAPSHOT: loaded {len(payload.get('entries', []))} entries",
                "info",
            )
            self._set_banner("Trace snapshot loaded.", "info")
        elif kind == "bench_result":
            self._apply_bench_result(payload)
            if payload.get("effective_mbps") is not None:
                self.evidence_live_vars["chip_mbps"].set(f"{float(payload['effective_mbps']):.3f} Mbps")
            self._append_log(
                "BENCH RESULT: "
                f"{payload.get('algo_name', payload.get('algo'))} "
                f"{payload.get('status_text', payload.get('status'))} "
                f"bytes={payload['byte_count']} cycles={payload['cycles']} "
                f"crc32=0x{int(payload['crc32']):08X}",
                "pass" if payload["passed"] else "error",
            )
            if payload.get("effective_mbps") is None:
                self._set_banner(
                    "On-chip benchmark result refreshed.",
                    "pass" if payload["passed"] else "error",
                )
            else:
                self._set_banner(
                    f"On-chip benchmark {payload.get('algo_name', payload.get('algo'))}: "
                    f"{float(payload['effective_mbps']):.3f} Mbps",
                    "pass" if payload["passed"] else "error",
                )
        elif kind == "pmu_snapshot":
            self._record_transport_activity(len(payload["rx"]), float(payload["duration_s"]))
            self._apply_pmu_snapshot(payload)
            source = str(payload.get("source", ""))
            self._update_live_evidence(payload)
            if self.evidence_frozen_active:
                self._update_frozen_from_live()
            else:
                self._apply_pmu_snapshot_to_evidencelive(payload)
            self._append_log(
                "PMU SNAPSHOT: "
                f"clk={payload['clk_hz']} "
                f"global={payload['global_cycles']} "
                f"crypto={payload['crypto_active_cycles']} "
                f"uart_stall={payload['uart_tx_stall_cycles']} "
                f"credit_block={payload['stream_credit_block_cycles']} "
                f"acl_events={payload['acl_block_events']} "
                f"stream_in={payload.get('stream_bytes_in', 0)} "
                f"stream_out={payload.get('stream_bytes_out', 0)} "
                f"chunks={payload.get('stream_chunk_count', 0)}",
                "pass" if payload["passed"] else "error",
            )
            self._set_banner(
                "PMU readback refreshed: "
                f"HW Util {float(payload['crypto_utilization']) * 100.0:.2f}% / "
                f"UART Stall {float(payload['uart_stall_ratio']) * 100.0:.2f}%",
                "pass" if payload["passed"] else "error",
            )
        elif kind == "file_begin":
            self._begin_file_status(payload)
            self._reset_frozen_evidence()
            self._append_log(
                f"FILE BEGIN {payload['algo']}: logical={payload['original_bytes']} transport={payload['total_bytes']} "
                f"pad={payload['pad_bytes']} chunks={payload['chunk_count']}",
                "info",
            )
        elif kind == "file_progress":
            elapsed_s = max(float(payload.get("elapsed_s", 0.001)), 1e-9)
            self._record_transport_activity(int(payload["chunk"]), elapsed_s)
            processed = int(payload["processed"])
            total = int(payload["total"])
            original_total = int(payload.get("original_total", total))
            pad_bytes = int(payload.get("pad_bytes", 0))
            chunk_index = int(payload.get("chunk_index", 0))
            chunk_count = int(payload.get("chunk_count", 0))
            self.file_done_chunks = chunk_index
            self.file_total_chunks = max(chunk_count, self.file_total_chunks)
            self.file_status_vars["progress"].set(f"{chunk_index} / {chunk_count} ACKed")
            self._draw_file_progress()
            self._flash_file_pulse(f"ACK {chunk_index}", "#082f49", "#7dd3fc")
            self._append_log(
                f"FILE {payload['algo']}: chunk {chunk_index}/{chunk_count} "
                f"{processed}/{total} bytes over UART (orig {original_total}, pad {pad_bytes}, chunk {payload['chunk']})",
                "info",
            )
            self._set_banner(
                f"Encrypting via {payload['algo']}: {processed}/{total} transport bytes "
                f"(orig {original_total}, pad {pad_bytes}) @ {float(payload['throughput_mbps']):.3f} Mbps",
                "info",
            )
        elif kind == "file_done":
            self.file_done_chunks = int(payload.get("chunk_count", self.file_done_chunks))
            self.file_total_chunks = max(self.file_total_chunks, self.file_done_chunks)
            self.file_status_vars["progress"].set(f"{self.file_done_chunks} / {self.file_total_chunks} ACKed")
            self._draw_file_progress()
            self._flash_file_pulse("DONE", "#14532d", "#dcfce7")
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
            wire_mbps = float(payload["throughput_mbps"])
            total_bytes = int(payload.get("total_bytes", 0))
            chunk_count = int(payload.get("chunk_count", 0))
            self.evidence_live_vars["wire_mbps"].set(f"{wire_mbps:.3f} Mbps")
            self.evidence_live_vars["stream_chunks"].set(str(chunk_count))
            self._freeze_evidence_snapshot(wire_mbps, total_bytes, chunk_count)


    def _poll_worker(self) -> None:
        for event in self.worker.poll_events():
            self._handle_event(event)
        self.after(80, self._poll_worker)

    def _on_close(self) -> None:
        if self.rule_refresh_job is not None:
            self.after_cancel(self.rule_refresh_job)
            self.rule_refresh_job = None
        if self.file_pulse_job is not None:
            self.after_cancel(self.file_pulse_job)
            self.file_pulse_job = None
        if self.throughput_sample_job is not None:
            self.after_cancel(self.throughput_sample_job)
            self.throughput_sample_job = None
        self.worker.stop()
        self.destroy()


def main() -> int:
    app = CryptoGatewayApp()
    app.mainloop()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())


