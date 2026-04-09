# UART Echo Priority

`contest_uart_io.sv` is the first survival line of the contest version.

Current implementation scope:

- fixed UART format: `8N1`
- default baud: `115200`
- default clock assumption: `50MHz`
- two-flop RX synchronizer
- RX -> small FIFO -> TX echo path
- sticky `frame_error` and `overrun` flags

Current files:

- `contest_project/rtl/contest/contest_uart_rx.sv`
- `contest_project/rtl/contest/contest_uart_tx.sv`
- `contest_project/rtl/contest/contest_uart_fifo.sv`
- `contest_project/rtl/contest/contest_uart_io.sv`
- `contest_project/rtl/contest/rx50t_uart_echo_top.sv`
- `contest_project/tb/contest/tb_uart_echo.sv`

Immediate next step after syntax / sim confirmation:

1. run UART echo simulation
2. bind top-level ports to RX50T UART pins
3. burn echo bitstream
4. verify PC -> board -> PC raw byte loopback
5. only then insert parser / ACL / AES / SM4 into the middle of the path
