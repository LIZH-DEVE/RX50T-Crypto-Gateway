# RX50T Crypto Gateway

`RX50T Crypto Gateway` is a pure-`PL` security datapath for the `RX50T` board.

Current merged baseline on `main` includes:
- `P1`: clock-gated crypto island + `PMU v3`
- `P2`: BRAM-backed trace buffer with paged UART readback
- `P3-A`: `125MHz ingress -> AFIFO -> 50MHz crypto/control`
- `P3-B`: MAC-facing ingress prototype top and sustained-throughput regressions
- `P3-C1`: `50MHz root TX -> skid buffer -> egress AFIFO -> 125MHz UART TX`

Current silicon-closed tag:
- `v1.0-cdc-closure`

The production shell remains:
- `UART @ 2,000,000 8N1`
- `ACL v2`
- `AES-128 / SM4-128`
- `PMU / trace / watchdog / on-chip bench`

## Hard Requirement

Vivado and XSIM path length is a hard physical precondition, not a recommendation.

- repository root absolute path length must be `<= 40`
- supported example path: `D:\rx50t_gateway`
- if the repo is longer than that, do not continue; move it first

Required local environment:
- `Vivado 2024.1`
- `Python 3.12`
- `tkinter` available in that Python installation

Generated artifacts are not source of truth:
- do not hand off `contest_project/build/`
- do not rely on `.xpr`, `.runs`, `.bit`, or generated Tcl under `contest_project/build/`
- the authoritative handoff baseline is tracked source + `README.md` + `requirements-dev.txt` + `contest_project/scripts/`

## One Command

Fresh clone, short path, then run:

```powershell
powershell -ExecutionPolicy Bypass -File .\contest_project\scripts\teammate_init.ps1
```

When you want the script to program the board and run the fixed smoke matrix:

```powershell
powershell -ExecutionPolicy Bypass -File .\contest_project\scripts\teammate_init.ps1 -BoardSmoke -Port <PORT>
```

If multiple JTAG devices are present:

```powershell
powershell -ExecutionPolicy Bypass -File .\contest_project\scripts\teammate_init.ps1 -BoardSmoke -Port <PORT> -HwDeviceIndex <N>
```

## What `teammate_init.ps1` Does

- enforces the short-path hard requirement
- locates `Vivado 2024.1`
- creates or reuses `.venv`
- installs `requirements-dev.txt`
- checks `tkinter`
- runs the release sanity matrix:
  - `python -m pytest contest_project/tools -q`
  - `build_tb_uart_crypto_probe_cdc_ingress.ps1`
  - `build_tb_uart_crypto_probe_cdc_egress.ps1`
  - `build_tb_uart_crypto_probe_trace.ps1`
  - `build_tb_uart_crypto_probe_watchdog.ps1`
- enumerates serial ports
- enumerates JTAG devices
- when `-BoardSmoke` is present:
  - programs the production bitstream through the tracked hardware entrypoint
  - runs `query-pmu -> query-trace -> run-onchip-bench(sm4) -> query-bench -> query-trace`

## Hardware Entry Points

- tracked programmer:
  - `contest_project/scripts/program_hw_target.ps1`
  - `contest_project/scripts/program_hw_target.tcl`
- these scripts do not bind any fixed JTAG target id or device name
- default rule:
  - if exactly one JTAG device exists, it is selected automatically
  - if multiple JTAG devices exist, you must pass `-HwDeviceIndex`

Serial-port rule:
- host CLI must always use explicit `--port <PORT>`
- GUI no longer defaults to any hard-coded COM port
- if only one serial port exists, GUI may prefill it
- if zero or multiple serial ports exist, GUI waits for explicit selection

## Production Facts

Production UART interface is unchanged:
- frame wrapper: `55 LEN PAYLOAD`
- no new public UART protocol was added for `P3-C1`
- `ACL / PMU / trace / watchdog / bench` remain host-visible on the same shell

Current production bitstream build entrypoint:

```powershell
powershell -ExecutionPolicy Bypass -File .\contest_project\scripts\build_rx50t_uart_crypto_probe.ps1
```

## Boundaries

- no `ARM/PS`
- no `DMA / DDR / PBM`
- no full `Ethernet/IP/UDP`
- no persistent ACL storage
- no `PUF / hardware key derivation`
- MAC-facing ingress remains a prototype path, not the production board shell

## Historical Notes

- `daily-progress/` and older docs may still contain historical board evidence such as prior COM-port numbers
- those files are historical records, not the authoritative onboarding path
- the only authoritative onboarding entrypoints are this `README.md` and `contest_project/scripts/teammate_init.ps1`
