# RX50T UART Echo Board Test

## Current board mapping

- `i_clk` -> `Y18`
- `i_rst_n` -> `J20` (`KEY1`)
- `i_uart_rx` -> `J1`
- `o_uart_tx` -> `K1`

Board source:

- `A7-50T资源约束表.xlsx` screenshot
- confirmed rows:
  - `50MHz / PL_CLK -> Y18`
  - `USB-UART RX -> J1`
  - `USB-UART TX -> K1`

## Important note

`USB-UART RX/TX` naming may be from the USB bridge perspective instead of the FPGA perspective.

If the first bitstream shows no echo at all, keep the same RTL and only swap the UART pins once:

- `i_uart_rx -> K1`
- `o_uart_tx -> J1`

## Test procedure

1. Synthesize and implement `rx50t_uart_echo_top`
2. Load the bitstream to RX50T
3. Open a serial terminal on the RX50T COM port
4. Configure:
   - `115200`
   - `8N1`
   - no flow control
5. Press `KEY1` once to reset
6. Send:
   - `U`
   - `Hello`
   - `1234567890`
7. Expected behavior:
   - characters are echoed back exactly
   - no random bytes
   - no missing bytes
   - repeated reset still works

## If first test fails

### Case 1: no output at all

Swap `J1/K1` in the XDC and retest.

### Case 2: output exists but is garbled

Check:

- actual board clock really is `50MHz`
- terminal baud is `115200`
- logic level / COM port is correct

### Case 3: first few bytes correct, then broken

Focus on:

- UART FIFO behavior
- reset stability
- terminal auto line-ending settings

## Success gate

The UART path is considered open only when the board can echo a long ASCII string with:

- exact byte-for-byte return
- no dropped bytes
- no extra bytes
- repeatable behavior after reset
