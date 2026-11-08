# UART + FIFO (Verilog RTL)

A small, self-contained RTL project: a parameterized synchronous FIFO, an 8N1
UART transmitter and receiver, and a top level that wraps both UART engines
with a FIFO in each direction.

Everything is simulated with Icarus Verilog, linted with Verilator, and can be
synthesized with Yosys.

## Layout

```
rtl/fifo.v        First-word-fall-through synchronous FIFO
rtl/uart_tx.v     8N1 transmitter (valid/ready handshake)
rtl/uart_rx.v     8N1 receiver, 16x oversampling, framing-error detection
rtl/uart_fifo.v   Top level: TX FIFO -> UART TX, UART RX -> RX FIFO

tb/tb_fifo.v      Directed + randomized self-checking FIFO test
tb/tb_uart_tx.v   Bit-level decoder checks every transmitted frame
tb/tb_uart_rx.v   Drives synthetic serial frames + framing-error test
tb/tb_uart_fifo.v Loopback integration test with backpressure

Makefile          test / lint / synth / wave / clean targets
```

## Quick start

```sh
make test        # build and run all four testbenches
make test_real   # RX test at 50 MHz / 115200 baud
make lint        # verilator --lint-only
make synth       # yosys stat report for uart_fifo
make wave_tb_uart_fifo   # open the integration waveform in gtkwave
```

Individual test:

```sh
make run_tb_uart_rx
```

## Top level

```verilog
uart_fifo #(
    .CLK_FREQ   (50_000_000),
    .BAUD_RATE  (115200),
    .FIFO_DEPTH (16)          // must be a power of two
) u_uart (
    .clk (clk),
    .rst (rst),               // synchronous, active high

    // Host -> UART
    .tx_wr_en (tx_wr_en),     // push byte when !tx_full
    .tx_din   (tx_din),
    .tx_full  (tx_full),
    .tx_empty (tx_empty),
    .tx_count (tx_count),
    .tx_done  (tx_done),      // 1-clock pulse at end of each frame

    // Pins
    .tx (tx),
    .rx (rx),

    // UART -> host
    .rx_rd_en (rx_rd_en),     // pop byte when !rx_empty
    .rx_dout  (rx_dout),      // valid while rx_empty is low
    .rx_empty (rx_empty),
    .rx_full  (rx_full),
    .rx_count (rx_count),
    .rx_frame_err (rx_frame_err) // 1-clock pulse on a bad stop bit
);
```

## Design notes

**FIFO.** First-word-fall-through: `dout` is combinational and always shows the
oldest entry, so a consumer can inspect data before popping. An extra pointer
bit distinguishes full from empty, so `DEPTH` must be a power of two.
Simultaneous read and write are supported. On an FPGA this style of read
infers distributed/LUT RAM; switch to a registered read (and add a one-cycle
read latency) if you need block RAM.

**UART TX.** 8N1, LSB first. A byte is accepted when `valid && ready`. `ready`
is high only while idle, so a streaming source must hold `valid`/`data` stable
until the handshake completes. `done` pulses at the end of the stop bit.

**UART RX.** 16x oversampling. The line goes through a two-flop synchronizer.
Falling edges are latched so a start bit is not lost between sample ticks. The
start bit is verified at its midpoint and every data bit is sampled at its
midpoint. A low stop bit pulses `frame_err`; the receiver then waits for a real
high-to-low edge before accepting another frame, so a stuck-low line cannot
retrigger noise frames.

**Baud accuracy.** Both engines derive their dividers with integer division:

```
TX: CLKS_PER_BIT    = CLK_FREQ / BAUD_RATE
RX: CLKS_PER_SAMPLE = CLK_FREQ / (BAUD_RATE * 16)
```

Choose a clock/baud pair that divides cleanly, or accept the usual small
rounding error. RX requires `CLK_FREQ >= BAUD_RATE * 16` (and practically much
more, so oversampling has resolution).

## Tests

The testbenches use small, exactly-dividing clock/baud numbers (`CLK_FREQ =
1600`, `BAUD_RATE = 100`, i.e. 16 clocks/bit) so they run in milliseconds and
check bit timing precisely.

- `tb_fifo`: fill/drain, full/empty behavior, ignored writes when full, and
  4000 randomized read/write cycles against a golden queue.
- `tb_uart_tx`: decodes start/data/stop bits at their midpoints for several
  bytes, including `0x00` and `0xFF`, and checks the `done` pulse count.
- `tb_uart_rx`: decodes clean and back-to-back frames, checks a deliberate
  framing error, and confirms recovery on the next valid frame.
- `tb_uart_fifo`: loopback with a flow-controlled producer and a draining
  consumer; verifies byte order, that backpressure asserts `tx_full`, and that
  both FIFOs end empty.

The receiver testbench is parameterized and can be run with a realistic
(non-exact) clock divider via `make test_real` (`50 MHz` / `115200` baud).

## License

MIT — see [LICENSE](LICENSE).

