import unittest
from unittest import mock

import rx50t_crypto_gui as gui


class CryptoGatewayGuiLayoutTests(unittest.TestCase):
    def test_dashboard_exposes_three_zone_layout(self) -> None:
        app = gui.CryptoGatewayApp()
        try:
            app.update_idletasks()
            self.assertTrue(hasattr(app, "main_zone"))
            self.assertTrue(hasattr(app, "aux_zone"))
            self.assertTrue(hasattr(app, "footer_zone"))
            self.assertTrue(hasattr(app, "telemetry_zone"))
            self.assertTrue(hasattr(app, "acl_zone"))
            self.assertTrue(hasattr(app, "file_demo_zone"))
            self.assertTrue(hasattr(app, "wave_zone"))
            self.assertTrue(hasattr(app, "live_log_zone"))
            self.assertEqual(len(app.acl_rule_bar_canvases), 8)
            self.assertSetEqual(
                set(app.stat_value_labels.keys()),
                {"total", "acl", "aes", "sm4", "err"},
            )
            self.assertFalse(hasattr(app, "banner"))
        finally:
            app.destroy()

    def test_layout_preserves_footer_and_progress_safety_margins(self) -> None:
        app = gui.CryptoGatewayApp()
        try:
            app.update()
            footer_row = app.shell.grid_rowconfigure(2)
            self.assertGreaterEqual(int(footer_row["minsize"]), 180)
            self.assertGreaterEqual(int(app.file_progress_canvas.cget("height")), 72)
            self.assertFalse(hasattr(app, "file_progress_caption"))
            aux_log_row = app.aux_zone.grid_rowconfigure(1)
            self.assertGreaterEqual(int(aux_log_row["minsize"]), 220)
            self.assertGreaterEqual(int(app.log_box.cget("height")), 14)
            self.assertEqual(str(app.control_panel.grid_info()["sticky"]), "ew")
            first_rule = next(iter(app.acl_rule_cells.values()))
            self.assertLessEqual(first_rule.winfo_reqheight(), 76)
            self.assertLessEqual(app.control_panel.winfo_reqheight(), 620)
            self.assertGreaterEqual(app.live_log_zone.winfo_height(), 180)
            self.assertGreaterEqual(app.log_box.winfo_height(), 120)
        finally:
            app.destroy()

    def test_connected_event_triggers_runtime_readback(self) -> None:
        app = gui.CryptoGatewayApp()
        try:
            with mock.patch.object(app, "_refresh_runtime_views") as refresh:
                app._handle_event(gui.WorkerEvent(kind="connected", payload={"port": "COM12", "baud": 2_000_000}))
                refresh.assert_called_once_with()
                self.assertEqual(app.connection_state.get(), "Connected: COM12")
        finally:
            app.destroy()

    def test_gui_defaults_to_high_speed_uart(self) -> None:
        app = gui.CryptoGatewayApp()
        try:
            self.assertEqual(app.current_baud.get(), 2_000_000)
        finally:
            app.destroy()

    def test_force_run_button_submits_force_bench_case_via_worker(self) -> None:
        app = gui.CryptoGatewayApp()
        try:
            app.bench_algo.set("AES")
            with mock.patch.object(app.worker, "submit_case") as submit_case:
                app._force_run_bench()

            submit_case.assert_called_once()
            case = submit_case.call_args.args[0]
            self.assertEqual(case.kind, "bench_force")
            self.assertEqual(case.tx, bytes([0x55, 0x03, 0x62, 0xFF, 0x41]))
        finally:
            app.destroy()

    def test_pmu_events_update_and_clear_runtime_panel(self) -> None:
        app = gui.CryptoGatewayApp()
        try:
            app._handle_event(
                gui.WorkerEvent(
                    kind="pmu_snapshot",
                    payload={
                        "rx": bytes.fromhex("55 2E 50 01"),
                        "duration_s": 0.001,
                        "passed": True,
                        "clk_hz": 50_000_000,
                        "global_cycles": 1000,
                        "crypto_active_cycles": 250,
                        "uart_tx_stall_cycles": 500,
                        "stream_credit_block_cycles": 125,
                        "acl_block_events": 2,
                        "crypto_utilization": 0.25,
                        "uart_stall_ratio": 0.5,
                        "credit_block_ratio": 0.125,
                    },
                )
            )
            self.assertEqual(app.pmu_vars["hw_util"].get(), "25.00%")
            self.assertEqual(app.pmu_vars["uart_stall"].get(), "50.00%")
            self.assertEqual(app.pmu_vars["credit_block"].get(), "12.50%")
            self.assertEqual(app.pmu_vars["acl_events"].get(), "2")

            app._handle_event(
                gui.WorkerEvent(
                    kind="pmu_cleared",
                    payload={"rx": bytes([0x55, 0x02, 0x4A, 0x00]), "duration_s": 0.001, "passed": True, "status": 0},
                )
            )
            self.assertEqual(app.pmu_vars["hw_util"].get(), "0.0%")
            self.assertEqual(app.pmu_vars["uart_stall"].get(), "0.0%")
            self.assertEqual(app.pmu_vars["credit_block"].get(), "0.0%")
            self.assertEqual(app.pmu_vars["acl_events"].get(), "0")
        finally:
            app.destroy()

    def test_benchmark_panel_exists_and_bench_event_does_not_touch_uart_throughput(self) -> None:
        app = gui.CryptoGatewayApp()
        try:
            self.assertTrue(hasattr(app, "bench_vars"))
            self.assertTrue(hasattr(app, "bench_panel"))
            self.assertEqual(app.pending_transport_bytes, 0)
            self.assertEqual(app.throughput_label.get(), "0.000 Mbps")

            app._handle_event(
                gui.WorkerEvent(
                    kind="bench_result",
                    payload={
                        "status": 0,
                        "algo": 0x53,
                        "byte_count": 1_048_576,
                        "cycles": 65_536,
                        "crc32": 0x12345678,
                        "effective_mbps": 6400.0,
                        "passed": True,
                        "rx": bytes.fromhex("55 14 62 01"),
                        "duration_s": 0.001,
                    },
                )
            )

            self.assertEqual(app.bench_vars["status"].get(), "SUCCESS")
            self.assertEqual(app.bench_vars["mbps"].get(), "6400.000 Mbps")
            self.assertEqual(app.bench_vars["cycles"].get(), "65536")
            self.assertEqual(app.bench_vars["crc32"].get(), "0x12345678")
            self.assertEqual(app.pending_transport_bytes, 0)
            self.assertEqual(app.throughput_label.get(), "0.000 Mbps")
        finally:
            app.destroy()


if __name__ == "__main__":
    unittest.main()
