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

    def test_evidence_dashboard_tracks_live_and_frozen_metrics(self) -> None:
        app = gui.CryptoGatewayApp()
        try:
            self.assertTrue(hasattr(app, "evidence_live_vars"))
            self.assertTrue(hasattr(app, "evidence_frozen_vars"))

            app._handle_event(
                gui.WorkerEvent(
                    kind="file_done",
                    payload={
                        "path": "safe_stream_512kb.bin",
                        "output_path": "safe_stream_512kb.bin.sm4.bin",
                        "algo": "SM4",
                        "total_bytes": 512,
                        "original_bytes": 512,
                        "pad_bytes": 0,
                        "chunk_count": 4,
                        "duration_s": 1.0,
                        "throughput_mbps": 1.024,
                    },
                )
            )
            app._handle_event(
                gui.WorkerEvent(
                    kind="pmu_snapshot",
                    payload={
                        "source": "file_session",
                        "rx": bytes.fromhex("55 46 50 02"),
                        "duration_s": 0.001,
                        "passed": True,
                        "clk_hz": 50_000_000,
                        "global_cycles": 1000,
                        "crypto_active_cycles": 250,
                        "uart_tx_stall_cycles": 500,
                        "stream_credit_block_cycles": 125,
                        "acl_block_events": 0,
                        "crypto_utilization": 0.25,
                        "uart_stall_ratio": 0.5,
                        "credit_block_ratio": 0.125,
                        "stream_bytes_in": 512,
                        "stream_bytes_out": 512,
                        "stream_chunk_count": 4,
                    },
                )
            )

            self.assertEqual(app.evidence_frozen_vars["wire_mbps"].get(), "1.024 Mbps")
            self.assertEqual(app.evidence_frozen_vars["stream_in"].get(), "512 B")
            self.assertEqual(app.evidence_frozen_vars["stream_out"].get(), "512 B")
            self.assertEqual(app.evidence_frozen_vars["stream_chunks"].get(), "4")

            app._handle_event(
                gui.WorkerEvent(
                    kind="bench_result",
                    payload={
                        "source": "bench_session",
                        "status": 0,
                        "algo": 0x53,
                        "byte_count": 1_048_576,
                        "cycles": 65536,
                        "crc32": 0x12345678,
                        "effective_mbps": 200.0,
                        "passed": True,
                        "rx": bytes.fromhex("55 14 62 01"),
                        "duration_s": 0.001,
                    },
                )
            )
            app._handle_event(
                gui.WorkerEvent(
                    kind="pmu_snapshot",
                    payload={
                        "source": "bench_session",
                        "rx": bytes.fromhex("55 46 50 02"),
                        "duration_s": 0.001,
                        "passed": True,
                        "clk_hz": 50_000_000,
                        "global_cycles": 2000,
                        "crypto_active_cycles": 1000,
                        "uart_tx_stall_cycles": 500,
                        "stream_credit_block_cycles": 0,
                        "acl_block_events": 0,
                        "crypto_utilization": 0.5,
                        "uart_stall_ratio": 0.25,
                        "credit_block_ratio": 0.0,
                        "stream_bytes_in": 0,
                        "stream_bytes_out": 0,
                        "stream_chunk_count": 0,
                    },
                )
            )

            self.assertEqual(app.evidence_live_vars["chip_mbps"].get(), "200.000 Mbps")
            self.assertEqual(app.evidence_frozen_vars["wire_mbps"].get(), "1.024 Mbps")
            self.assertEqual(app.evidence_frozen_vars["stream_chunks"].get(), "4")
        finally:
            app.destroy()


    def test_file_begin_clears_frozen_evidence_snapshot(self) -> None:
        app = gui.CryptoGatewayApp()
        try:
            app.evidence_frozen_active = True
            app.evidence_frozen_vars["wire_mbps"].set("1.024 Mbps")
            app.evidence_frozen_vars["chip_mbps"].set("200.000 Mbps")
            app.evidence_frozen_vars["gap_ratio"].set("99.5%")
            app.evidence_frozen_vars["stream_chunks"].set("4")

            app._handle_event(
                gui.WorkerEvent(
                    kind="file_begin",
                    payload={
                        "path": "safe_stream_512kb.bin",
                        "algo": "SM4",
                        "original_bytes": 512,
                        "total_bytes": 512,
                        "pad_bytes": 0,
                        "chunk_count": 4,
                    },
                )
            )

            self.assertFalse(app.evidence_frozen_active)
            self.assertEqual(app.evidence_frozen_vars["wire_mbps"].get(), "- Mbps")
            self.assertEqual(app.evidence_frozen_vars["chip_mbps"].get(), "- Mbps")
            self.assertEqual(app.evidence_frozen_vars["gap_ratio"].get(), "-")
            self.assertEqual(app.evidence_frozen_vars["stream_chunks"].get(), "-")
        finally:
            app.destroy()

    def test_runtime_refresh_uses_acl_v2_queries(self) -> None:
        app = gui.CryptoGatewayApp()
        try:
            with mock.patch.object(app.worker, "submit_case") as submit_case:
                app._refresh_runtime_views()
            kinds = [call.args[0].kind for call in submit_case.call_args_list]
            self.assertIn("acl_v2_keymap", kinds)
            self.assertIn("acl_v2_hits", kinds)
            self.assertNotIn("acl_key_map", kinds)
            self.assertNotIn("rule_stats", kinds)
        finally:
            app.destroy()

    def test_deploy_acl_rule_rejects_legacy_two_hex_v1_shape(self) -> None:
        app = gui.CryptoGatewayApp()
        try:
            app.deploy_rule_slot.set(2)
            app.deploy_rule_key.set("51")
            with mock.patch.object(gui.messagebox, "showerror") as showerror:
                with mock.patch.object(app.worker, "submit_case") as submit_case:
                    app._deploy_acl_rule()
            submit_case.assert_not_called()
            showerror.assert_called_once()
        finally:
            app.destroy()

    def test_fatal_error_does_not_open_modal_dialog(self) -> None:
        app = gui.CryptoGatewayApp()
        try:
            with mock.patch.object(gui.messagebox, "showerror") as showerror:
                app._handle_event(
                    gui.WorkerEvent(
                        kind="fatal_error",
                        payload={"code": 0x01, "name": "stream_encrypt_file_v3_on_serial"},
                    )
                )
            showerror.assert_not_called()
            self.assertIn("FATAL ERROR", app.banner_text.get())
        finally:
            app.destroy()

    def test_poll_and_throughput_reschedule_at_80ms(self) -> None:
        app = gui.CryptoGatewayApp()
        try:
            with mock.patch.object(app.worker, "poll_events", return_value=[]):
                with mock.patch.object(app, "after", return_value="poll_job") as after:
                    app._poll_worker()
                self.assertEqual(after.call_args.args[0], 80)
                self.assertIs(after.call_args.args[1].__self__, app)
                self.assertEqual(after.call_args.args[1].__func__, app._poll_worker.__func__)

            with mock.patch.object(app, "after", return_value="sample_job") as after:
                with mock.patch.object(app, "_draw_chart"):
                    with mock.patch.object(gui.time, "perf_counter", return_value=app.last_sample_at + 0.08):
                        app._sample_throughput()
                self.assertEqual(after.call_args.args[0], 80)
                self.assertIs(after.call_args.args[1].__self__, app)
                self.assertEqual(after.call_args.args[1].__func__, app._sample_throughput.__func__)
                self.assertEqual(app.throughput_sample_job, "sample_job")
        finally:
            app.destroy()
    def test_runtime_error_does_not_open_modal_dialog(self) -> None:
        app = gui.CryptoGatewayApp()
        try:
            with mock.patch.object(gui.messagebox, "showerror") as showerror:
                app._handle_event(gui.WorkerEvent(kind="error", payload={"message": "serial timeout"}))
            showerror.assert_not_called()
            self.assertIn("serial timeout", app.banner_text.get())
        finally:
            app.destroy()

    def test_file_done_does_not_open_completion_modal(self) -> None:
        app = gui.CryptoGatewayApp()
        try:
            with mock.patch.object(gui.messagebox, "showinfo") as showinfo:
                app._handle_event(
                    gui.WorkerEvent(
                        kind="file_done",
                        payload={
                            "path": "safe_stream_512kb.bin",
                            "output_path": "safe_stream_512kb.bin.sm4.bin",
                            "algo": "SM4",
                            "total_bytes": 512,
                            "original_bytes": 512,
                            "pad_bytes": 0,
                            "chunk_count": 4,
                            "duration_s": 1.0,
                            "throughput_mbps": 1.024,
                        },
                    )
                )
            showinfo.assert_not_called()
            self.assertIn("File encryption finished", app.banner_text.get())
        finally:
            app.destroy()
if __name__ == "__main__":
    unittest.main()
