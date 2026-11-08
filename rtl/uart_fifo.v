// -----------------------------------------------------------------------------
// uart_fifo.v
//
// UART with a FIFO on each direction.
//
//   Transmit path:  host writes bytes into the TX FIFO (tx_wr_en/tx_din).
//                   The transmitter pops them automatically and shifts them
//                   out of `tx`.
//   Receive path:   bytes received on `rx` are pushed into the RX FIFO.
//                   The host pops them with rx_rd_en; rx_dout is valid while
//                   rx_empty is low (first-word-fall-through).
//
// `tx_full` / `rx_empty` should be used for flow control by the host.
// `rx_frame_err` is a one-clock pulse on a bad stop bit.
// -----------------------------------------------------------------------------
`timescale 1ns/1ps
`default_nettype none

module uart_fifo #(
    parameter integer CLK_FREQ   = 50_000_000,
    parameter integer BAUD_RATE  = 115200,
    parameter integer FIFO_DEPTH = 16,
    // Do not override; derived from FIFO_DEPTH for the port list below.
    parameter integer FIFO_AW    = $clog2(FIFO_DEPTH)
) (
    input  wire             clk,
    input  wire             rst,       // synchronous, active high

    // Transmit path (host -> UART)
    input  wire             tx_wr_en,
    input  wire [7:0]       tx_din,
    output wire             tx_full,
    output wire             tx_empty,
    output wire [FIFO_AW:0] tx_count,
    output wire             tx_done,

    // UART pins
    output wire             tx,
    input  wire             rx,

    // Receive path (UART -> host)
    input  wire             rx_rd_en,
    output wire [7:0]       rx_dout,
    output wire             rx_empty,
    output wire             rx_full,
    output wire [FIFO_AW:0] rx_count,
    output wire             rx_frame_err
);

    // ---------------------------------------------------------------- TX path
    wire [7:0] tx_fifo_dout;
    wire       tx_fifo_empty;
    wire       tx_ready;

    // Pop the TX FIFO only when the transmitter can actually take a byte.
    wire tx_fifo_rd_en = !tx_fifo_empty && tx_ready;

    fifo #(
        .WIDTH  (8),
        .DEPTH  (FIFO_DEPTH),
        .ADDR_W (FIFO_AW)
    ) tx_fifo (
        .clk   (clk),
        .rst   (rst),
        .wr_en (tx_wr_en),
        .din   (tx_din),
        .rd_en (tx_fifo_rd_en),
        .dout  (tx_fifo_dout),
        .full  (tx_full),
        .empty (tx_fifo_empty),
        .count (tx_count)
    );

    uart_tx #(
        .CLK_FREQ  (CLK_FREQ),
        .BAUD_RATE (BAUD_RATE)
    ) u_tx (
        .clk   (clk),
        .rst   (rst),
        .valid (!tx_fifo_empty),
        .data  (tx_fifo_dout),
        .ready (tx_ready),
        .tx    (tx),
        .done  (tx_done)
    );

    assign tx_empty = tx_fifo_empty;

    // ---------------------------------------------------------------- RX path
    wire [7:0] rx_fifo_din;
    wire       rx_valid;
    wire       rx_frame_err_pulse;

    uart_rx #(
        .CLK_FREQ  (CLK_FREQ),
        .BAUD_RATE (BAUD_RATE)
    ) u_rx (
        .clk        (clk),
        .rst        (rst),
        .rx         (rx),
        .data_out   (rx_fifo_din),
        .data_valid (rx_valid),
        .frame_err  (rx_frame_err_pulse)
    );

    // Drop received bytes if the RX FIFO is full (host is not draining).
    wire rx_fifo_wr_en = rx_valid && !rx_full;

    fifo #(
        .WIDTH  (8),
        .DEPTH  (FIFO_DEPTH),
        .ADDR_W (FIFO_AW)
    ) rx_fifo (
        .clk   (clk),
        .rst   (rst),
        .wr_en (rx_fifo_wr_en),
        .din   (rx_fifo_din),
        .rd_en (rx_rd_en),
        .dout  (rx_dout),
        .full  (rx_full),
        .empty (rx_empty),
        .count (rx_count)
    );

    assign rx_frame_err = rx_frame_err_pulse;

endmodule

`default_nettype wire
