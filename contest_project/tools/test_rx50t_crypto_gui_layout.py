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
            self.assertLessEqual(app.control_panel.winfo_reqheight(), 500)
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


if __name__ == "__main__":
    unittest.main()
