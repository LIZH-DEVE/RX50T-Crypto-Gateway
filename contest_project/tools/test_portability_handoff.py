from pathlib import Path
import unittest
from unittest import mock

import rx50t_crypto_gui as gui


REPO_ROOT = Path(__file__).resolve().parents[2]


class PortabilityHandoffTests(unittest.TestCase):
    def test_authoritative_handoff_entrypoints_exist(self) -> None:
        required_paths = [
            REPO_ROOT / "requirements-dev.txt",
            REPO_ROOT / "contest_project" / "scripts" / "teammate_init.ps1",
            REPO_ROOT / "contest_project" / "scripts" / "program_hw_target.ps1",
            REPO_ROOT / "contest_project" / "scripts" / "program_hw_target.tcl",
        ]

        missing = [str(path.relative_to(REPO_ROOT)) for path in required_paths if not path.exists()]
        self.assertEqual(missing, [], f"missing portability entrypoints: {missing}")

    def test_authoritative_files_do_not_hardcode_old_repo_root(self) -> None:
        files_to_check = [
            REPO_ROOT / "README.md",
            REPO_ROOT / "contest_project" / "scripts" / "build_rx50t_uart_acl_probe.ps1",
            REPO_ROOT / "contest_project" / "scripts" / "build_rx50t_uart_parser_probe.ps1",
            REPO_ROOT / "contest_project" / "scripts" / "build_rx50t_uart_sm4_probe.ps1",
            REPO_ROOT / "contest_project" / "scripts" / "create_rx50t_uart_acl_probe_project.tcl",
            REPO_ROOT / "contest_project" / "scripts" / "create_rx50t_uart_parser_probe_project.tcl",
            REPO_ROOT / "contest_project" / "scripts" / "create_rx50t_uart_sm4_probe_project.tcl",
        ]
        legacy_repo_root_windows = "\\".join(["D:", "FPGAhanjia", "jichuangsai"])
        legacy_repo_root_posix = "/".join(["D:", "FPGAhanjia", "jichuangsai"])
        forbidden = (
            legacy_repo_root_windows,
            legacy_repo_root_posix,
        )

        offenders = []
        for path in files_to_check:
            text = path.read_text(encoding="utf-8")
            if any(marker in text for marker in forbidden):
                offenders.append(str(path.relative_to(REPO_ROOT)))

        self.assertEqual(offenders, [], f"tracked authoritative files still hardcode old repo root: {offenders}")

    def test_readme_does_not_hardcode_com12(self) -> None:
        readme = (REPO_ROOT / "README.md").read_text(encoding="utf-8")
        legacy_port = "COM" + "12"
        self.assertNotIn(legacy_port, readme)

    def test_tracked_text_sources_do_not_hardcode_com12_or_old_repo_root(self) -> None:
        roots_to_scan = [
            REPO_ROOT / "README.md",
            REPO_ROOT / "docs",
            REPO_ROOT / "contest_project" / "constraints",
            REPO_ROOT / "contest_project" / "scripts",
            REPO_ROOT / "contest_project" / "tools",
        ]
        allowed_suffixes = {".md", ".py", ".ps1", ".tcl", ".txt", ".xdc"}
        legacy_port = "COM" + "12"
        legacy_repo_root_windows = "\\".join(["D:", "FPGAhanjia", "jichuangsai"])
        legacy_repo_root_posix = "/".join(["D:", "FPGAhanjia", "jichuangsai"])
        forbidden = (
            legacy_port,
            legacy_repo_root_windows,
            legacy_repo_root_posix,
        )

        offenders = []
        for root in roots_to_scan:
            paths = [root] if root.is_file() else sorted(path for path in root.rglob("*") if path.is_file())
            for path in paths:
                if path.suffix.lower() not in allowed_suffixes:
                    continue
                text = path.read_text(encoding="utf-8")
                if any(marker in text for marker in forbidden):
                    offenders.append(str(path.relative_to(REPO_ROOT)))

        self.assertEqual(offenders, [], f"tracked text sources still hardcode the legacy UART port or old repo root: {offenders}")

    def test_gui_leaves_port_empty_when_no_serial_ports_are_detected(self) -> None:
        with mock.patch.object(gui.GatewayWorker, "list_ports", return_value=[]):
            app = gui.CryptoGatewayApp()
            try:
                self.assertEqual(app.current_port.get(), "")
            finally:
                app.destroy()

    def test_gui_leaves_port_empty_when_multiple_serial_ports_are_detected(self) -> None:
        with mock.patch.object(gui.GatewayWorker, "list_ports", return_value=["COM7", "COM8"]):
            app = gui.CryptoGatewayApp()
            try:
                self.assertEqual(app.current_port.get(), "")
            finally:
                app.destroy()
